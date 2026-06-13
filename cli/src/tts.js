// TTS 引擎：把文本合成为音频。引擎可插拔（目前实现豆包 seed-tts-2.0）。
// 豆包 seed-tts-2.0 走 WebSocket 双向流式二进制协议，新版控制台鉴权用单头 X-Api-Key。
import WebSocket from 'ws';
import crypto from 'node:crypto';

const DOUBAO_WS = 'wss://openspeech.bytedance.com/api/v3/tts/bidirection';
const RESOURCE_ID = 'seed-tts-2.0';
export const DEFAULT_SPEAKER = 'zh_female_vv_uranus_bigtts'; // 2.0 童声系（uranus）

// ---- 二进制协议常量 ----
const MT = { FullClient: 0b0001, AudioServer: 0b1011, FullServer: 0b1001, Error: 0b1111 };
const FLAG_EVENT = 0b0100;
const EV = {
  StartConnection: 1, FinishConnection: 2, ConnectionStarted: 50, ConnectionFailed: 51,
  StartSession: 100, FinishSession: 102, SessionStarted: 150, SessionFinished: 152, SessionFailed: 153,
  TaskRequest: 200, TTSResponse: 352, TTSEnded: 359,
};
const CONNECTION_EVENTS = new Set([1, 2, 50, 51, 52]);

function frame(msgType, event, sessionId, payload) {
  const header = Buffer.from([0x11, (msgType << 4) | FLAG_EVENT, 0x10, 0x00]); // v1 / JSON / 不压缩
  const parts = [header];
  const ev = Buffer.alloc(4); ev.writeInt32BE(event); parts.push(ev);
  if (!CONNECTION_EVENTS.has(event)) {
    const sid = Buffer.from(sessionId, 'utf8');
    const sl = Buffer.alloc(4); sl.writeUInt32BE(sid.length); parts.push(sl, sid);
  }
  const p = Buffer.from(JSON.stringify(payload), 'utf8');
  const pl = Buffer.alloc(4); pl.writeUInt32BE(p.length); parts.push(pl, p);
  return Buffer.concat(parts);
}

function parse(buf) {
  let o = 0;
  o++; const b1 = buf[o++]; o++; o++;
  const msgType = b1 >> 4, flags = b1 & 0x0f;
  const res = { msgType };
  if (flags & FLAG_EVENT) { res.event = buf.readInt32BE(o); o += 4; }
  if (res.event !== undefined && !CONNECTION_EVENTS.has(res.event)) {
    const sl = buf.readUInt32BE(o); o += 4; res.sessionId = buf.slice(o, o + sl).toString('utf8'); o += sl;
  }
  if (msgType === MT.Error) { res.errorCode = buf.readUInt32BE(o); o += 4; }
  const pl = buf.readUInt32BE(o); o += 4;
  res.payload = buf.slice(o, o + pl);
  return res;
}

class AuthError extends Error {} // 鉴权/授权类错误，重试无用

// 一个 WS 会话合成一章：把多段文本依次喂入，累加音频帧得到一个 mp3 Buffer。
function doubaoSynthesizeOnce(segments, { apiKey, speaker, timeoutMs = 60000 }) {
  return new Promise((resolve, reject) => {
    const sessionId = crypto.randomUUID();
    const audio = [];
    let settled = false;
    const finish = (err, buf) => {
      if (settled) return; settled = true;
      clearTimeout(timer); try { ws.close(); } catch { /* noop */ }
      err ? reject(err) : resolve(buf);
    };
    const ws = new WebSocket(DOUBAO_WS, {
      headers: {
        'X-Api-Key': apiKey,
        'X-Api-Resource-Id': RESOURCE_ID,
        'X-Api-Request-Id': crypto.randomUUID(),
        'X-Api-Connect-Id': crypto.randomUUID(),
      },
    });
    const timer = setTimeout(() => finish(new Error('TTS 超时')), timeoutMs);
    const audioParams = { format: 'mp3', sample_rate: 24000, speech_rate: 0 };

    ws.on('unexpected-response', (_req, res) => {
      let body = ''; res.on('data', (d) => (body += d));
      res.on('end', () => {
        const msg = `TTS 鉴权失败 HTTP ${res.statusCode}：${body.slice(0, 160)}`;
        finish(res.statusCode === 401 || res.statusCode === 403 ? new AuthError(msg) : new Error(msg));
      });
    });
    ws.on('error', (e) => finish(new Error(`TTS 连接错误：${e.message}`)));
    ws.on('open', () => ws.send(frame(MT.FullClient, EV.StartConnection, null, {})));
    ws.on('message', (data) => {
      let m; try { m = parse(Buffer.isBuffer(data) ? data : Buffer.from(data)); } catch (e) { return finish(new Error(`TTS 帧解析失败：${e.message}`)); }
      if (m.msgType === MT.AudioServer) { audio.push(m.payload); return; }
      if (m.msgType === MT.Error) {
        const msg = `TTS 服务错误 code=${m.errorCode}：${m.payload.toString('utf8').slice(0, 160)}`;
        return finish(m.errorCode >= 45000000 && m.errorCode < 45000010 ? new AuthError(msg) : new Error(msg));
      }
      switch (m.event) {
        case EV.ConnectionStarted:
          ws.send(frame(MT.FullClient, EV.StartSession, sessionId, { user: { uid: 'cpv' }, namespace: 'BidirectionalTTS', req_params: { speaker, audio_params: audioParams }, event: EV.StartSession }));
          break;
        case EV.ConnectionFailed:
          finish(new AuthError(`TTS 连接被拒：${m.payload.toString('utf8').slice(0, 160)}`)); break;
        case EV.SessionStarted:
          for (const seg of segments) {
            ws.send(frame(MT.FullClient, EV.TaskRequest, sessionId, { user: { uid: 'cpv' }, namespace: 'BidirectionalTTS', req_params: { speaker, text: seg, audio_params: audioParams }, event: EV.TaskRequest }));
          }
          ws.send(frame(MT.FullClient, EV.FinishSession, sessionId, {}));
          break;
        case EV.SessionFailed:
          finish(new Error(`TTS 会话失败：${m.payload.toString('utf8').slice(0, 160)}`)); break;
        case EV.SessionFinished: {
          const buf = Buffer.concat(audio);
          buf.length > 200 ? finish(null, buf) : finish(new Error('TTS 未返回音频'));
          break;
        }
      }
    });
  });
}

async function withRetry(fn, { retries = 2, baseDelayMs = 800 } = {}) {
  let lastErr;
  for (let attempt = 0; attempt <= retries; attempt++) {
    try { return await fn(); }
    catch (e) {
      if (e instanceof AuthError) throw e; // 鉴权错误重试无用
      lastErr = e;
      if (attempt < retries) await new Promise((r) => setTimeout(r, baseDelayMs * 2 ** attempt));
    }
  }
  throw lastErr;
}

// 创建一个 TTS 引擎实例。引擎对外只暴露 synthesize(segments) -> Promise<Buffer(mp3)>。
export function createTtsEngine(name, opts = {}) {
  if (name === 'doubao') {
    const apiKey = opts.apiKey;
    if (!apiKey) {
      const err = new Error('缺少 DOUBAO_TTS_API_KEY（豆包语音新版控制台 API Key）');
      err.isConfig = true;
      throw err;
    }
    const speaker = opts.speaker || DEFAULT_SPEAKER;
    return {
      name: 'doubao',
      speaker,
      synthesize: (segments) => withRetry(() => doubaoSynthesizeOnce(Array.isArray(segments) ? segments : [segments], { apiKey, speaker })),
    };
  }
  throw new Error(`未知 TTS 引擎：${name}（目前支持：doubao）`);
}

// 体检：用一小段文本试合成，验证密钥与连通性。
export async function ttsDoctor(name, opts = {}) {
  try {
    const engine = createTtsEngine(name, opts);
    const buf = await engine.synthesize(['你好。']);
    return { ok: true, bytes: buf.length };
  } catch (e) {
    return { ok: false, error: e.message, auth: e instanceof AuthError, config: !!e.isConfig };
  }
}
