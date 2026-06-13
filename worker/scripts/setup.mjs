#!/usr/bin/env node
// 一键部署引导（issue #18 / #19）：建 R2 桶 + D1（自动写回 id）+ 迁移 + 设密钥 + 部署。
// 仅询问真正需要人输入的项；幂等可重跑。默认用免费 *.workers.dev，自定义域名可选。
//   用法：cd worker && npm install && npm run setup
import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { createInterface } from 'node:readline/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const workerDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const wranglerPath = join(workerDir, 'wrangler.jsonc');
const DB_NAME = 'child-video-db';
const BUCKET = 'child-video';

const rl = createInterface({ input: process.stdin, output: process.stdout });
const ask = async (q, def = '') => (await rl.question(def ? `${q} [${def}]: ` : `${q}: `)).trim() || def;

// stdio：capture=管道捕获输出；有 input=只管道 stdin（让用户看到 wrangler 输出）；否则全继承
function run(cmd, { capture = false, input } = {}) {
  const stdio = capture ? 'pipe' : input !== undefined ? ['pipe', 'inherit', 'inherit'] : 'inherit';
  return execSync(cmd, { cwd: workerDir, stdio, encoding: 'utf8', input });
}
function tryRun(cmd, opts) {
  try { return { ok: true, out: run(cmd, opts) }; }
  catch (e) { return { ok: false, out: `${e.stdout || ''}${e.stderr || ''}${e.message}` }; }
}
const wr = (args, opts) => run(`npx --no-install wrangler ${args}`, opts);
const tryWr = (args, opts) => tryRun(`npx --no-install wrangler ${args}`, opts);
const stripJsonc = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

async function main() {
  console.log('\n=== child-video 后端一键部署 ===\n');

  // 1) 登录检查（不自动 login —— 那是浏览器交互，需用户手动）
  const who = tryWr('whoami', { capture: true });
  if (!who.ok || /not authenticated|run .?wrangler login/i.test(who.out)) {
    console.error('✗ 未登录 Cloudflare。请先运行：\n    npx wrangler login\n然后重跑：npm run setup');
    process.exit(1);
  }
  console.log('✓ 已登录 Cloudflare');

  // 2) 读已有 wrangler.jsonc（幂等：复用已有 d1 id / 域名）
  let existing = {};
  if (existsSync(wranglerPath)) {
    try { existing = JSON.parse(stripJsonc(readFileSync(wranglerPath, 'utf8'))); } catch { /* 解析失败则当无 */ }
  }

  // 3) R2 桶（幂等）
  console.log(`\n→ 创建 R2 桶 ${BUCKET}（已存在则跳过）`);
  const b = tryWr(`r2 bucket create ${BUCKET}`, { capture: true });
  if (!b.ok && !/already (exists|owned)/i.test(b.out)) console.log(b.out);

  // 4) D1（已配置则复用，否则创建并解析 id）
  let dbId = existing?.d1_databases?.[0]?.database_id;
  if (dbId && !/^<|REPLACE/i.test(dbId)) {
    console.log(`\n✓ 复用已有 D1：${dbId}`);
  } else {
    console.log(`\n→ 创建 D1 ${DB_NAME}`);
    let out = tryWr(`d1 create ${DB_NAME}`, { capture: true }).out;
    if (/already exists/i.test(out)) out = tryWr('d1 list --json', { capture: true }).out;
    const m = out.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
    if (!m) { console.error(`✗ 无法解析 D1 database_id，请手动创建后填入 wrangler.jsonc\n${out}`); process.exit(1); }
    dbId = m[0];
    console.log(`✓ D1 database_id = ${dbId}`);
  }

  // 5) 自定义域名（可选；否则免费 *.workers.dev）
  const useCustom = /^y/i.test(await ask('\n绑定自定义域名？(否则用免费 *.workers.dev；中国大陆建议绑定) y/N', 'N'));
  let domain = existing?.routes?.[0]?.pattern || '';
  if (useCustom) domain = await ask('自定义域名（需已托管在 Cloudflare，如 video.example.com）', domain);

  // 6) 写 wrangler.jsonc（plain JSON，避免改 JSONC 注释出错）
  const config = {
    $schema: 'node_modules/wrangler/config-schema.json',
    name: 'child-video-api',
    main: 'src/index.js',
    compatibility_date: '2026-06-01',
    ...(useCustom && domain
      ? { workers_dev: false, routes: [{ pattern: domain, custom_domain: true }] }
      : { workers_dev: true }),
    r2_buckets: [{ binding: 'BUCKET', bucket_name: BUCKET }],
    d1_databases: [{ binding: 'DB', database_name: DB_NAME, database_id: dbId }],
    observability: { enabled: true },
  };
  writeFileSync(wranglerPath, `${JSON.stringify(config, null, 2)}\n`);
  console.log('✓ 已写 wrangler.jsonc');

  // 7) 初始化 D1 表结构（schema.sql 全是 CREATE TABLE IF NOT EXISTS，幂等）
  console.log('\n→ 初始化 D1 表结构');
  wr(`d1 execute ${DB_NAME} --remote --file=./schema.sql -y`);

  // 8) 密钥（激活密钥默认随机生成；家长门 PIN 由用户输入）
  const genKey = randomBytes(24).toString('hex');
  const actKey = await ask('\n设备激活密钥 ACTIVATION_KEY（回车=用随机生成）', genKey);
  wr('secret put ACTIVATION_KEY', { input: `${actKey}\n` });
  const pin = await ask('家长门 PIN（改每日时长/允许时段用，可短数字；可留空）');
  if (pin) wr('secret put PARENT_PIN', { input: `${pin}\n` });

  // 9) 部署
  console.log('\n→ 部署 Worker');
  wr('deploy');

  console.log('\n=== 完成 🎉 ===');
  console.log(`激活密钥（妥善保存，激活设备时填）：${actKey}`);
  console.log(useCustom && domain
    ? `App 服务器地址填：https://${domain}`
    : 'App 服务器地址填上面 deploy 输出的 https://<name>.<子域>.workers.dev');
  rl.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
