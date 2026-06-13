// 电子书解析：把 EPUB / TXT / Markdown 读成有序章节（标题 + 纯文本）+ 书籍元数据。
// EPUB 用 fflate 解压，手解 OPF（spine/manifest/metadata），XHTML 去标签取纯文本。
import fs from 'node:fs/promises';
import path from 'node:path';
import { unzipSync, strFromU8 } from 'fflate';

const HTML_ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’', hellip: '…', mdash: '—', ndash: '–' };

function decodeEntities(s) {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&([a-zA-Z]+);/g, (m, name) => (name in HTML_ENTITIES ? HTML_ENTITIES[name] : m));
}

// XHTML/HTML → 纯文本（保留段落换行）
export function htmlToText(html) {
  let s = html
    .replace(/<\?[\s\S]*?\?>/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<(script|style|head)[\s\S]*?<\/\1>/gi, '');
  s = s.replace(/<\s*(br|\/p|\/div|\/h[1-6]|\/li|\/tr)\s*\/?>/gi, '\n');
  s = s.replace(/<[^>]+>/g, '');
  s = decodeEntities(s);
  return s.replace(/[ \t ]+/g, ' ').replace(/\n{2,}/g, '\n').split('\n').map((l) => l.trim()).filter(Boolean).join('\n');
}

function firstTagText(html, tags) {
  for (const t of tags) {
    const m = html.match(new RegExp(`<${t}[^>]*>([\\s\\S]*?)<\\/${t}>`, 'i'));
    if (m) { const txt = htmlToText(m[1]).replace(/\n/g, ' ').trim(); if (txt) return txt; }
  }
  return null;
}

function attr(tag, name) {
  const m = tag.match(new RegExp(`${name}\\s*=\\s*"([^"]*)"`, 'i')) || tag.match(new RegExp(`${name}\\s*=\\s*'([^']*)'`, 'i'));
  return m ? m[1] : null;
}

function joinHref(opfDir, href) {
  const clean = decodeURIComponent(href.split('#')[0]);
  return path.posix.normalize(path.posix.join(opfDir, clean));
}

async function parseEpub(buf) {
  const files = unzipSync(new Uint8Array(buf));
  const get = (p) => (files[p] ? strFromU8(files[p]) : null);
  const findKey = (p) => Object.keys(files).find((k) => k.toLowerCase() === p.toLowerCase());

  const container = get(findKey('META-INF/container.xml'));
  if (!container) throw new Error('不是有效的 EPUB（缺 container.xml）');
  const opfPath = attr(container.match(/<rootfile\b[^>]*>/i)?.[0] || '', 'full-path');
  if (!opfPath) throw new Error('EPUB container.xml 未指向 OPF');
  const opf = get(findKey(opfPath));
  if (!opf) throw new Error(`读不到 OPF：${opfPath}`);
  const opfDir = path.posix.dirname(opfPath);

  const title = firstTagText(opf, ['dc:title', 'title']) || 'Untitled';
  const author = firstTagText(opf, ['dc:creator', 'creator']);

  // manifest: id -> {href, type, properties}
  const manifest = {};
  for (const item of opf.match(/<item\b[^>]*>/gi) || []) {
    const id = attr(item, 'id'); if (!id) continue;
    manifest[id] = { href: attr(item, 'href'), type: attr(item, 'media-type') || '', props: attr(item, 'properties') || '' };
  }

  // 封面图：properties=cover-image，或 <meta name="cover" content="id">
  let coverId = Object.keys(manifest).find((id) => manifest[id].props.includes('cover-image'));
  if (!coverId) coverId = attr(opf.match(/<meta\b[^>]*name\s*=\s*["']cover["'][^>]*>/i)?.[0] || '', 'content');
  let cover = null;
  if (coverId && manifest[coverId]?.href) {
    const key = findKey(joinHref(opfDir, manifest[coverId].href));
    if (key && files[key]) cover = { data: Buffer.from(files[key]), type: manifest[coverId].type || 'image/jpeg' };
  }

  // spine 顺序的 XHTML 文档即章节
  const chapters = [];
  const spine = opf.match(/<spine\b[^>]*>([\s\S]*?)<\/spine>/i)?.[1] || '';
  let n = 0;
  for (const ref of spine.match(/<itemref\b[^>]*>/gi) || []) {
    const idref = attr(ref, 'idref');
    const it = idref && manifest[idref];
    if (!it || !/html|xml/.test(it.type)) continue;
    const key = findKey(joinHref(opfDir, it.href));
    const html = key ? strFromU8(files[key]) : null;
    if (!html) continue;
    const text = htmlToText(html);
    if (!text || text.length < 2) continue; // 跳过封面页/空页
    n += 1;
    const heading = firstTagText(html, ['h1', 'h2', 'h3', 'title']);
    chapters.push({ title: heading || `第 ${n} 章`, text });
  }
  if (chapters.length === 0) throw new Error('EPUB 未解析出任何正文章节');
  return { title, author, cover, chapters };
}

const CHAPTER_LINE = /^(#{1,3}\s+.+|第\s*[0-9零一二三四五六七八九十百千]+\s*[章回节卷].*|Chapter\s+\d+.*)$/i;

function parseText(raw, fallbackTitle) {
  const lines = raw.replace(/\r\n?/g, '\n').split('\n');
  const headingIdx = lines.map((l, i) => (CHAPTER_LINE.test(l.trim()) ? i : -1)).filter((i) => i >= 0);
  const chapters = [];
  if (headingIdx.length >= 2) {
    for (let k = 0; k < headingIdx.length; k++) {
      const start = headingIdx[k];
      const end = k + 1 < headingIdx.length ? headingIdx[k + 1] : lines.length;
      const title = lines[start].replace(/^#{1,3}\s+/, '').trim();
      const text = lines.slice(start + 1, end).join('\n').trim();
      if (text) chapters.push({ title, text });
    }
  }
  if (chapters.length === 0) {
    const text = lines.map((l) => l.trim()).filter(Boolean).join('\n');
    if (!text) throw new Error('文本为空');
    chapters.push({ title: fallbackTitle, text });
  }
  return { title: fallbackTitle, author: null, cover: null, chapters };
}

// 入口：按扩展名解析
export async function parseEbook(file) {
  const ext = path.extname(file).toLowerCase();
  const fallbackTitle = path.basename(file, ext);
  if (ext === '.epub') {
    return parseEpub(await fs.readFile(file));
  }
  if (ext === '.txt' || ext === '.md' || ext === '.markdown') {
    return parseText(await fs.readFile(file, 'utf8'), fallbackTitle);
  }
  throw new Error(`暂不支持的电子书格式：${ext || '(无扩展名)'}（支持 .epub / .txt / .md）`);
}

// 文本清洗 + 按句子边界切成 ≤maxLen 的小段，供 TTS 稳定合成。
export function cleanAndSegment(text, maxLen = 300) {
  const clean = text
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '') // 去控制字符（保留 \t \n）
    .replace(/[ \t ]+/g, ' ')
    .split('\n').map((l) => l.trim()).filter(Boolean).join('\n')
    .trim();
  if (!clean) return [];
  // 在句末标点/换行后切句，再合并到 ≤maxLen
  const sentences = clean.match(/[^。！？!?；;\n]*[。！？!?；;\n]?/g)?.map((s) => s.trim()).filter(Boolean) || [clean];
  const segments = [];
  let cur = '';
  for (const s of sentences) {
    if ((cur + s).length > maxLen && cur) { segments.push(cur); cur = ''; }
    if (s.length > maxLen) { // 单句超长，硬切
      if (cur) { segments.push(cur); cur = ''; }
      for (let i = 0; i < s.length; i += maxLen) segments.push(s.slice(i, i + maxLen));
    } else {
      cur += s;
    }
  }
  if (cur) segments.push(cur);
  return segments;
}
