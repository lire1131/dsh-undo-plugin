// tools/check-size.mjs — V0.3.9 体积门禁（R4）。
// 用途：断言插件产物 < 5MB，防止引入 React/Electron/Tauri 等重依赖把包体撑爆。
// 统计范围与 npm `files` 白名单一致：lib/、tools/、cordis.patch.yml，
// 以及 npm 自动带上的 package.json / README* / CHANGELOG* / LICENSE。
// 与规划 §5.1 一致：50M 是上限，但本版按用户确认收紧为 5MB（实际产物远小于此，约束的意义是门禁机制）。
import { statSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const LIMIT = 5 * 1024 * 1024; // 5MB

// npm `files` 只发布 lib/、tools/、cordis.patch.yml；README/LICENSE 会被 npm 自动带上。
const includedTop = new Set([
  'package.json', 'README.md', 'README.en.md',
  'CHANGELOG.md', 'CHANGELOG.en.md', 'LICENSE', 'cordis.patch.yml',
]);
const includedDirs = new Set(['lib', 'tools']);
const skipDirs = new Set(['node_modules', '.git', '.github', 'docs', 'dist', 'build']);

let total = 0;
const entries = [];

function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const rel = relative(root, p).replace(/\\/g, '/');
    const st = statSync(p);
    if (st.isDirectory()) {
      if (skipDirs.has(name)) continue;
      walk(p);
    } else {
      const top = rel.split('/')[0];
      const inDir = includedDirs.has(top);
      const inTop = includedTop.has(rel);
      if (!inDir && !inTop) continue; // 不随 npm files 发布的文件不计入
      total += st.size;
      entries.push(`${rel}\t${st.size}`);
    }
  }
}

walk(root);

console.log(`check-size: ${total} bytes (limit ${LIMIT} bytes = 5MB)`);
if (total > LIMIT) {
  console.error(`FAIL: plugin tarball estimate ${total} bytes exceeds 5MB gate.`);
  // 列出最大的 10 个文件，便于定位膨胀来源
  entries.sort((a, b) => Number(b.split('\t')[1]) - Number(a.split('\t')[1]));
  for (const e of entries.slice(0, 10)) console.error('  ', e);
  process.exit(1);
}
console.log('check-size: OK (< 5MB)');
