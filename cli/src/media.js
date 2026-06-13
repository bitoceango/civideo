import { spawn } from 'node:child_process';

export function runFfmpeg(args, { quiet = false } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      'ffmpeg',
      ['-y', '-hide_banner', '-loglevel', 'error', '-stats', ...args],
      { stdio: ['ignore', 'ignore', quiet ? 'ignore' : 'inherit'] },
    );
    child.on('error', reject);
    child.on('close', (code) =>
      code === 0 ? resolve() : reject(new Error(`ffmpeg 退出码 ${code}`)),
    );
  });
}

export async function makePoster(videoFile, outFile, durationSec) {
  const ss = Math.min(10, Math.max(0, Math.floor(durationSec / 2)));
  await runFfmpeg(
    ['-ss', String(ss), '-i', videoFile, '-frames:v', '1', '-vf', 'scale=480:-2', '-q:v', '3', outFile],
    { quiet: true },
  );
}
