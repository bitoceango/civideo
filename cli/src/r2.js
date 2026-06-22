import {
  S3Client,
  GetObjectCommand,
  PutObjectCommand,
  ListObjectsV2Command,
  DeleteObjectsCommand,
  HeadBucketCommand,
} from '@aws-sdk/client-s3';
import { Upload } from '@aws-sdk/lib-storage';
import fs from 'node:fs';

export const MANIFEST_KEY = 'manifest.json';

export function makeClient(cfg) {
  return new S3Client({
    region: 'auto',
    endpoint: `https://${cfg.accountId}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId: cfg.accessKeyId, secretAccessKey: cfg.secretAccessKey },
  });
}

export async function checkBucket(client, bucket) {
  await client.send(new HeadBucketCommand({ Bucket: bucket }));
}

export async function uploadFile(client, bucket, key, filePath, contentType) {
  const upload = new Upload({
    client,
    params: {
      Bucket: bucket,
      Key: key,
      Body: fs.createReadStream(filePath),
      ContentType: contentType,
      // 内容按 id 寻址、永不原地修改，放心长缓存
      CacheControl: 'public, max-age=31536000, immutable',
    },
    partSize: 64 * 1024 * 1024,
    queueSize: 4,
  });
  upload.on('httpUploadProgress', (p) => {
    const mb = (n) => (n / 1048576).toFixed(0);
    process.stderr.write(`\r上传 ${key}: ${mb(p.loaded)}MB${p.total ? `/${mb(p.total)}MB` : ''}`);
  });
  await upload.done();
  process.stderr.write('\n');
}

export async function getManifest(client, bucket) {
  try {
    const res = await client.send(new GetObjectCommand({ Bucket: bucket, Key: MANIFEST_KEY }));
    const m = JSON.parse(await res.Body.transformToString());
    // 向后兼容旧 manifest：补齐数组字段
    if (!Array.isArray(m.videos)) m.videos = [];
    if (!Array.isArray(m.audiobooks)) m.audiobooks = [];
    return m;
  } catch (e) {
    if (e.name === 'NoSuchKey' || e.$metadata?.httpStatusCode === 404) {
      return { version: 1, updatedAt: null, videos: [], audiobooks: [] };
    }
    throw e;
  }
}

export async function putManifest(client, bucket, manifest) {
  manifest.updatedAt = new Date().toISOString();
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: MANIFEST_KEY,
      Body: JSON.stringify(manifest, null, 2),
      ContentType: 'application/json',
      CacheControl: 'no-store',
    }),
  );
}

// 分页列举某前缀（或全桶）下所有对象，累加返回 [{Key, Size, LastModified}]。
// 家庭量级（千级对象）直接全量拉，无需 R2 用量分析 API。
export async function listAllObjects(client, bucket, prefix) {
  const objects = [];
  let token;
  do {
    const listed = await client.send(
      new ListObjectsV2Command({ Bucket: bucket, Prefix: prefix, ContinuationToken: token }),
    );
    for (const o of listed.Contents || []) {
      objects.push({ key: o.Key, size: o.Size || 0, lastModified: o.LastModified || null });
    }
    token = listed.IsTruncated ? listed.NextContinuationToken : undefined;
  } while (token);
  return objects;
}

// 统计总用量并按前缀分组（videos/ / audiobooks/ / other），结合阈值给出 ok/warn/over 状态。
export async function storageStats(client, bucket, { capGb, lowGb }) {
  const objects = await listAllObjects(client, bucket);
  const groups = { videos: { bytes: 0, objects: 0 }, audiobooks: { bytes: 0, objects: 0 }, other: { bytes: 0, objects: 0 } };
  let totalBytes = 0;
  for (const o of objects) {
    totalBytes += o.size;
    const g = o.key.startsWith('videos/') ? 'videos' : o.key.startsWith('audiobooks/') ? 'audiobooks' : 'other';
    groups[g].bytes += o.size;
    groups[g].objects += 1;
  }
  const GB = 1024 ** 3;
  const totalGb = totalBytes / GB;
  const status = totalGb > capGb ? 'over' : totalGb >= lowGb ? 'warn' : 'ok';
  return { totalBytes, totalGb, objectCount: objects.length, groups, capGb, lowGb, status };
}

export async function deletePrefix(client, bucket, prefix) {
  let deleted = 0;
  let token;
  do {
    const listed = await client.send(
      new ListObjectsV2Command({ Bucket: bucket, Prefix: prefix, ContinuationToken: token }),
    );
    const keys = (listed.Contents || []).map((o) => ({ Key: o.Key }));
    if (keys.length) {
      await client.send(
        new DeleteObjectsCommand({ Bucket: bucket, Delete: { Objects: keys } }),
      );
      deleted += keys.length;
    }
    token = listed.IsTruncated ? listed.NextContinuationToken : undefined;
  } while (token);
  return deleted;
}
