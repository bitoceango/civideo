#!/usr/bin/env node
import { Command } from 'commander';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { loadConfig } from './config.js';
import { buildPlan, ffprobe, extractMeta } from './probe.js';
import { runFfmpeg, makePoster } from './media.js';
import { parseEbook, cleanAndSegment } from './ebook.js';
import { createTtsEngine, ttsDoctor, DEFAULT_SPEAKER } from './tts.js';
import {
  makeClient,
  checkBucket,
  uploadFile,
  getManifest,
  putManifest,
  deletePrefix,
} from './r2.js';

const execFileP = promisify(execFile);

// 退出码：0 成功 / 1 运行失败 / 2 缺 R2 配置 / 3 缺 ffmpeg
const EXIT = { OK: 0, FAIL: 1, CONFIG: 2, DEPS: 3 };

function emit(json, obj, human) {
  if (json) console.log(JSON.stringify(obj, null, 2));
  else console.log(human);
}

function fail(code, message, json) {
  if (json) console.log(JSON.stringify({ ok: false, error: message }, null, 2));
  else console.error(`错误：${message}`);
  process.exit(code);
}

function requireConfig(json) {
  const { cfg, missing } = loadConfig();
  if (missing.length) {
    fail(EXIT.CONFIG, `缺少环境变量：${missing.join(', ')}（配置方法见 cli/README.md）`, json);
  }
  return cfg;
}

function isMissingBinary(e) {
  return e?.code === 'ENOENT';
}

function fmtDuration(sec) {
  const m = Math.floor(sec / 60);
  const s = String(sec % 60).padStart(2, '0');
  return `${m}:${s}`;
}

const program = new Command();
program
  .name('cpv')
  .description('child-podcast 视频上传 CLI：上传到 Cloudflare R2 并维护播放列表 manifest.json。为 AI 调用设计：非交互、--json 输出、明确退出码。')
  .version('0.1.0');

program
  .command('upload')
  .description('上传一个视频（自动探测编码，默认不转码）')
  .argument('<file>', '视频文件路径')
  .requiredOption('--title <title>', '标题')
  .option('--series <series>', '系列/合集名')
  .option('--category <category>', '学科/分类（如 科学/英语/数理/国学/艺术）')
  .option('--id <id>', '指定视频 ID（同 ID 重传即覆盖，幂等）')
  .option('--max-height <n>', '真转码时限制最大高度（0 关闭）', '720')
  .option('--dry-run', '只探测并输出处理计划，不处理不上传')
  .option('--local-out <dir>', '完整处理但输出到本地目录，不上传（联调用）')
  .option('--json', 'JSON 输出（供 AI/脚本解析）')
  .action(async (file, opts) => {
    const json = !!opts.json;
    const absFile = path.resolve(file);
    try {
      await fs.access(absFile);
    } catch {
      fail(EXIT.FAIL, `文件不存在：${absFile}`, json);
    }

    let plan;
    try {
      plan = await buildPlan(absFile, { maxHeight: Number(opts.maxHeight) });
    } catch (e) {
      if (isMissingBinary(e)) fail(EXIT.DEPS, '未找到 ffprobe，请先安装 ffmpeg（brew install ffmpeg）', json);
      fail(EXIT.FAIL, `探测失败：${e.message}`, json);
    }

    if (opts.dryRun) {
      emit(json, { ok: true, dryRun: true, action: plan.action, reason: plan.reason, meta: plan.meta },
        `处理计划：${plan.action}\n原因：${plan.reason}\n` +
        `元信息：${plan.meta.width}x${plan.meta.height} ${plan.meta.vcodec}/${plan.meta.acodec ?? '无音频'} ` +
        `${fmtDuration(plan.meta.durationSec)} ${(plan.meta.sizeBytes / 1048576).toFixed(1)}MB`);
      return;
    }

    // 真上传前先验配置，避免白白转码一小时才发现缺密钥
    const cfg = opts.localOut ? null : requireConfig(json);

    const id = opts.id || `v${crypto.randomBytes(5).toString('hex')}`;
    const workDir = opts.localOut
      ? path.join(path.resolve(opts.localOut), id)
      : await fs.mkdtemp(path.join(os.tmpdir(), 'cpv-'));
    await fs.mkdir(workDir, { recursive: true });

    try {
      let videoFile;
      if (plan.action === 'direct') {
        videoFile = absFile;
        if (opts.localOut) {
          videoFile = path.join(workDir, 'video.mp4');
          await fs.copyFile(absFile, videoFile);
        }
      } else {
        videoFile = path.join(workDir, 'video.mp4');
        if (!json) console.error(`${plan.action === 'remux' ? '重封装' : '转码'}中：${plan.reason}`);
        try {
          await runFfmpeg([...plan.ffmpegArgs, videoFile]);
        } catch (e) {
          if (isMissingBinary(e)) fail(EXIT.DEPS, '未找到 ffmpeg，请先安装（brew install ffmpeg）', json);
          throw e;
        }
      }

      // 处理后的文件重新探测，保证 manifest 里的尺寸/大小准确
      const meta = plan.action === 'direct' ? plan.meta : extractMeta(await ffprobe(videoFile));

      const posterFile = path.join(workDir, 'poster.jpg');
      await makePoster(videoFile, posterFile, meta.durationSec);

      const now = new Date().toISOString();
      const entry = {
        id,
        title: opts.title,
        series: opts.series ?? null,
        category: opts.category ?? null,
        durationSec: meta.durationSec,
        width: meta.width,
        height: meta.height,
        sizeBytes: meta.sizeBytes,
        video: `videos/${id}/video.mp4`,
        poster: `videos/${id}/poster.jpg`,
        createdAt: now,
        updatedAt: now,
        source: { action: plan.action, originalName: path.basename(absFile) },
      };

      if (opts.localOut) {
        await fs.writeFile(path.join(workDir, 'entry.json'), JSON.stringify(entry, null, 2));
        emit(json, { ok: true, localOut: workDir, action: plan.action, entry },
          `已输出到本地（未上传）：${workDir}\n处理方式：${plan.action}（${plan.reason}）`);
        return;
      }

      const client = makeClient(cfg);
      await uploadFile(client, cfg.bucket, entry.video, videoFile, 'video/mp4');
      await uploadFile(client, cfg.bucket, entry.poster, posterFile, 'image/jpeg');

      const manifest = await getManifest(client, cfg.bucket);
      const existing = manifest.videos.findIndex((v) => v.id === id);
      if (existing >= 0) {
        entry.createdAt = manifest.videos[existing].createdAt;
        manifest.videos[existing] = entry;
      } else {
        manifest.videos.push(entry);
      }
      await putManifest(client, cfg.bucket, manifest);

      emit(json, { ok: true, id, action: plan.action, entry, manifestVideos: manifest.videos.length },
        `上传完成：${opts.title}（id=${id}，${plan.action}）\n` +
        `播放列表现有 ${manifest.videos.length} 个视频，播放器刷新即可看到。`);
    } catch (e) {
      fail(EXIT.FAIL, e.message, json);
    } finally {
      if (!opts.localOut) await fs.rm(workDir, { recursive: true, force: true });
    }
  });

program
  .command('audiobook')
  .description('把电子书（EPUB/TXT/MD）转成听书：按章 TTS 合成 → 上传 R2 → 更新 manifest')
  .argument('<file>', '电子书文件路径（.epub/.txt/.md）')
  .option('--title <title>', '书名（缺省用电子书内标题/文件名）')
  .option('--author <author>', '作者（缺省用电子书内作者）')
  .option('--category <category>', '学科/分类')
  .option('--id <id>', '指定 ID（同 ID 重传即覆盖，幂等）')
  .option('--tts <engine>', 'TTS 引擎', 'doubao')
  .option('--speaker <speaker>', `音色（默认 ${DEFAULT_SPEAKER}）`, DEFAULT_SPEAKER)
  .option('--seg-chars <n>', '单段最大字数', '300')
  .option('--dry-run', '只解析并输出章节/字数/预计时长/成本估算，不合成不上传')
  .option('--json', 'JSON 输出')
  .action(async (file, opts) => {
    const json = !!opts.json;
    const absFile = path.resolve(file);
    try {
      await fs.access(absFile);
    } catch {
      fail(EXIT.FAIL, `文件不存在：${absFile}`, json);
    }

    let book;
    try {
      book = await parseEbook(absFile);
    } catch (e) {
      fail(EXIT.FAIL, `电子书解析失败：${e.message}`, json);
    }

    const title = opts.title || book.title;
    const author = opts.author ?? book.author ?? null;
    const segChars = Number(opts.segChars) || 300;

    // 章节清洗分段 + 统计
    const chapters = book.chapters
      .map((c, i) => {
        const segments = cleanAndSegment(c.text, segChars);
        return { idx: i + 1, title: c.title, segments, chars: segments.reduce((n, s) => n + s.length, 0) };
      })
      .filter((c) => c.chars > 0);
    if (chapters.length === 0) fail(EXIT.FAIL, '没有可合成的正文', json);

    const totalChars = chapters.reduce((n, c) => n + c.chars, 0);
    const estSec = Math.round(totalChars / 4); // 中文约 4 字/秒

    if (opts.dryRun) {
      emit(
        json,
        { ok: true, dryRun: true, title, author, totalChars, estDurationSec: estSec,
          chapters: chapters.map((c) => ({ idx: c.idx, title: c.title, chars: c.chars, segments: c.segments.length })) },
        `书名：${title}${author ? `（${author}）` : ''}\n` +
          `章节数：${chapters.length}　总字数：${totalChars}　预计时长：约 ${fmtDuration(estSec)}\n` +
          chapters.map((c) => `  ${c.idx}. ${c.title}  ${c.chars}字 / ${c.segments.length}段`).join('\n') +
          `\n（成本：豆包按字符计费，约 ${(totalChars / 10000).toFixed(2)} 万字，单价以火山控制台为准）`,
      );
      return;
    }

    // 真跑前先验 TTS 密钥与 R2 配置，避免白合成
    const apiKey = process.env.DOUBAO_TTS_API_KEY;
    if (opts.tts === 'doubao' && !apiKey) {
      fail(EXIT.CONFIG, '缺少环境变量 DOUBAO_TTS_API_KEY（豆包语音新版控制台 API Key）', json);
    }
    const cfg = requireConfig(json);

    let engine;
    try {
      engine = createTtsEngine(opts.tts, { apiKey, speaker: opts.speaker });
    } catch (e) {
      fail(e.isConfig ? EXIT.CONFIG : EXIT.FAIL, e.message, json);
    }

    const id = opts.id || `a${crypto.randomBytes(5).toString('hex')}`;
    const workDir = await fs.mkdtemp(path.join(os.tmpdir(), 'cpv-ab-'));
    try {
      const client = makeClient(cfg);
      const chapterEntries = [];
      for (const c of chapters) {
        if (!json) console.error(`合成第 ${c.idx}/${chapters.length} 章：${c.title}（${c.chars}字）`);
        const mp3 = await engine.synthesize(c.segments);
        const chFile = path.join(workDir, `ch-${c.idx}.mp3`);
        await fs.writeFile(chFile, mp3);
        const meta = extractMeta(await ffprobe(chFile));
        const key = `audiobooks/${id}/ch-${c.idx}.mp3`;
        await uploadFile(client, cfg.bucket, key, chFile, 'audio/mpeg');
        chapterEntries.push({ idx: c.idx, title: c.title, audio: key, durationSec: meta.durationSec });
      }

      // 封面（若 EPUB 自带）
      let cover = null;
      if (book.cover?.data?.length) {
        const ext = (book.cover.type || '').includes('png') ? 'png' : 'jpg';
        const coverFile = path.join(workDir, `cover.${ext}`);
        await fs.writeFile(coverFile, book.cover.data);
        cover = `audiobooks/${id}/cover.${ext}`;
        await uploadFile(client, cfg.bucket, cover, coverFile, book.cover.type || 'image/jpeg');
      }

      const totalDurationSec = chapterEntries.reduce((n, c) => n + c.durationSec, 0);
      const now = new Date().toISOString();
      const entry = {
        id,
        title,
        author,
        cover,
        category: opts.category ?? null,
        chapters: chapterEntries,
        totalDurationSec,
        createdAt: now,
        updatedAt: now,
        source: { format: path.extname(absFile).slice(1), originalName: path.basename(absFile), engine: opts.tts, speaker: opts.speaker },
      };

      const manifest = await getManifest(client, cfg.bucket);
      const existing = manifest.audiobooks.findIndex((a) => a.id === id);
      if (existing >= 0) {
        entry.createdAt = manifest.audiobooks[existing].createdAt;
        manifest.audiobooks[existing] = entry;
      } else {
        manifest.audiobooks.push(entry);
      }
      await putManifest(client, cfg.bucket, manifest);

      emit(
        json,
        { ok: true, id, entry, manifestAudiobooks: manifest.audiobooks.length },
        `听书已生成：${title}（id=${id}，${chapterEntries.length} 章，总时长 ${fmtDuration(totalDurationSec)}）\n` +
          `播放列表现有 ${manifest.audiobooks.length} 本听书，播放器刷新即可看到。`,
      );
    } catch (e) {
      fail(EXIT.FAIL, e.message, json);
    } finally {
      await fs.rm(workDir, { recursive: true, force: true });
    }
  });

program
  .command('list')
  .description('列出播放列表中的所有视频与听书')
  .option('--json', 'JSON 输出')
  .action(async (opts) => {
    const json = !!opts.json;
    const cfg = requireConfig(json);
    try {
      const manifest = await getManifest(makeClient(cfg), cfg.bucket);
      const vLines = manifest.videos.map(
        (v) => `${v.id}  📹 ${v.series ? `[${v.series}] ` : ''}${v.title}  (${fmtDuration(v.durationSec)})`,
      );
      const aLines = manifest.audiobooks.map(
        (a) => `${a.id}  🎧 ${a.title}${a.author ? `（${a.author}）` : ''}  ${a.chapters.length}章/${fmtDuration(a.totalDurationSec)}`,
      );
      const lines = [...vLines, ...aLines];
      emit(json, { ok: true, updatedAt: manifest.updatedAt, videos: manifest.videos, audiobooks: manifest.audiobooks },
        lines.length === 0 ? '播放列表为空' : lines.join('\n'));
    } catch (e) {
      fail(EXIT.FAIL, e.message, json);
    }
  });

program
  .command('remove')
  .description('删除一个视频或听书（R2 对象 + 播放列表条目）')
  .argument('<id>', '视频 ID（v 开头）或听书 ID（a 开头）')
  .option('--json', 'JSON 输出')
  .action(async (id, opts) => {
    const json = !!opts.json;
    const cfg = requireConfig(json);
    try {
      const client = makeClient(cfg);
      const manifest = await getManifest(client, cfg.bucket);
      const isVideo = manifest.videos.some((v) => v.id === id);
      const isAudiobook = manifest.audiobooks.some((a) => a.id === id);
      if (!isVideo && !isAudiobook) {
        fail(EXIT.FAIL, `播放列表中没有 id=${id} 的视频或听书`, json);
      }
      const prefix = isVideo ? `videos/${id}/` : `audiobooks/${id}/`;
      if (isVideo) manifest.videos = manifest.videos.filter((v) => v.id !== id);
      else manifest.audiobooks = manifest.audiobooks.filter((a) => a.id !== id);
      const deletedObjects = await deletePrefix(client, cfg.bucket, prefix);
      await putManifest(client, cfg.bucket, manifest);
      emit(json, { ok: true, id, type: isVideo ? 'video' : 'audiobook', deletedObjects },
        `已删除 ${isVideo ? '视频' : '听书'} ${id}（${deletedObjects} 个对象），剩 ${manifest.videos.length} 视频 / ${manifest.audiobooks.length} 听书`);
    } catch (e) {
      fail(EXIT.FAIL, e.message, json);
    }
  });

program
  .command('doctor')
  .description('检查 ffmpeg、R2 配置与连通性')
  .option('--json', 'JSON 输出')
  .action(async (opts) => {
    const json = !!opts.json;
    const status = { ffmpeg: false, ffprobe: false, configMissing: [], r2: 'skipped' };
    for (const bin of ['ffmpeg', 'ffprobe']) {
      try {
        await execFileP(bin, ['-version']);
        status[bin] = true;
      } catch { /* 保持 false */ }
    }
    const { cfg, missing } = loadConfig();
    status.configMissing = missing;
    if (missing.length === 0) {
      try {
        await checkBucket(makeClient(cfg), cfg.bucket);
        status.r2 = 'ok';
      } catch (e) {
        status.r2 = `failed: ${e.message}`;
      }
    }
    // TTS 为可选能力（仅 audiobook 需要）：有 key 才探测，不计入整体 ok
    const ttsKey = process.env.DOUBAO_TTS_API_KEY;
    if (ttsKey) {
      const r = await ttsDoctor('doubao', { apiKey: ttsKey, speaker: DEFAULT_SPEAKER });
      status.tts = r.ok ? 'ok' : `failed: ${r.error}`;
    } else {
      status.tts = 'skipped (未设 DOUBAO_TTS_API_KEY)';
    }
    const ok = status.ffmpeg && status.ffprobe && missing.length === 0 && status.r2 === 'ok';
    emit(json, { ok, ...status },
      `ffmpeg: ${status.ffmpeg ? 'ok' : '缺失'}\nffprobe: ${status.ffprobe ? 'ok' : '缺失'}\n` +
      `配置: ${missing.length ? `缺少 ${missing.join(', ')}` : 'ok'}\nR2 连通性: ${status.r2}\nTTS(豆包): ${status.tts}`);
    process.exit(ok ? EXIT.OK : EXIT.FAIL);
  });

program.parseAsync().catch((e) => {
  console.error(`错误：${e.message}`);
  process.exit(EXIT.FAIL);
});
