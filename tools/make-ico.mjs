// tools/make-ico.mjs — v0.4.0 Logo 接线助手（零依赖）。
// 用途：把 image2.0 生成的透明 PNG 转成 Windows .ico（PNG-in-ICO 容器），
//       供桌面快捷方式 IconLocation 使用。Windows 对 PNG-in-ICO 的 256x256 支持最好，
//       建议用 1024x1024 透明 PNG 作为母版；本脚本若检测到 256x256 会按标准写 0。
// 用法：node tools/make-ico.mjs <input.png> <output.ico>
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export async function pngToIco(pngPath, icoPath) {
  const png = await readFile(pngPath);
  if (!Buffer.compare(png.subarray(0, 8), PNG_SIG) === 0) throw new Error('not a PNG: ' + pngPath);
  if (png.length < 26) throw new Error('PNG too small: ' + pngPath);
  // IHDR：宽高为大端 uint32，位于偏移 16 / 20。
  const w = png.readUInt32BE(16);
  const h = png.readUInt32BE(20);
  const bw = w >= 256 ? 0 : w;
  const bh = h >= 256 ? 0 : h;
  const count = 1;
  const dir = Buffer.alloc(6);
  dir.writeUInt16LE(0, 0);   // reserved
  dir.writeUInt16LE(1, 2);   // type = icon
  dir.writeUInt16LE(count, 4);
  const entry = Buffer.alloc(16);
  entry.writeUInt8(bw, 0);
  entry.writeUInt8(bh, 1);
  entry.writeUInt8(0, 2);    // colors
  entry.writeUInt8(0, 3);    // reserved
  entry.writeUInt16LE(1, 4); // planes
  entry.writeUInt16LE(32, 6);// bit count
  entry.writeUInt32LE(png.length, 8);
  entry.writeUInt32LE(dir.length + entry.length, 12); // 22
  const out = Buffer.concat([dir, entry, png]);
  await writeFile(icoPath, out);
  return icoPath;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const [inp = '', outp = ''] = process.argv.slice(2);
  if (!inp || !outp) {
    console.error('usage: node tools/make-ico.mjs <input.png> <output.ico>');
    process.exit(2);
  }
  try {
    const res = await pngToIco(inp, outp);
    console.log('make-ico: wrote', res);
  } catch (e) {
    console.error('make-ico failed:', String(e?.message ?? e));
    process.exit(1);
  }
}
