const ENV_KEYS = {
  accountId: 'R2_ACCOUNT_ID',
  accessKeyId: 'R2_ACCESS_KEY_ID',
  secretAccessKey: 'R2_SECRET_ACCESS_KEY',
  bucket: 'R2_BUCKET',
};

export function loadConfig() {
  const cfg = {};
  const missing = [];
  for (const [key, env] of Object.entries(ENV_KEYS)) {
    cfg[key] = process.env[env];
    if (!cfg[key]) missing.push(env);
  }
  return { cfg, missing };
}

// 存储治理 / GC 配置（#48/#50/#51）。均带默认值，非必填；可被命令行参数覆盖。
// - capGb/lowGb：上限与低水位（GB）。over=超上限，warn=超低水位，gc 删到 ≤ lowGb。
// - cooldownDays：视频「看完」后至少冷却多少天才允许 gc 删（防刚看完手滑被删）。
// - workerUrl/parentPin：gc 调 Worker /api/admin/watch-stats 查看完状态用（受 PIN 保护）。
export function loadGcConfig(overrides = {}) {
  const num = (v, d) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : d;
  };
  const capGb = num(overrides.capGb ?? process.env.R2_CAP_GB, 500);
  let lowGb = num(overrides.lowGb ?? process.env.R2_LOW_GB, 450);
  if (lowGb >= capGb) lowGb = Math.floor(capGb * 0.9); // 低水位必须 < 上限，否则回退到 90%
  return {
    capGb,
    lowGb,
    cooldownDays: num(overrides.cooldownDays ?? process.env.GC_COOLDOWN_DAYS, 7),
    // 末尾斜杠归一，避免拼出 //api
    workerUrl: (overrides.workerUrl || process.env.CV_WORKER_URL || process.env.BASE || '').replace(/\/+$/, '') || null,
    parentPin: overrides.parentPin || process.env.PARENT_PIN || null,
  };
}
