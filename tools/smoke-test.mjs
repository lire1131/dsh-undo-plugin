// tools/smoke-test.mjs — offline smoke test of dsh-undo-savepoint logic (no DSH needed).
// Run:  node tools/smoke-test.mjs
process.env.DSH_ROOT = process.env.DSH_ROOT ?? 'C:/Users/yzf';
const { apply } = await import('../lib/index.js');
import { mkdtemp, writeFile, readFile, mkdir, rm, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const root = await mkdtemp(join(tmpdir(), 'dsh-undo-savepoint-test-'));
const home = join(root, 'home');
const profile = join(root, 'profile');
const snapDir = join(root, 'snapshots');
await mkdir(home, { recursive: true });
await mkdir(profile, { recursive: true });
await writeFile(join(home, 'settings.yaml'), 'model: v1\n');
await writeFile(join(profile, 'cordis.patch.yml'), '# patch\n[]\n');
await writeFile(join(profile, 'package.json'), '{"name":"test","v":1}\n');

const tools = new Map();
const ctx = {
  tools: { register: (t) => { tools.set(t.name, t); return () => { }; } },
  systemPrompt: { section: (s) => { return () => { }; } },
  get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); },
  logger: { info: () => { }, warn: (...a) => console.warn('[warn]', ...a) },
};
apply(ctx, { manualDir: join(snapDir, 'manual'), autoDir: join(snapDir, 'auto'), homeDir: home, profileDir: profile, watch: false, keepAuto: 2, pluginDirs: [] });
// let the async baseline snapshot land before we start asserting
await new Promise((r) => setTimeout(r, 300));

let pass = 0, fail = 0;
const check = (cond, label) => { if (cond) { pass++; console.log('  ok  -', label); } else { fail++; console.error('  FAIL -', label); } };
const run = async (name, args) => {
  const t = tools.get(name);
  if (!t) throw new Error(`tool not registered: ${name}`);
  return await t.execute(args, {});
};
const cur = async (f) => readFile(join(profile, f), 'utf8');
const set = async (f, v) => writeFile(join(profile, f), v);

console.log('== 1. snapshot & list ==');
let out = await run('undo_snapshot', { reason: 'known-good' });
console.log('   ', out.split('\n')[0]);
check((await readdir(snapDir)).sort().join(',') === 'auto,manual', 'manual/auto stores exist');
check((await readdir(join(snapDir, 'manual'))).length >= 1, 'manual store has the manual snapshot');
out = await run('undo_list', {});
check(out.includes('known-good'), 'list shows reason');
check(out.includes('plugin-mounted'), 'list shows baseline');
check(out.includes('[manual]') && out.includes('[auto]'), 'list shows store locations');

console.log('== 2. change config, snapshot again ==');
await set('cordis.patch.yml', '# patch\n- id: test\n  name: test\n');
await set('package.json', '{"name":"test","v":2}\n');
out = await run('undo_snapshot', { reason: 'after change' });

console.log('== 3. undo steps back to known-good ==');
out = await run('undo_restore', { mode: 'undo' });
console.log('   ', out.split('\n')[0]);
check((await cur('package.json')).includes('"v":1'), 'package.json back to v1');
check(!(await cur('cordis.patch.yml')).includes('- id: test'), 'patch entry removed');
check((await cur('cordis.patch.yml')).includes('- insert:'), 'undo mount is an insert patch');
check((await cur('cordis.patch.yml')).includes('name: dsh-undo-savepoint'), 'undo mount has package name');
check(out.includes('re-ensured'), 'report mentions re-ensure');

console.log('== 4. redo re-applies the change ==');
out = await run('undo_restore', { mode: 'redo' });
check((await cur('package.json')).includes('"v":2'), 'package.json back to v2');
check((await cur('cordis.patch.yml')).includes('- id: test'), 'patch entry back');

console.log('== 5. undo again after redo ==');
out = await run('undo_restore', { mode: 'undo' });
check((await cur('package.json')).includes('"v":1'), 'back to v1 again');

console.log('== 6. undo then new change blocks redo (realistic: every change snapshotted) ==');
await set('package.json', '{"name":"test","v":3}\n');
await run('undo_snapshot', { reason: 'auto-like v3' });
out = await run('undo_restore', { mode: 'undo' });
check((await cur('package.json')).includes('"v":1'), 'v3 change undone (back to v1)');
await set('package.json', '{"name":"test","v":4}\n');
await run('undo_snapshot', { reason: 'auto-like v4' });
out = await run('undo_restore', { mode: 'redo' });
console.log('   ', out.split('\n')[0]);
check(out.includes('blocked'), 'redo blocked after a newer change');

console.log('== 7. multi-step undo (three states) ==');
await set('package.json', '{"name":"test","v":4}\n'); await run('undo_snapshot', { reason: 's4' });
await set('package.json', '{"name":"test","v":5}\n'); await run('undo_snapshot', { reason: 's5' });
await set('package.json', '{"name":"test","v":6}\n'); await run('undo_snapshot', { reason: 's6' });
out = await run('undo_restore', { mode: 'undo' });
check((await cur('package.json')).includes('"v":5'), 'undo1 -> v5');
out = await run('undo_restore', { mode: 'undo' });
check((await cur('package.json')).includes('"v":4'), 'undo2 -> v4');
out = await run('undo_restore', { mode: 'redo' });
check((await cur('package.json')).includes('"v":5'), 'redo1 -> v5');
out = await run('undo_restore', { mode: 'redo' });
check((await cur('package.json')).includes('"v":6'), 'redo2 -> v6');
out = await run('undo_restore', { mode: 'undo' });
check((await cur('package.json')).includes('"v":5'), 'undo after full redo -> v5');

console.log('== 8. restore by id ==');
const list = await run('undo_list', {});
const line = list.split('\n').find((l) => /known-good\s+\(/.test(l));
const id1 = line?.match(/^(\S+)/)?.[1];
check(!!id1, 'found known-good id');
out = await run('undo_restore', { mode: 'id', snapshot_id: id1 });
check((await cur('package.json')).includes('"v":1'), 'restore by id -> v1');

console.log('== 9. manual snapshots survive (never pruned) ==');
const countSnaps = async () => (await readdir(join(snapDir, 'manual'))).length + (await readdir(join(snapDir, 'auto'))).length;
const all = await countSnaps();
console.log('   snapshot count:', all);
check(all >= 8, 'manual snapshots survive');

console.log('== 9b. manual vs auto stores are separate ==');
const manualBefore = (await readdir(join(snapDir, 'manual'))).length;
const autoBefore = (await readdir(join(snapDir, 'auto'))).length;
await run('undo_snapshot', { reason: 'store-check' });
check((await readdir(join(snapDir, 'manual'))).length === manualBefore + 1, 'manual snapshot goes to the manual store');
check((await readdir(join(snapDir, 'auto'))).length === autoBefore, 'auto store untouched by manual snapshot');

console.log('== 10. diff works ==');
out = await run('undo_diff', { snapshot_id: id1 });
check(out.includes('Diff of'), 'diff produced');

console.log('== 11. undo with all-identical snapshots says unchanged ==');
const root2 = await mkdtemp(join(tmpdir(), 'dsh-undo-savepoint-test2-'));
const home2 = join(root2, 'home');
const profile2 = join(root2, 'profile');
const snap2 = join(root2, 'snapshots');
await mkdir(home2, { recursive: true });
await mkdir(profile2, { recursive: true });
await writeFile(join(home2, 'settings.yaml'), 'model: x\n');
await writeFile(join(profile2, 'cordis.patch.yml'), '# patch\n[]\n');
const tools2 = new Map();
const ctx2 = {
  tools: { register: (t) => { tools2.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } },
  get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); },
  logger: { info: () => { }, warn: () => { } },
};
apply(ctx2, { manualDir: join(snap2, 'manual'), autoDir: join(snap2, 'auto'), homeDir: home2, profileDir: profile2, watch: false, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run2 = async (name, args) => (await tools2.get(name).execute(args, {}));
await run2('undo_snapshot', { reason: 'dup-a' });
await run2('undo_snapshot', { reason: 'dup-b' });
out = await run2('undo_restore', { mode: 'undo' });
console.log('   ', out.split('\n')[0]);
check(out.includes('nothing to undo') || out.includes('already matches'), 'identical states -> clear unchanged message');
check(!out.includes('failed'), 'unchanged is not a failure');
out = await run2('undo_restore', { mode: 'undo' });
check(out.includes('nothing to undo') || out.includes('already matches'), 'repeat undo stays unchanged');
await rm(root2, { recursive: true, force: true });

console.log('== 12. prune: pre-restore cleanup + autoCleanup off ==');
// fixture 3: keepPre=1, autoCleanup on
const root3 = await mkdtemp(join(tmpdir(), 'dsh-undo-savepoint-test3-'));
const home3 = join(root3, 'home'), profile3 = join(root3, 'profile'), snap3 = join(root3, 'snaps');
await mkdir(home3, { recursive: true }); await mkdir(profile3, { recursive: true });
await writeFile(join(home3, 'settings.yaml'), 'model: x\n');
await writeFile(join(profile3, 'cordis.patch.yml'), '# patch\n[]\n');
const tools3 = new Map();
const ctx3 = {
  tools: { register: (t) => { tools3.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx3, { manualDir: join(snap3, 'manual'), autoDir: join(snap3, 'auto'), homeDir: home3, profileDir: profile3, watch: false, keepAuto: 2, keepPre: 1, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run3 = async (name, args) => (await tools3.get(name).execute(args, {}));
const set3 = async (v) => writeFile(join(profile3, 'package.json'), v);
// two real change+undo cycles -> two pre-restore snapshots
await set3('{"name":"test","v":2}\n');
await run3('undo_snapshot', { reason: 's2' });
await run3('undo_restore', { mode: 'undo' }); // pre1 (state v2), back to x
await set3('{"name":"test","v":3}\n');
await run3('undo_snapshot', { reason: 's3' });
await run3('undo_restore', { mode: 'undo' }); // pre2 (state v3), back to x
out = await run3('undo_prune', {});
console.log('   ', out);
check(out.includes('Pruned'), 'undo_prune ran');
check(out.includes('1 pre-restore'), 'one pre-restore pruned (2 kept 1)');
out = await run3('undo_list', {});
check((out.match(/pre-restore/g) || []).length === 1, 'exactly 1 pre-restore left (keepPre=1)');
await rm(root3, { recursive: true, force: true });

// fixture 4: autoCleanup=false -> prune deletes nothing
const root4 = await mkdtemp(join(tmpdir(), 'dsh-undo-savepoint-test4-'));
const home4 = join(root4, 'home'), profile4 = join(root4, 'profile'), snap4 = join(root4, 'snaps');
await mkdir(home4, { recursive: true }); await mkdir(profile4, { recursive: true });
await writeFile(join(home4, 'settings.yaml'), 'model: x\n');
await writeFile(join(profile4, 'cordis.patch.yml'), '# patch\n[]\n');
const tools4 = new Map();
const ctx4 = {
  tools: { register: (t) => { tools4.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx4, { manualDir: join(snap4, 'manual'), autoDir: join(snap4, 'auto'), homeDir: home4, profileDir: profile4, watch: false, keepAuto: 1, keepPre: 1, autoCleanup: false, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run4 = async (name, args) => (await tools4.get(name).execute(args, {}));
const set4 = async (v) => writeFile(join(profile4, 'package.json'), v);
await set4('{"name":"test","v":2}\n');
await run4('undo_snapshot', { reason: 's2' });
await run4('undo_restore', { mode: 'undo' }); // one pre-restore
out = await run4('undo_prune', {});
check(out.includes('disabled'), 'autoCleanup off -> prune refuses');
out = await run4('undo_list', {});
check((out.match(/pre-restore/g) || []).length === 1, 'pre-restore kept when autoCleanup off');
await rm(root4, { recursive: true, force: true });

console.log('== 13. crash self-check: leftover .booting marker -> boot alert ==');
const root5 = await mkdtemp(join(tmpdir(), 'dsh-undo-test5-'));
const home5 = join(root5, 'home'), profile5 = join(root5, 'profile'), snap5 = join(root5, 'snaps');
await mkdir(home5, { recursive: true }); await mkdir(profile5, { recursive: true });
await mkdir(join(snap5, 'auto'), { recursive: true });
await writeFile(join(snap5, 'auto', '.booting'), 'stale marker from a crashed run\n'); // simulate crash
await writeFile(join(home5, 'settings.yaml'), 'model: x\n');
await writeFile(join(profile5, 'cordis.patch.yml'), '# patch\n[]\n');
const tools5 = new Map();
const ctx5 = {
  tools: { register: (t) => { tools5.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx5, { manualDir: join(snap5, 'manual'), autoDir: join(snap5, 'auto'), homeDir: home5, profileDir: profile5, watch: false, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run5 = async (name, args) => (await tools5.get(name).execute(args, {}));
out = await run5('undo_list', {});
check(out.includes('did not finish starting'), 'boot alert shown in undo_list after simulated crash');
await rm(root5, { recursive: true, force: true });

console.log('== 14. bundle-mode double-load fix: leftover manual mount is removed ==');
const root6 = await mkdtemp(join(tmpdir(), 'dsh-undo-test6-'));
const home6 = join(root6, 'home'), profile6 = join(root6, 'profile'), snap6 = join(root6, 'snaps');
await mkdir(home6, { recursive: true }); await mkdir(profile6, { recursive: true });
await writeFile(join(home6, 'settings.yaml'), 'model: x\n');
// profile declares the plugin in bundles (simulating `dsh plugin add` install)
await writeFile(join(profile6, 'package.json'), JSON.stringify({ name: 'dsh-profile-web', dsh: { profile: { bundles: ['dsh-undo-savepoint'] } } }));
// patch contains a leftover manual mount block written by an older ensureMount
await writeFile(join(profile6, 'cordis.patch.yml'), '# patch\n[]\n\n# dsh-undo-savepoint mount (re-ensured by dsh-undo-savepoint)\n- insert:\n    - id: dsh-undo-savepoint\n      name: dsh-undo-savepoint\n');
const tools6 = new Map();
const ctx6 = {
  tools: { register: (t) => { tools6.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx6, { manualDir: join(snap6, 'manual'), autoDir: join(snap6, 'auto'), homeDir: home6, profileDir: profile6, watch: false, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run6 = async (name, args) => (await tools6.get(name).execute(args, {}));
const set6 = async (v) => writeFile(join(profile6, 'package.json'), JSON.stringify({ name: 'dsh-profile-web', dsh: { profile: { bundles: ['dsh-undo-savepoint'] } }, v }));
await run6('undo_snapshot', { reason: 's1' });
await set6(2);
await run6('undo_snapshot', { reason: 's2' });
await run6('undo_restore', { mode: 'undo' }); // triggers ensureMount
const patch6 = await readFile(join(profile6, 'cordis.patch.yml'), 'utf8');
check(!patch6.includes('re-ensured'), 'leftover manual mount block removed in bundle mode');
check(!patch6.includes('- id: dsh-undo-savepoint'), 'no manual mount re-added in bundle mode');
await rm(root6, { recursive: true, force: true });

console.log('== 15. rollback log: undo_recent shows what was rolled back ==');
const root7 = await mkdtemp(join(tmpdir(), 'dsh-undo-test7-'));
const home7 = join(root7, 'home'), profile7 = join(root7, 'profile'), snap7 = join(root7, 'snaps');
await mkdir(home7, { recursive: true }); await mkdir(profile7, { recursive: true });
await writeFile(join(home7, 'settings.yaml'), 'model: x\n');
await writeFile(join(profile7, 'cordis.patch.yml'), '# patch\n[]\n');
await writeFile(join(profile7, 'package.json'), '{"v":1}\n');
const tools7 = new Map();
const ctx7 = {
  tools: { register: (t) => { tools7.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx7, { manualDir: join(snap7, 'manual'), autoDir: join(snap7, 'auto'), homeDir: home7, profileDir: profile7, watch: false, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run7 = async (name, args) => (await tools7.get(name).execute(args, {}));
const set7 = async (v) => writeFile(join(profile7, 'package.json'), v);
await run7('undo_snapshot', { reason: 's1' });
await set7('{"v":2}\n');
await run7('undo_snapshot', { reason: 's2' });
out = await run7('undo_restore', { mode: 'undo' });
const targetId = out.match(/Restored snapshot (\S+)/)?.[1];
check(!!targetId, 'undo performed');
out = await run7('undo_recent', {});
console.log('   ', out.split('\n').slice(0, 2).join(' | '));
check(out.includes(targetId), 'undo_recent shows the restored snapshot id');
check(out.includes('profile-package.json'), 'undo_recent lists the rolled-back file');
out = await run7('undo_recent', { limit: '0' });
check(out.includes(targetId), 'limit 0 is clamped to 1 (still shows the newest entry)');
await rm(root7, { recursive: true, force: true });

console.log('== 16. plugin code tree: whitelist, blob dedup, diff, restore (v0.2) ==');
const root8 = await mkdtemp(join(tmpdir(), 'dsh-undo-test8-'));
const home8 = join(root8, 'home'), profile8 = join(root8, 'profile'), snap8 = join(root8, 'snaps');
const plugin8 = join(root8, 'plugin-fake'); // 模拟 D:\dsh\plugins\dsh-xxx
await mkdir(home8, { recursive: true }); await mkdir(profile8, { recursive: true });
await mkdir(join(plugin8, 'lib'), { recursive: true });
await writeFile(join(home8, 'settings.yaml'), 'model: x\n');
// patch 引用一个 profile 本地代码文件（name: './xxx' 条目）
await writeFile(join(profile8, 'cordis.patch.yml'), '# patch\n- insert:\n    - id: rg\n      name: \'./router-global.mjs\'\n');
await writeFile(join(profile8, 'router-global.mjs'), 'export const a = 1;\n');
await writeFile(join(profile8, 'package.json'), '{"v":1}\n');
// 插件目录：代码文件 + 资源文件（白名单应排除）+ 超限代码文件（应跳过并记录）
await writeFile(join(plugin8, 'package.json'), '{"name":"dsh-fake","version":"0.1.0"}\n');
await writeFile(join(plugin8, 'lib', 'index.js'), 'export const x = 1;\n');
await writeFile(join(plugin8, 'lib', 'asset.png'), 'PNG-FAKE-DATA\n');
await writeFile(join(plugin8, 'big.js'), 'J'.repeat(300 * 1024));
const tools8 = new Map();
const ctx8 = {
  tools: { register: (t) => { tools8.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx8, { manualDir: join(snap8, 'manual'), autoDir: join(snap8, 'auto'), homeDir: home8, profileDir: profile8, watch: false, pluginDirs: [plugin8] });
await new Promise((r) => setTimeout(r, 300));
const run8 = async (name, args) => (await tools8.get(name).execute(args, {}));
const blobDir8 = join(snap8, 'blobs');
await run8('undo_snapshot', { reason: 'plugin-v1' });
let out8 = await run8('undo_list', {});
check(out8.includes('plugin file(s)'), 'list shows plugin file count');
const manualDir8 = join(snap8, 'manual');
// 按 reason 定位 v1 快照目录（同秒创建的快照排序不稳定，不能依赖目录名排序）
let v1Snap8 = null;
for (const d of await readdir(manualDir8)) {
  try {
    const mm = JSON.parse(await readFile(join(manualDir8, d, 'manifest.json'), 'utf8'));
    if (mm.reason === 'plugin-v1') { v1Snap8 = d; break; }
  } catch { /* skip */ }
}
check(!!v1Snap8, 'found plugin-v1 snapshot dir by reason');
const m8 = JSON.parse(await readFile(join(manualDir8, v1Snap8, 'manifest.json'), 'utf8'));
check(Array.isArray(m8.plugins) && m8.plugins.length === 1, 'manifest has one plugin entry');
const pf8 = m8.plugins[0].files;
check(pf8.some((f) => f.path === 'lib/index.js'), 'plugin code file referenced');
check(!pf8.some((f) => f.path === 'lib/asset.png'), 'asset file excluded by whitelist');
check(m8.plugins[0].skipped.some((s) => s.path === 'big.js' && s.reason === 'too-large'), 'oversized code file recorded as skipped');
check(m8.plugins[0].version === '0.1.0', 'plugin version recorded');
check(m8.profileFiles.some((f) => f.path === 'router-global.mjs'), 'profile-local code file referenced');
// v1: lib/index.js + plugin package.json + router-global.mjs = 3 blobs
check((await readdir(blobDir8)).length === 3, 'blobs written (3 unique contents)');
// 改插件代码 + profile 代码 + 配置 → 再快照 → blob 只新增 2 个（去重生效）
await writeFile(join(plugin8, 'lib', 'index.js'), 'export const x = 2;\n');
await writeFile(join(profile8, 'router-global.mjs'), 'export const a = 2;\n');
await writeFile(join(profile8, 'package.json'), '{"v":2}\n');
await run8('undo_snapshot', { reason: 'plugin-v2' });
check((await readdir(blobDir8)).length === 5, 'blob store dedup: only new contents added (3 -> 5)');
// diff 用 v1 快照（当前是 v2 状态，与 v2 快照无差异）
out8 = await run8('undo_diff', { snapshot_id: v1Snap8 });
console.log('   ', out8.split('\n').find((l) => l.includes('plugin')) ?? '(no plugin line)');
check(out8.includes('plugin plugin-fake/lib/index.js'), 'diff shows plugin file');
check(out8.includes('profile ./router-global.mjs'), 'diff shows profile-local code file');
out8 = await run8('undo_restore', { mode: 'undo' });
console.log('   ', out8.split('\n')[0]);
check((await readFile(join(plugin8, 'lib', 'index.js'), 'utf8')).includes('x = 1'), 'plugin code file restored');
check((await readFile(join(profile8, 'router-global.mjs'), 'utf8')).includes('a = 1'), 'profile-local code restored');
check((await readFile(join(profile8, 'package.json'), 'utf8')).includes('"v":1'), 'config restored together');
check(out8.includes('plugin:plugin-fake/lib/index.js'), 'report lists the plugin file');
check(out8.includes('restart of DSH'), 'report mentions restart requirement (v0.3)');
await rm(root8, { recursive: true, force: true });

console.log('== 17. crash attribution: stale boot-state -> last-good suggestion (v0.3) ==');
const root9 = await mkdtemp(join(tmpdir(), 'dsh-undo-test9-'));
const home9 = join(root9, 'home'), profile9 = join(root9, 'profile'), snap9 = join(root9, 'snaps');
await mkdir(home9, { recursive: true }); await mkdir(profile9, { recursive: true });
await mkdir(join(snap9, 'auto'), { recursive: true });
// 模拟上次崩溃：ok=false，lastGoodAt 设为未来时间（所有快照都早于它）
await writeFile(join(snap9, 'auto', 'boot-state.json'), JSON.stringify({ startedAt: '2026-01-01T00:00:00.000Z', pid: 1, ok: false, okAt: null, lastGoodAt: '2099-01-01T00:00:00.000Z' }));
await writeFile(join(home9, 'settings.yaml'), 'model: x\n');
await writeFile(join(profile9, 'cordis.patch.yml'), '# patch\n[]\n');
const tools9 = new Map();
const ctx9 = {
  tools: { register: (t) => { tools9.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx9, { manualDir: join(snap9, 'manual'), autoDir: join(snap9, 'auto'), homeDir: home9, profileDir: profile9, watch: false, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run9 = async (name, args) => (await tools9.get(name).execute(args, {}));
let out9 = await run9('undo_list', {});
check(out9.includes('did not finish starting'), 'crash alert shown after simulated crash');
check(out9.includes('Last known-good snapshot:'), 'alert names a concrete last-good snapshot');
check(out9.includes('undo_safe_mode'), 'alert mentions safe mode as fallback');
const bs9 = JSON.parse(await readFile(join(snap9, 'auto', 'boot-state.json'), 'utf8'));
check(bs9.ok === false && bs9.pid > 0, 'boot-state.json rewritten for this run (ok=false until 30s)');
await rm(root9, { recursive: true, force: true });

console.log('== 18. safe mode on/off roundtrip (v0.3) ==');
const root10 = await mkdtemp(join(tmpdir(), 'dsh-undo-test10-'));
const home10 = join(root10, 'home'), profile10 = join(root10, 'profile'), snap10 = join(root10, 'snaps');
await mkdir(home10, { recursive: true }); await mkdir(profile10, { recursive: true });
await writeFile(join(home10, 'settings.yaml'), 'model: x\n');
const originalPatch10 = '# patch\n- insert:\n    - id: whale\n      name: dsh-whale-kit\n';
await writeFile(join(profile10, 'cordis.patch.yml'), originalPatch10);
const tools10 = new Map();
const ctx10 = {
  tools: { register: (t) => { tools10.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx10, { manualDir: join(snap10, 'manual'), autoDir: join(snap10, 'auto'), homeDir: home10, profileDir: profile10, watch: false, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run10 = async (name, args) => (await tools10.get(name).execute(args, {}));
let out10 = await run10('undo_safe_mode', { action: 'on' });
console.log('   ', out10.split('\n')[0]);
check(out10.includes('Safe mode ON'), 'safe mode entered');
const patchOn10 = await readFile(join(profile10, 'cordis.patch.yml'), 'utf8');
check(patchOn10.includes('SAFE MODE') && !patchOn10.includes('dsh-whale-kit'), 'patch minimized (only undo remains)');
const smState10 = JSON.parse(await readFile(join(snap10, 'auto', 'safe-mode.json'), 'utf8'));
check(smState10.active === true && !!smState10.backup && !!smState10.snapshotId, 'safe-mode state file recorded');
let backupOk = false;
try { await readFile(smState10.backup, 'utf8'); backupOk = true; } catch { /* missing */ }
check(backupOk, 'patch backup file exists');
out10 = await run10('undo_safe_mode', { action: 'on' });
check(out10.includes('already ON'), 're-entering safe mode is idempotent');
out10 = await run10('undo_safe_mode', { action: 'status' });
check(out10.includes('Safe mode is ON'), 'status reports ON');
out10 = await run10('undo_safe_mode', { action: 'off' });
console.log('   ', out10.split('\n')[0]);
check(out10.includes('Safe mode OFF'), 'safe mode exited');
const patchOff10 = await readFile(join(profile10, 'cordis.patch.yml'), 'utf8');
check(patchOff10 === originalPatch10, 'patch restored to original content');
out10 = await run10('undo_safe_mode', { action: 'status' });
check(out10.includes('OFF'), 'status reports OFF after exit');
await rm(root10, { recursive: true, force: true });

console.log('== 19. cross-machine preflight: missing plugins reported (v0.4) ==');
const root11 = await mkdtemp(join(tmpdir(), 'dsh-undo-test11-'));
const home11 = join(root11, 'home'), profile11 = join(root11, 'profile'), snap11 = join(root11, 'snaps');
await mkdir(home11, { recursive: true }); await mkdir(profile11, { recursive: true });
await writeFile(join(home11, 'settings.yaml'), 'model: x\n');
// patch 引用：一个本机解析不到的插件 + 一个本地文件（不应被探测）
await writeFile(join(profile11, 'cordis.patch.yml'), '# patch\n- insert:\n    - id: ghost\n      name: dsh-ghost-plugin-xyz\n    - id: rg\n      name: \'./router-global.mjs\'\n');
await writeFile(join(profile11, 'router-global.mjs'), 'export const a = 1;\n');
// bundles 引用：一个真实存在的包（不应误报）+ 一个不存在的
await writeFile(join(profile11, 'package.json'), JSON.stringify({ name: 'test', dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', 'dsh-ghost-bundle-xyz'] } } }));
const tools11 = new Map();
const ctx11 = {
  tools: { register: (t) => { tools11.set(t.name, t); return () => { }; } },
  systemPrompt: { section: () => () => { } }, get: () => undefined,
  effect: (fn) => { const d = fn(); return d ?? (() => { }); }, logger: { info: () => { }, warn: () => { } },
};
apply(ctx11, { manualDir: join(snap11, 'manual'), autoDir: join(snap11, 'auto'), homeDir: home11, profileDir: profile11, watch: false, pluginDirs: [] });
await new Promise((r) => setTimeout(r, 300));
const run11 = async (name, args) => (await tools11.get(name).execute(args, {}));
const set11 = async (v) => writeFile(join(profile11, 'package.json'), v);
await run11('undo_snapshot', { reason: 's1' });
await set11(JSON.stringify({ name: 'test', v: 2, dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', 'dsh-ghost-bundle-xyz'] } } }));
await run11('undo_snapshot', { reason: 's2' });
out = await run11('undo_restore', { mode: 'undo' }); // 回到 s1 快照 → 预检 s1 的引用
const preflightLine = out.split('\n').find((l) => l.includes('preflight')) ?? '';
console.log('   ', preflightLine);
check(out.includes('Cross-machine preflight'), 'preflight section reported');
check(out.includes('dsh-ghost-plugin-xyz'), 'missing patch plugin named');
check(out.includes('dsh-ghost-bundle-xyz'), 'missing bundle plugin named');
check(!preflightLine.includes('router-global.mjs'), 'local file entry not probed');
check(!preflightLine.includes('@deepseek-ai/dsh-base'), 'resolvable bundle not flagged');
await rm(root11, { recursive: true, force: true });

await rm(root, { recursive: true, force: true });
console.log(`\n== RESULT: ${pass} passed, ${fail} failed ==`);
process.exit(fail > 0 ? 1 : 0);
