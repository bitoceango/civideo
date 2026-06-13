// child-video API —— 儿童视频流媒体后端
// 路由：
//   POST /api/activate         家长用 PIN 激活一台设备，返回设备令牌
//   GET  /api/library          返回播放列表（读 R2 的 manifest.json）
//   GET  /media/:id/video.mp4  媒体网关，校验令牌后从 R2 流式返回（支持 Range）
//   GET  /media/:id/poster.jpg 封面图
//   GET  /api/progress         返回本设备所有播放进度 + 今日已看时长
//   POST /api/progress         上报某视频播放进度 + 累加今日时长
// 所有 /api/* 与 /media/* （除 activate）都需 Authorization: Bearer <设备令牌>

const MANIFEST_KEY = 'manifest.json';

const json = (data, status = 200, extra = {}) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...extra },
  });

async function sha256Hex(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// 从 Authorization 头取出设备，未通过返回 null
async function authDevice(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const m = auth.match(/^Bearer\s+([0-9a-f]{64})$/i);
  if (!m) return null;
  const hash = await sha256Hex(m[1]);
  return env.DB.prepare('SELECT * FROM devices WHERE token_hash = ?').bind(hash).first();
}

// 校验家长控制规则，允许播放返回 null，否则返回拦截原因
function checkRules(device, body) {
  // 允许时段
  if (device.allowed_start != null && device.allowed_end != null && typeof body?.minuteOfDay === 'number') {
    const m = body.minuteOfDay;
    const inWindow =
      device.allowed_start <= device.allowed_end
        ? m >= device.allowed_start && m < device.allowed_end
        : m >= device.allowed_start || m < device.allowed_end; // 跨午夜
    if (!inWindow) return 'outside_allowed_hours';
  }
  return null;
}

async function handleActivate(request, env) {
  if (!env.PARENT_PIN) return json({ error: 'server_not_configured' }, 500);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  if (!body?.pin || String(body.pin) !== String(env.PARENT_PIN)) {
    return json({ error: 'invalid_pin' }, 403);
  }
  const token = randomToken();
  const id = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO devices (id, token_hash, name, created_at) VALUES (?, ?, ?, ?)',
  )
    .bind(id, await sha256Hex(token), body.name || null, Date.now())
    .run();
  return json({ ok: true, deviceId: id, token });
}

async function handleLibrary(env) {
  const obj = await env.BUCKET.get(MANIFEST_KEY);
  if (!obj) return json({ version: 1, videos: [] });
  const manifest = JSON.parse(await obj.text());
  // 给客户端补上可直接请求的媒体地址（走本 Worker 鉴权网关）
  const videos = (manifest.videos || []).map((v) => ({
    ...v,
    videoUrl: `/media/${v.id}/video.mp4`,
    posterUrl: `/media/${v.id}/poster.jpg`,
  }));
  return json({ version: manifest.version || 1, updatedAt: manifest.updatedAt, videos });
}

// 媒体网关：支持 HTTP Range，便于拖动进度与边下边播
async function handleMedia(env, id, file, request) {
  const key = `videos/${id}/${file}`;
  const range = request.headers.get('Range');
  let r2Range;
  if (range) {
    const m = range.match(/bytes=(\d*)-(\d*)/);
    if (m) {
      const start = m[1] === '' ? undefined : parseInt(m[1], 10);
      const end = m[2] === '' ? undefined : parseInt(m[2], 10);
      if (start !== undefined && end !== undefined) r2Range = { offset: start, length: end - start + 1 };
      else if (start !== undefined) r2Range = { offset: start };
      else if (end !== undefined) r2Range = { suffix: end };
    }
  }

  const obj = await env.BUCKET.get(key, r2Range ? { range: r2Range } : undefined);
  if (!obj) return json({ error: 'not_found' }, 404);

  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set('etag', obj.httpEtag);
  headers.set('accept-ranges', 'bytes');
  headers.set('cache-control', 'private, max-age=3600');
  if (!headers.has('content-type')) {
    headers.set('content-type', file.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg');
  }

  if (obj.range && range) {
    const total = obj.size;
    const start = obj.range.offset || 0;
    const len = obj.range.length ?? total - start;
    const end = start + len - 1;
    headers.set('content-range', `bytes ${start}-${end}/${total}`);
    headers.set('content-length', String(len));
    return new Response(obj.body, { status: 206, headers });
  }
  headers.set('content-length', String(obj.size));
  return new Response(obj.body, { status: 200, headers });
}

async function handleGetProgress(env, device, url) {
  const { results } = await env.DB.prepare(
    'SELECT video_id, position_sec FROM watch_progress WHERE device_id = ?',
  )
    .bind(device.id)
    .all();
  const progress = {};
  for (const r of results) progress[r.video_id] = r.position_sec;

  // 当日已观看时长（客户端按本地日期传 ?day=YYYY-MM-DD）
  let watchedSec = 0;
  const day = url.searchParams.get('day');
  if (day) {
    const row = await env.DB.prepare(
      'SELECT watched_sec FROM watch_daily WHERE device_id = ? AND day = ?',
    )
      .bind(device.id, day)
      .first();
    watchedSec = row?.watched_sec || 0;
  }
  return json({ ok: true, progress, rules: ruleSummary(device), watchedSec });
}

// 家长改本设备规则（需 PIN，防孩子用设备令牌绕过限制）
async function handleSaveRules(request, env, device) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  if (!env.PARENT_PIN || String(body?.pin) !== String(env.PARENT_PIN)) {
    return json({ error: 'invalid_pin' }, 403);
  }
  const norm = (v) => (v === null || v === undefined ? null : Number(v));
  await env.DB.prepare(
    'UPDATE devices SET daily_limit_min = ?, allowed_start = ?, allowed_end = ? WHERE id = ?',
  )
    .bind(norm(body.dailyLimitMin), norm(body.allowedStart), norm(body.allowedEnd), device.id)
    .run();
  return json({ ok: true });
}

function ruleSummary(device) {
  return {
    dailyLimitMin: device.daily_limit_min,
    allowedStart: device.allowed_start,
    allowedEnd: device.allowed_end,
  };
}

async function handlePostProgress(request, env, device) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  if (!body?.videoId || typeof body.positionSec !== 'number') {
    return json({ error: 'missing_fields' }, 400);
  }

  const blocked = checkRules(device, body);

  // 断点进度 upsert
  await env.DB.prepare(
    `INSERT INTO watch_progress (device_id, video_id, position_sec, updated_at)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(device_id, video_id) DO UPDATE SET position_sec = excluded.position_sec, updated_at = excluded.updated_at`,
  )
    .bind(device.id, body.videoId, Math.floor(body.positionSec), Date.now())
    .run();

  // 今日时长累加（客户端按心跳上报 deltaSec）
  let watchedSec = 0;
  if (body.day && typeof body.deltaSec === 'number' && body.deltaSec > 0) {
    await env.DB.prepare(
      `INSERT INTO watch_daily (device_id, day, watched_sec)
       VALUES (?, ?, ?)
       ON CONFLICT(device_id, day) DO UPDATE SET watched_sec = watched_sec + excluded.watched_sec`,
    )
      .bind(device.id, body.day, Math.floor(body.deltaSec))
      .run();
    const row = await env.DB.prepare(
      'SELECT watched_sec FROM watch_daily WHERE device_id = ? AND day = ?',
    )
      .bind(device.id, body.day)
      .first();
    watchedSec = row?.watched_sec || 0;
  }

  // 是否已超每日上限
  let limitReached = false;
  if (device.daily_limit_min != null && watchedSec > 0) {
    limitReached = watchedSec >= device.daily_limit_min * 60;
  }

  return json({ ok: true, blocked: blocked || (limitReached ? 'daily_limit_reached' : null), watchedSec });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS 预检（开发期网页客户端可能需要）
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-methods': 'GET, POST, OPTIONS',
          'access-control-allow-headers': 'Authorization, Content-Type, Range',
        },
      });
    }

    try {
      if (path === '/api/activate' && request.method === 'POST') {
        return await handleActivate(request, env);
      }

      // 健康检查（无需鉴权，不泄露内容）
      if (path === '/api/health') return json({ ok: true });

      // 以下全部需要设备令牌
      const device = await authDevice(request, env);
      if (!device) return json({ error: 'unauthorized' }, 401);

      if (path === '/api/library' && request.method === 'GET') {
        return await handleLibrary(env);
      }

      const media = path.match(/^\/media\/([A-Za-z0-9_-]+)\/(video\.mp4|poster\.jpg)$/);
      if (media && request.method === 'GET') {
        return await handleMedia(env, media[1], media[2], request);
      }

      if (path === '/api/progress' && request.method === 'GET') {
        return await handleGetProgress(env, device, url);
      }
      if (path === '/api/progress' && request.method === 'POST') {
        return await handlePostProgress(request, env, device);
      }
      if (path === '/api/rules' && request.method === 'POST') {
        return await handleSaveRules(request, env, device);
      }

      return json({ error: 'not_found' }, 404);
    } catch (err) {
      return json({ error: 'internal', message: err.message }, 500);
    }
  },
};
