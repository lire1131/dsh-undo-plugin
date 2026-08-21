// session-scan.mjs — 离线会话文件扫描/修复（v0.3.8, B6 的 PS 端载体）
// 与 dsh-undo-savepoint 插件的 undo_scan 工具同规则：区分
//   ok      合规多帧布局（frame 1 = header 行，frame 2..n = 事件行）
//   fixable 单帧布局违规（8/18 崩溃根因）——--fix 时备份 + 重编码 + 三重校验后替换
//   corrupt 无法解码 / 首行非法 header / 坏 JSON 行——--fix 时仅隔离复制，绝不动原件
//
// 用法: node session-scan.mjs [--fix] [<home>]
//   <home> 默认 = $env:DSH_HOME 或 ~/.dsh；会话文件在 <home>/sessions/**/session.jsonl.zstd
// 退出码: 0 = 全部 ok（或 fix 全部成功），1 = 存在 corrupt/fixable 未处理，2 = 用法错误

import { readdir, readFile, writeFile, mkdir } from 'node:fs/promises';
import { join, dirname, basename } from 'node:path';
import { homedir } from 'node:os';
// zstd Zlib API 需 Node 22.15+；Node 20 下属性为 undefined，脚本给出明确提示后退出（不崩）。
import * as zlib from 'node:zlib';

const args = process.argv.slice(2);
const fix = args.includes('--fix');
const rest = args.filter((a) => a !== '--fix');
if (rest.length > 1) {
  console.error('usage: node session-scan.mjs [--fix] [<home>]');
  process.exit(2);
}
const home = rest[0] ?? process.env.DSH_HOME ?? join(homedir(), '.dsh');

const zstdCompressSync = typeof zlib.zstdCompressSync === 'function' ? zlib.zstdCompressSync : null;
const zstdDecompressSync = typeof zlib.zstdDecompressSync === 'function' ? zlib.zstdDecompressSync : null;
if (!zstdCompressSync || !zstdDecompressSync) {
  console.error('session-scan requires Node.js >= 22.15 (node:zlib zstd API not available on this Node version).');
  process.exit(2);
}

const ZSTD_MAGIC = 4247762216;
const ZSTD_CHECKSUM = { params: { [zlib.constants?.ZSTD_c_checksumFlag]: 1 } };

function zstdScanFrames(b) {
  const frames = [];
  let off = 0;
  while (off < b.length) {
    const start = off;
    if (b.length - off < 4) { frames.push({ start, end: off, torn: true }); return frames; }
    if (b.readUInt32LE(off) !== ZSTD_MAGIC) throw new Error('bad frame magic at ' + off);
    off += 4;
    if (off === b.length) { frames.push({ start, end: off, torn: true }); return frames; }
    const d = b.readUInt8(off);
    off += 1;
    if ((d & 24) !== 0) throw new Error('reserved frame-header bit at ' + (off - 1));
    const csf = d >>> 6, ss = (d & 32) !== 0, ck = (d & 4) !== 0, df = d & 3;
    const db = df === 3 ? 4 : df;
    const csb = csf === 0 ? (ss ? 1 : 0) : 1 << csf;
    const rhb = (ss ? 0 : 1) + db + csb;
    if (b.length - off < rhb) { frames.push({ start, end: off, torn: true }); return frames; }
    off += rhb;
    for (;;) {
      if (b.length - off < 3) { frames.push({ start, end: off, torn: true }); return frames; }
      const bh = b.readUIntLE(off, 3);
      off += 3;
      const last = (bh & 1) !== 0, bt = (bh >>> 1) & 3, bs = bh >>> 3;
      if (bt === 3) throw new Error('reserved block type at ' + (off - 3));
      const pl = bt === 1 ? 1 : bs;
      if (b.length - off < pl) { frames.push({ start, end: off, torn: true }); return frames; }
      off += pl;
      if (last) break;
    }
    if (ck) {
      if (b.length - off < 4) { frames.push({ start, end: off, torn: true }); return frames; }
      off += 4;
    }
    frames.push({ start, end: off });
  }
  return frames;
}

function zstdDecodeAll(b) {
  const frames = zstdScanFrames(b);
  const parts = [];
  for (const f of frames) {
    if (f.torn) throw new Error('torn frame at byte ' + f.start);
    parts.push(zstdDecompressSync(b.subarray(f.start, f.end)));
  }
  return Buffer.concat(parts).toString('utf8');
}

function tryJsonLine(s) { try { JSON.parse(s); return true; } catch { return false; } }

function isSessionHeaderLine(v) {
  return typeof v === 'object' && v !== null && v.type === 'session' &&
    typeof v.version === 'number' && typeof v.id === 'string' &&
    typeof v.createdAt === 'number' && Number.isSafeInteger(v.createdAt) && v.createdAt >= 0 &&
    typeof v.delegationDepth === 'number' && Number.isSafeInteger(v.delegationDepth) && v.delegationDepth >= 0;
}

function analyzeSessionBytes(b) {
  try {
    const text = zstdDecodeAll(b);
    const frames = zstdScanFrames(b);
    const nl = text.indexOf('\n');
    if (nl === -1) return { status: 'corrupt', reason: 'no newline in decoded text' };
    const headerLine = text.slice(0, nl);
    let parsed = null;
    try { parsed = JSON.parse(headerLine); } catch { /* 首行非 JSON */ }
    if (!isSessionHeaderLine(parsed)) return { status: 'corrupt', reason: 'first line is not a valid session header' };
    const lines = text.split('\n');
    const events = lines.slice(1).filter((l) => l.trim().length > 0).length;
    if (frames.length >= 2) {
      let badJson = 0;
      for (const l of lines) { if (l.trim() && !tryJsonLine(l)) badJson++; }
      if (badJson > 0) return { status: 'corrupt', reason: `${badJson} bad JSON line(s)` };
      return { status: 'ok', events, frames: frames.length };
    }
    return { status: 'fixable', reason: 'single-frame layout violation', events, frames: frames.length };
  } catch (error) {
    return { status: 'corrupt', reason: String(error?.message ?? error) };
  }
}

function recodeSessionBytes(b) {
  const text = zstdDecodeAll(b);
  const nl = text.indexOf('\n');
  if (nl === -1) throw new Error('no newline in decoded text');
  const headerLine = text.slice(0, nl);
  const rest = text.slice(nl + 1);
  let parsed = null;
  try { parsed = JSON.parse(headerLine); } catch { /* 下抛 */ }
  if (!isSessionHeaderLine(parsed)) throw new Error('first line is not a valid session header');
  const frames = [zstdCompressSync(Buffer.from(headerLine + '\n', 'utf8'), ZSTD_CHECKSUM)];
  if (rest.length > 0) frames.push(zstdCompressSync(Buffer.from(rest, 'utf8'), ZSTD_CHECKSUM));
  const out = Buffer.concat(frames);
  const check = zstdDecodeAll(out);
  if (check !== text) throw new Error('round-trip text mismatch');
  for (const l of check.split('\n')) { if (l.trim() && !tryJsonLine(l)) throw new Error('bad JSON line after recode'); }
  const re = analyzeSessionBytes(out);
  if (re.status !== 'ok') throw new Error(`recode re-analysis failed: ${re.reason}`);
  return out;
}

async function walkSessionFiles(root) {
  const out = [];
  const stack = [root];
  while (stack.length > 0) {
    const dir = stack.pop();
    let entries = [];
    try { entries = await readdir(dir, { withFileTypes: true }); } catch { continue; }
    for (const e of entries) {
      const p = join(dir, e.name);
      if (e.isDirectory()) stack.push(p);
      else if (e.isFile() && e.name.toLowerCase() === 'session.jsonl.zstd') out.push(p);
    }
  }
  return out;
}

const sessionsRoot = join(home, 'sessions');
const files = await walkSessionFiles(sessionsRoot);
// 与插件 undo_scan 一致：隔离目录 = <undo 根>/corrupt-quarantine（undo 根 =
// $env:DSH_UNDO_ROOT 或 <home>/undo-snapshots；autoDir 在 <根>/auto 下）。
const undoRoot = process.env.DSH_UNDO_ROOT ?? join(home, 'undo-snapshots');
const quarantineDir = join(undoRoot, 'corrupt-quarantine');
const lines = [];
let ok = 0, fixed = 0, needsFix = 0, isolated = 0, corrupt = 0;
for (const p of files) {
  let raw;
  try { raw = await readFile(p); } catch (error) {
    lines.push(`  unreadable ${p} (${String(error?.message ?? error)})`);
    corrupt++;
    continue;
  }
  const a = analyzeSessionBytes(raw);
  if (a.status === 'ok') {
    lines.push(`  ok       ${p} (${a.events} events, ${a.frames} frames)`);
    ok++;
    continue;
  }
  if (a.status === 'fixable') {
    if (fix) {
      try {
        const fixedBytes = recodeSessionBytes(raw);
        await mkdir(quarantineDir, { recursive: true });
        const stamp = new Date().toISOString().replace(/[:.]/g, '-');
        await writeFile(join(quarantineDir, `${basename(dirname(p))}-${stamp}.jsonl.zstd`), raw);
        await writeFile(p + '.bak', raw);
        await writeFile(p, fixedBytes);
        lines.push(`  fixed    ${p} (single-frame violation, ${a.events} events -> header frame + event frame; original -> .bak)`);
        fixed++;
      } catch (error) {
        lines.push(`  failed   ${p} (${String(error?.message ?? error)})`);
        corrupt++;
      }
    } else {
      lines.push(`  fixable  ${p} (single-frame violation, ${a.events} events; rerun with --fix to repair)`);
      needsFix++;
    }
    continue;
  }
  let didIsolate = false;
  if (fix) {
    try {
      await mkdir(quarantineDir, { recursive: true });
      const stamp = new Date().toISOString().replace(/[:.]/g, '-');
      await writeFile(join(quarantineDir, `${basename(dirname(p))}-${stamp}-corrupt.jsonl.zstd`), raw);
      didIsolate = true;
      isolated++;
    } catch { /* 隔离失败不阻断扫描 */ }
  }
  lines.push(`  corrupt  ${p} (${a.reason})${didIsolate ? ' -> isolated' : ''}`);
  corrupt++;
}

console.log(`undo_scan: scanned ${files.length} session file(s) in ${sessionsRoot}${fix ? ' (--fix mode)' : ''}`);
for (const l of lines) console.log(l);
console.log(`summary: ${ok} ok, ${fixed} fixed, ${needsFix} fixable, ${isolated} isolated, ${corrupt} corrupt`);
process.exit(needsFix > 0 || corrupt > 0 ? 1 : 0);
