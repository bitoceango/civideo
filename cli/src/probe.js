import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs/promises';

const execFileP = promisify(execFile);

export async function ffprobe(file) {
  const { stdout } = await execFileP(
    'ffprobe',
    ['-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', file],
    { maxBuffer: 16 * 1024 * 1024 },
  );
  return JSON.parse(stdout);
}

export function extractMeta(info) {
  const v = info.streams.find((s) => s.codec_type === 'video');
  const a = info.streams.find((s) => s.codec_type === 'audio');
  return {
    durationSec: Math.round(parseFloat(info.format.duration || '0')),
    width: v?.width ?? null,
    height: v?.height ?? null,
    vcodec: v?.codec_name ?? null,
    acodec: a?.codec_name ?? null,
    sizeBytes: Number(info.format.size || 0),
  };
}

// MP4 顶层 atom 顺序：moov 在 mdat 之前才能边下边播（faststart）
export async function isFastStart(file) {
  const fh = await fs.open(file, 'r');
  try {
    const { size } = await fh.stat();
    let pos = 0;
    while (pos + 8 <= size) {
      const head = Buffer.alloc(16);
      await fh.read(head, 0, 16, pos);
      let atomSize = head.readUInt32BE(0);
      const type = head.toString('latin1', 4, 8);
      if (type === 'moov') return true;
      if (type === 'mdat') return false;
      if (atomSize === 1) atomSize = Number(head.readBigUInt64BE(8));
      else if (atomSize === 0) break;
      if (atomSize < 8) break;
      pos += atomSize;
    }
    return false;
  } finally {
    await fh.close();
  }
}

// 决定 direct / remux / transcode 三条路之一
export async function buildPlan(file, { maxHeight = 720 } = {}) {
  const info = await ffprobe(file);
  const meta = extractMeta(info);
  if (!meta.vcodec) throw new Error('未找到视频流');

  const formatNames = (info.format.format_name || '').split(',');
  const isMp4 = formatNames.includes('mp4') || formatNames.includes('mov');
  const vOk = meta.vcodec === 'h264';
  const aOk = meta.acodec === null || meta.acodec === 'aac';
  const fast = isMp4 ? await isFastStart(file) : false;

  if (vOk && aOk && isMp4 && fast) {
    return { action: 'direct', reason: 'H.264/AAC + MP4 + faststart，原样上传', ffmpegArgs: null, meta };
  }

  const args = ['-i', file];
  let action;
  let reason;
  if (vOk && aOk) {
    action = 'remux';
    reason = isMp4
      ? 'MP4 但 moov 不在文件头，重封装加 faststart'
      : `容器为 ${formatNames[0]}，重封装为 MP4（不转码）`;
    args.push('-c:v', 'copy', '-c:a', 'copy');
  } else {
    action = 'transcode';
    reason = `需要转码：视频 ${meta.vcodec} → ${vOk ? 'copy' : 'h264'}，音频 ${meta.acodec ?? '无'} → ${aOk ? 'copy' : 'aac'}`;
    if (vOk) {
      args.push('-c:v', 'copy');
    } else {
      args.push('-c:v', 'libx264', '-preset', 'medium', '-crf', '23');
      if (maxHeight > 0 && meta.height > maxHeight) args.push('-vf', `scale=-2:${maxHeight}`);
    }
    if (aOk) args.push('-c:a', 'copy');
    else args.push('-c:a', 'aac', '-b:a', '128k');
  }
  args.push('-movflags', '+faststart');
  return { action, reason, ffmpegArgs: args, meta };
}
