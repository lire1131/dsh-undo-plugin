/**
 * dsh-undo-savepoint: undo/rollback system for DeepSeek Harness.
 *
 * - Tools: undo_snapshot / undo_list / undo_diff / undo_restore
 * - Two save modes with SEPARATE stores (paths configurable in settings):
 *   manual snapshots -> <manualDir> (default D:\dsh\undo-snapshots\manual)
 *   auto/baseline/pre-restore -> <autoDir> (default D:\dsh\undo-snapshots\auto)
 *   Legacy flat layout under <snapshotDir> is read and auto-migrated.
 * - Auto-archiving: snapshots config files whenever they change (debounced),
 *   plus a baseline on mount; all parameters live in the settings file
 *   (D:\dsh\undo\settings.json) and are editable from WebUI settings.
 * - WebUI: REST endpoints under /api/undo/* power the header buttons, the
 *   snapshot manager panel (view / delete / restore-to-version) and the
 *   settings row (client half in lib/client.js).
 * - Undo/redo stack: undo restores the newest snapshot whose state differs
 *   from the current one (identical snapshots are skipped with a clear
 *   "nothing to undo" message). Every restore first stores the current state
 *   as a pre-restore snapshot; redo re-applies the newest unconsumed one
 *   (blocked when a real newer change exists). The watcher ignores the
 *   restore's own file writes (content-hash echo detection) so redo is never
 *   blocked by itself. Restoring cordis.patch.yml re-ensures the mount line.
 *
 * The external PowerShell tooling (tools/) shares the same stores/formats and
 * works even when DSH cannot boot.
 *
 * @module dsh-undo-savepoint
 */
import { createRequire } from 'node:module';
import { promises as fs, watch as fsWatch, existsSync, readFileSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { join, dirname, basename } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash, randomBytes } from 'node:crypto';
import { homedir } from 'node:os';

/** User home directory (no hardcoded author paths — see issue #1). */
const HOME = process.env.USERPROFILE ?? process.env.HOME ?? homedir();

/**
 * Resolve @deepseek-ai/dsh-tools without hardcoding any machine path.
 * 1) Anchor at THIS plugin's own location first: standard installs
 *    (`dsh plugin add`) place the plugin inside the profile dependency tree,
 *    so createRequire(import.meta.url) resolves the peer dependency.
 * 2) Fall back to $DSH_ROOT (explicitly set for local/junction mounts).
 * 3) Otherwise fail with a clear message instead of a cryptic MODULE_NOT_FOUND.
 */
const DSH_ROOT = process.env.DSH_ROOT ?? '';
let defineTool;
{
  let toolsRequire = null;
  try {
    const local = createRequire(import.meta.url);
    local.resolve('@deepseek-ai/dsh-tools');
    toolsRequire = local;
  } catch { /* not resolvable from the plugin location */ }
  if (!toolsRequire && DSH_ROOT !== '') {
    try {
      toolsRequire = createRequire(join(DSH_ROOT, 'package.json'));
      toolsRequire.resolve('@deepseek-ai/dsh-tools');
    } catch { toolsRequire = null; }
  }
  if (!toolsRequire) {
    throw new Error('dsh-undo-savepoint: cannot resolve "@deepseek-ai/dsh-tools". Install the plugin via `dsh plugin add` (peer deps resolve automatically), or set DSH_ROOT to your DSH install root for local junction mounts.');
  }
  try {
    ({ defineTool } = toolsRequire('@deepseek-ai/dsh-tools'));
  } catch {
    // Older Node without require(esm): dynamic import of the resolved path.
    const mod = await import(pathToFileURL(toolsRequire.resolve('@deepseek-ai/dsh-tools')).href);
    defineTool = mod.defineTool;
  }
}

export const name = 'dsh-undo-savepoint';
// 'webServer' is injected at the LOADER level (not ctx.get) so the REST routes
// register reliably on cold boot too: the loader waits for the service before
// applying this entry. ctx.get('webServer') at apply time can be undefined
// when the webserver row is still pending (startup ordering), which silently
// skipped route registration (symptom: /api/undo/* -> 404 while tools/baseline
// worked).
export const inject = ['tools', 'systemPrompt', 'webServer'];

/** Legacy flat snapshot root (kept for migration/back-compat). */
const LEGACY_ROOT = process.env.DSH_UNDO_ROOT ?? join(HOME, '.dsh', 'undo-snapshots');
const SETTINGS_FILE = process.env.DSH_UNDO_SETTINGS ?? join(HOME, '.dsh', 'undo', 'settings.json');

const DEFAULT_SETTINGS = {
  autoEnabled: true,
  watchDebounceMs: 1500,
  keepAuto: 20,
  keepPre: 10,
  autoCleanup: true,
  manualDir: join(LEGACY_ROOT, 'manual'),
  autoDir: join(LEGACY_ROOT, 'auto'),
};

/** The config files that make up a "DSH state". Must mirror tools/dsh-undo-savepoint-lib.ps1. */
const FILE_SPECS = [
  { root: 'profile', rel: 'cordis.patch.yml' },
  { root: 'profile', rel: 'package.json' },
  { root: 'profile', rel: 'cordis.yml' },
  { root: 'profile', rel: 'pnpm-workspace.yaml' },
  { root: 'home', rel: 'settings.yaml' },
  { root: 'home', rel: '.env' },
];

const WATCHED_BASENAMES = new Set(FILE_SPECS.map((s) => basename(s.rel)));

function rootDir(cfg, root) {
  return root === 'profile'
    ? (cfg.profileDir ?? join(HOME, '.dsh', 'profiles', 'web'))
    : (cfg.homeDir ?? join(HOME, '.dsh'));
}

function filePath(cfg, spec) {
  return join(rootDir(cfg, spec.root), spec.rel);
}

function destName(spec) {
  return `${spec.root}-${spec.rel.replace(/[\\/]/g, '-')}`;
}

function findSpec(name) {
  return FILE_SPECS.find((s) => destName(s) === name) ?? null;
}

function makeId(now = new Date()) {
  const p = (n, w = 2) => String(n).padStart(w, '0');
  const ts = `${now.getFullYear()}${p(now.getMonth() + 1)}${p(now.getDate())}-${p(now.getHours())}${p(now.getMinutes())}${p(now.getSeconds())}`;
  return `${ts}-${randomBytes(2).toString('hex')}`;
}

async function pathExists(p) {
  try { await fs.access(p); return true; } catch { return false; }
}

function loadSettingsFile() {
  try {
    const j = JSON.parse(readFileSync(SETTINGS_FILE, 'utf8').replace(/^\uFEFF/, ''));
    return { ...DEFAULT_SETTINGS, ...j };
  } catch { return { ...DEFAULT_SETTINGS }; }
}

async function readManifest(dir) {
  const text = await fs.readFile(join(dir, 'manifest.json'), 'utf8');
  return JSON.parse(text.replace(/^\uFEFF/, '')); // tolerate a BOM (PS5.1 wrote it)
}

async function writeManifest(dir, snap) {
  await fs.writeFile(join(dir, 'manifest.json'), JSON.stringify(snap, null, 2), 'utf8');
}

/** All directories that may hold snapshots (manual, auto, legacy root). */
function storeDirs(cfg) {
  return [cfg.manualDir, cfg.autoDir, LEGACY_ROOT];
}

/** Create a snapshot in the store matching its kind. Manual -> manualDir, everything else -> autoDir. */
async function createSnapshot(cfg, kind, reason) {
  const base = kind === 'manual' ? cfg.manualDir : cfg.autoDir;
  await fs.mkdir(base, { recursive: true });
  let id;
  do {
    id = makeId();
  } while (await pathExists(join(base, id)));
  const dir = join(base, id);
  await fs.mkdir(dir, { recursive: true });
  const files = [];
  for (const spec of FILE_SPECS) {
    const src = filePath(cfg, spec);
    if (!(await pathExists(src))) continue;
    const dest = join(dir, destName(spec));
    await fs.copyFile(src, dest);
    files.push({ name: destName(spec), size: (await fs.stat(dest)).size });
  }
  const snap = { id, time: new Date().toISOString(), kind, reason, files };
  await writeManifest(dir, snap);
  return snap;
}

/** List snapshots newest-first across manual/auto/legacy stores. Entries carry _dir and _store. */
async function listSnapshots(cfg) {
  const out = [];
  for (const base of storeDirs(cfg)) {
    if (!(await pathExists(base))) continue;
    for (const entry of await fs.readdir(base, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const dir = join(base, entry.name);
      try {
        const snap = await readManifest(dir);
        snap._dir = dir;
        snap._store = dirLabel(cfg, base);
        out.push(snap);
      } catch { /* ignore broken */ }
    }
  }
  out.sort((a, b) => (a.time < b.time ? 1 : a.time > b.time ? -1 : 0));
  return out;
}

function dirLabel(cfg, dir) {
  if (dir === cfg.manualDir) return 'manual';
  if (dir === cfg.autoDir) return 'auto';
  return 'legacy';
}

function findSnapshot(list, id) {
  return list.find((s) => s.id === id) ?? null;
}

/** Content-hash the state a snapshot recorded: sorted [name, sha1] pairs of its files. */
async function stateOf(snap) {
  const pairs = [];
  for (const file of (snap.files ?? [])) {
    try {
      const buf = await fs.readFile(join(snap._dir, file.name));
      pairs.push([file.name, createHash('sha1').update(buf).digest('hex')]);
    } catch { /* missing file: skip */ }
  }
  return pairs.sort((a, b) => (a[0] < b[0] ? -1 : 1));
}

/** Content-hash the CURRENT config state (only files that exist). */
async function currentState(cfg) {
  const pairs = [];
  for (const spec of FILE_SPECS) {
    const p = filePath(cfg, spec);
    try {
      const buf = await fs.readFile(p);
      pairs.push([destName(spec), createHash('sha1').update(buf).digest('hex')]);
    } catch { /* absent */ }
  }
  return pairs.sort((a, b) => (a[0] < b[0] ? -1 : 1));
}

function sameState(a, b) {
  return a.length === b.length && a.every(([n, h], i) => b[i]?.[0] === n && b[i]?.[1] === h);
}

/** Restore one snapshot's files onto the live config tree (atomic per file).
 * Records the exact content it wrote into cfg.restoredHashes so the watcher
 * can recognize (and skip) the restore's own change events. */
async function applySnapshot(cfg, snap) {
  const restored = [];
  const hashes = new Map();
  for (const file of (snap.files ?? [])) {
    const spec = findSpec(file.name);
    if (!spec) continue;
    const src = join(snap._dir, file.name);
    if (!(await pathExists(src))) continue;
    const buf = await fs.readFile(src);
    const target = filePath(cfg, spec);
    await fs.mkdir(dirname(target), { recursive: true });
    const tmp = `${target}.undo-tmp`;
    await fs.writeFile(tmp, buf);
    await fs.rename(tmp, target);
    hashes.set(file.name, createHash('sha1').update(buf).digest('hex'));
    restored.push(file.name);
  }
  cfg.restoredHashes = hashes;
  return restored;
}

/** Keep the undo plugin itself mounted: append its insert row to cordis.patch.yml when missing. */
/**
 * Keep the plugin loadable after restores, WITHOUT double-loading:
 * - BUNDLE mode (installed via `dsh plugin add`): the plugin is already loaded
 *   from dsh.profile.bundles. We must NOT add a manual patch mount (that would
 *   instantiate the plugin twice -> duplicate tools/entry id). We also remove
 *   any leftover manual mount block that an older ensureMount wrote, fixing
 *   existing double-load setups (reported by the community).
 * - PATCH mode (local junction mount): ensure the manual mount line exists.
 */
async function ensureMount(cfg) {
  const patch = filePath(cfg, { root: 'profile', rel: 'cordis.patch.yml' });
  if (!(await pathExists(patch))) return false;
  let text = await fs.readFile(patch, 'utf8');

  // detect bundle mode from the profile package.json
  let bundleMode = false;
  try {
    const pkg = JSON.parse(await fs.readFile(filePath(cfg, { root: 'profile', rel: 'package.json' }), 'utf8'));
    bundleMode = Array.isArray(pkg?.dsh?.profile?.bundles) && pkg.dsh.profile.bundles.includes('dsh-undo-savepoint');
  } catch { /* profile package.json missing/unreadable: treat as patch mode */ }

  if (bundleMode) {
    // remove a leftover manual mount block (the double-load fix)
    const marker = '# dsh-undo-savepoint mount';
    const idx = text.indexOf(marker);
    if (idx >= 0) {
      const rel = text.indexOf('name: dsh-undo-savepoint', idx);
      let end = rel >= 0 ? text.indexOf('\n', rel) : text.indexOf('\n', idx);
      if (end >= 0) end += 1;
      let start = idx;
      if (text[start - 1] === '\n' && text[start - 2] === '\n') start -= 1; // drop the preceding blank line
      if (end > start) {
        await fs.writeFile(patch, text.slice(0, start) + text.slice(end), 'utf8');
        return true; // duplicate mount removed
      }
    }
    return false; // bundle mode: nothing to ensure
  }

  // patch mode: make sure the manual mount line exists
  if (text.includes('dsh-undo-savepoint')) return false;
  text = text.replace(/^\s*\[\]\s*$/m, '');
  const block = `\n# dsh-undo-savepoint mount (re-ensured by dsh-undo-savepoint)\n- insert:\n    - id: dsh-undo-savepoint\n      name: dsh-undo-savepoint\n`;
  await fs.writeFile(patch, text.replace(/\s*$/, '') + block, 'utf8');
  return true;
}

/**
 * Prune snapshots in the AUTO store:
 * - auto/baseline beyond keepAuto (oldest first);
 * - pre-restore beyond keepPre (consumed ones first, then oldest);
 * - skipped entirely when autoCleanup is off (nothing is ever deleted).
 * Manual snapshots are never touched.
 * @returns {{removedAuto:number, removedPre:number}}
 */
async function pruneAuto(cfg, list) {
  const removed = { removedAuto: 0, removedPre: 0 };
  if (cfg.autoCleanup === false) return removed;
  const inAuto = (s) => (s._store ?? dirLabel(cfg, s._dir)) === 'auto';
  const remove = async (snap) => {
    await fs.rm(snap._dir, { recursive: true, force: true });
  };
  const auto = list
    .filter((s) => (s.kind === 'auto' || s.kind === 'baseline') && inAuto(s))
    .sort((a, b) => (a.time < b.time ? -1 : 1));
  const excessAuto = auto.slice(0, Math.max(0, auto.length - cfg.keepAuto));
  for (const snap of excessAuto) { await remove(snap); removed.removedAuto++; }
  const pre = list
    .filter((s) => s.kind === 'pre-restore' && inAuto(s))
    .sort((a, b) => {
      // consumed pre-restores are pure garbage (redo chain already walked): delete first
      if (!!a.consumed !== !!b.consumed) return a.consumed ? -1 : 1;
      return a.time < b.time ? -1 : 1;
    });
  const excessPre = pre.slice(0, Math.max(0, pre.length - cfg.keepPre));
  for (const snap of excessPre) { await remove(snap); removed.removedPre++; }
  return removed;
}

async function markFlag(snap, flag, value) {
  if (!(await pathExists(join(snap._dir, 'manifest.json')))) return;
  snap[flag] = value;
  await writeManifest(snap._dir, snap);
}

/** Migrate legacy flat snapshots under LEGACY_ROOT into manual/auto stores by kind. */
async function migrateLegacy(cfg) {
  if (!(await pathExists(LEGACY_ROOT))) return 0;
  let moved = 0;
  for (const entry of await fs.readdir(LEGACY_ROOT, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const dir = join(LEGACY_ROOT, entry.name);
    const mf = join(dir, 'manifest.json');
    if (!(await pathExists(mf))) continue;
    let kind;
    try { kind = (await readManifest(dir)).kind; } catch { continue; }
    const dest = kind === 'manual' ? cfg.manualDir : cfg.autoDir;
    await fs.mkdir(dest, { recursive: true });
    await fs.rename(dir, join(dest, entry.name));
    moved++;
  }
  return moved;
}

/** Classify an auto snapshot by which config files changed (clearer list reasons). */
function classifyChange(names) {
  if (names.some((n) => n === 'package.json')) return 'plugin-change';
  if (names.some((n) => n === 'cordis.patch.yml')) return 'patch-change';
  if (names.some((n) => n === 'settings.yaml')) return 'settings-change';
  return 'config-change';
}

/**
 * Structured per-file diff (added/removed line counts + sample lines) between
 * the current config and a snapshot. Powers the WebUI diff preview and the
 * pre-restore confirmation dialog.
 */
async function diffSnapshotStructured(cfg, snap) {
  const out = [];
  for (const spec of FILE_SPECS) {
    const src = filePath(cfg, spec);
    const name = destName(spec);
    const snapPath = join(snap._dir, name);
    const snapHas = await pathExists(snapPath);
    const curHas = await pathExists(src);
    if (!snapHas && !curHas) continue;
    if (snapHas && !curHas) { out.push({ name, added: 0, removed: 0, addedLines: [], removedLines: ['(file did not exist at snapshot time)'] }); continue; }
    if (!snapHas && curHas) { out.push({ name, added: 1, removed: 0, addedLines: ['(file is absent in snapshot)'], removedLines: [] }); continue; }
    const a = (await fs.readFile(snapPath, 'utf8')).split(/\r?\n/);
    const b = (await fs.readFile(src, 'utf8')).split(/\r?\n/);
    const setA = new Set(a); const setB = new Set(b);
    const onlyA = [...setA].filter((l) => !setB.has(l));
    const onlyB = [...setB].filter((l) => !setA.has(l));
    if (onlyA.length === 0 && onlyB.length === 0) continue;
    out.push({
      name,
      added: onlyB.length,
      removed: onlyA.length,
      addedLines: onlyB.slice(0, 8),
      removedLines: onlyA.slice(0, 8),
    });
  }
  return out;
}

/** Simple line-level diff summary between current files and a snapshot. */
async function diffSnapshot(cfg, snap) {
  const lines = [];
  for (const spec of FILE_SPECS) {
    const src = filePath(cfg, spec);
    const name = destName(spec);
    const snapPath = join(snap._dir, name);
    const snapHas = await pathExists(snapPath);
    const curHas = await pathExists(src);
    if (!snapHas && !curHas) continue;
    if (snapHas && !curHas) { lines.push(`${name}: file did not exist at snapshot time`); continue; }
    if (!snapHas && curHas) { lines.push(`${name}: NEW file (absent in snapshot)`); continue; }
    const a = (await fs.readFile(snapPath, 'utf8')).split(/\r?\n/);
    const b = (await fs.readFile(src, 'utf8')).split(/\r?\n/);
    const setA = new Set(a); const setB = new Set(b);
    const onlyA = [...setA].filter((l) => !setB.has(l));
    const onlyB = [...setB].filter((l) => !setA.has(l));
    if (onlyA.length === 0 && onlyB.length === 0) continue;
    lines.push(`${name}: snapshot has ${onlyA.length} unique line(s), current has ${onlyB.length} unique line(s)`);
    for (const l of onlyA.slice(0, 6)) lines.push(`  - (in snapshot) ${l.length > 120 ? l.slice(0, 120) + '…' : l}`);
    for (const l of onlyB.slice(0, 6)) lines.push(`  + (current)    ${l.length > 120 ? l.slice(0, 120) + '…' : l}`);
  }
  return lines.length > 0 ? lines.join('\n') : '(no differences)';
}

/**
 * Undo candidates: non-pre-restore snapshots whose recorded state is not also
 * recorded by an unconsumed pre-restore (states we undid from), newest first.
 */
async function undoCandidates(cfg, list) {
  const unconsumedPre = list.filter((s) => s.kind === 'pre-restore' && !s.consumed);
  const preStates = [];
  for (const p of unconsumedPre) preStates.push(await stateOf(p));
  const candidates = [];
  for (const s of list) {
    if (s.kind === 'pre-restore') continue;
    const st = await stateOf(s);
    if (preStates.some((p) => sameState(p, st))) continue; // undid from this state
    candidates.push({ s, st });
  }
  return candidates;
}

/**
 * Undo/redo stack.
 * undo: restore the newest candidate whose state differs from the current one
 *   (identical snapshots are skipped); the current state is always preserved
 *   as a pre-restore snapshot first.
 * redo: apply the newest unconsumed pre-restore, but only when nothing newer
 *   exists except already-consumed pre-restores (i.e. no real change happened
 *   since the undo); consuming it un-steps matching regular snapshots so undo
 *   can walk back through them again.
 */
async function restore(cfg, mode, id) {
  const list = await listSnapshots(cfg);

  if (mode === 'undo') {
    const cur = await currentState(cfg);
    const candidates = await undoCandidates(cfg, list);
    if (candidates.length === 0) return { ok: false, error: 'nothing to undo' };
    const target = candidates.find((c) => !sameState(cur, c.st)) ?? null;
    if (!target) {
      return {
        ok: true,
        unchanged: true,
        targetId: candidates[0].s.id,
        message: 'Current config already matches every undoable snapshot — no real change since the last snapshot, so there is nothing to undo.',
      };
    }
    const stepped = target !== candidates[0];
    const pre = await createSnapshot(cfg, 'pre-restore', `before-restore:${target.s.id} (${target.s.kind}: ${target.s.reason ?? ''})`);
    cfg.suppressAuto++;
    try {
      const restored = await applySnapshot(cfg, target.s);
      if (stepped) await markFlag(candidates[0].s, 'stepped', true);
      const remounted = await ensureMount(cfg);
      return { ok: true, restored, targetId: target.s.id, targetKind: target.s.kind, targetReason: target.s.reason, preSnapshotId: pre.id, stepped, remounted };
    } finally {
      cfg.suppressAuto--;
    }
  }

  if (mode === 'redo') {
    const pre = list.find((s) => s.kind === 'pre-restore' && !s.consumed);
    if (!pre) return { ok: false, error: 'nothing to redo' };
    // Block only when a REAL change happened after the undo: a newer snapshot
    // that is not an already-consumed pre-restore.
    const newer = list.find((s) => s.time > pre.time && (s.kind !== 'pre-restore' || !s.consumed));
    if (newer) return { ok: false, error: 'redo blocked: newer changes exist after the undo' };
    cfg.suppressAuto++;
    try {
      const restored = await applySnapshot(cfg, pre);
      await markFlag(pre, 'consumed', true);
      // Un-step any regular snapshot whose state matches the consumed pre-restore,
      // so a later undo can walk back through it again.
      const preState = await stateOf(pre);
      for (const s of list) {
        if (s.kind === 'pre-restore' || !s.stepped) continue;
        if (sameState(preState, await stateOf(s))) await markFlag(s, 'stepped', false);
      }
      return { ok: true, restored, targetId: pre.id, preSnapshotId: pre.id, remounted: false };
    } finally {
      cfg.suppressAuto--;
    }
  }

  // mode 'id'
  const target = findSnapshot(list, id ?? '');
  if (!target) return { ok: false, error: `snapshot not found: ${id}` };
  const pre = await createSnapshot(cfg, 'pre-restore', `before-restore:${target.id} (${target.kind}: ${target.reason ?? ''})`);
  cfg.suppressAuto++;
  try {
    const restored = await applySnapshot(cfg, target);
    const remounted = await ensureMount(cfg);
    return { ok: true, restored, targetId: target.id, targetKind: target.kind, targetReason: target.reason, preSnapshotId: pre.id, stepped: false, remounted };
  } finally {
    cfg.suppressAuto--;
  }
}

/** Delete one snapshot by id (from whichever store it lives in). */
async function removeSnapshot(cfg, id) {
  const list = await listSnapshots(cfg);
  const snap = findSnapshot(list, id ?? '');
  if (!snap) return { ok: false, error: `snapshot not found: ${id}` };
  await fs.rm(snap._dir, { recursive: true, force: true });
  return { ok: true, removed: id };
}

/** Open a native folder-picker dialog via PowerShell and resolve the chosen path. */
function pickDirectory() {
  return new Promise((resolve) => {
    const script = [
      '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8',
      'Add-Type -AssemblyName System.Windows.Forms',
      '$f = New-Object System.Windows.Forms.FolderBrowserDialog',
      "$f.Description = 'Select snapshot directory'",
      '$f.ShowNewFolderButton = $true',
      "if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $f.SelectedPath }",
    ].join('; ');
    execFile('powershell', ['-NoProfile', '-Command', script], {
      timeout: 300000, // give the user time to browse; cancel returns empty
      windowsHide: true, // no console flash
      encoding: 'utf8',
    }, (_err, stdout) => {
      const p = (stdout ?? '').trim();
      if (p) return resolve({ ok: true, path: p });
      return resolve({ ok: false, cancelled: true });
    });
  });
}

/** Open a native file-picker dialog via PowerShell (used to choose an export zip). */
function pickFile() {
  return new Promise((resolve) => {
    const script = [
      '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8',
      'Add-Type -AssemblyName System.Windows.Forms',
      '$f = New-Object System.Windows.Forms.OpenFileDialog',
      "$f.Filter = 'ZIP archives (*.zip)|*.zip|All files (*.*)|*.*'",
      '$f.Title = "Select a dsh-undo-savepoint snapshot export"',
      "if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $f.FileName }",
    ].join('; ');
    execFile('powershell', ['-NoProfile', '-Command', script], {
      timeout: 300000,
      windowsHide: true,
      encoding: 'utf8',
    }, (_err, stdout) => {
      const p = (stdout ?? '').trim();
      if (p) return resolve({ ok: true, path: p });
      return resolve({ ok: false, cancelled: true });
    });
  });
}

/** Run a short PowerShell command (zip helpers); rejects on failure. */
function runPowershell(parts) {
  return new Promise((resolve, reject) => {
    execFile('powershell', ['-NoProfile', '-NonInteractive', '-Command', parts.join(' ')], {
      windowsHide: true,
      timeout: 180000,
    }, (err) => (err ? reject(err) : resolve()));
  });
}

/** Export directory for snapshot archives (next to the snapshot root). */
const EXPORT_ROOT = process.env.DSH_UNDO_EXPORT ?? join(dirname(LEGACY_ROOT), 'undo-exports');

/** Zip the manual + auto stores into D:\dsh\undo-exports\*.zip (portable backup / transfer). */
async function exportSnapshots(cfg) {
  await fs.mkdir(EXPORT_ROOT, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const tmp = join(EXPORT_ROOT, `tmp-${ts}`);
  const zip = join(EXPORT_ROOT, `dsh-undo-export-${ts}.zip`);
  let count = 0;
  try {
    await fs.mkdir(tmp, { recursive: true });
    for (const base of [cfg.manualDir, cfg.autoDir]) {
      if (!(await pathExists(base))) continue;
      const label = base === cfg.manualDir ? 'manual' : 'auto';
      for (const entry of await fs.readdir(base, { withFileTypes: true })) {
        if (!entry.isDirectory()) continue;
        if (!(await pathExists(join(base, entry.name, 'manifest.json')))) continue;
        await fs.cp(join(base, entry.name), join(tmp, label, entry.name), { recursive: true });
        count++;
      }
    }
    await runPowershell(['Compress-Archive', '-Path', `"${tmp}\\*"`, '-DestinationPath', `"${zip}"`, '-Force']);
    return { ok: true, path: zip, count };
  } catch (error) {
    return { ok: false, error: String(error?.message ?? error) };
  } finally {
    await fs.rm(tmp, { recursive: true, force: true }).catch(() => { /* noop */ });
  }
}

/** Import snapshots from an export zip: snapshot dirs with manifests are copied
 * into the matching store by kind (manual -> manual, everything else -> auto).
 * Same-id snapshots are skipped (never overwritten). */
async function importSnapshots(cfg, zipPath) {
  if (!zipPath || !(await pathExists(zipPath))) return { ok: false, error: `file not found: ${zipPath ?? '(none)'}` };
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const tmp = join(EXPORT_ROOT, `imp-${ts}`);
  let imported = 0;
  let skipped = 0;
  try {
    await fs.mkdir(tmp, { recursive: true });
    await runPowershell(['Expand-Archive', '-Path', `"${zipPath}"`, '-DestinationPath', `"${tmp}"`, '-Force']);
    const walk = async (dir) => {
      for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
        const p = join(dir, entry.name);
        if (!entry.isDirectory()) continue;
        const mf = join(p, 'manifest.json');
        if (!(await pathExists(mf))) { await walk(p); continue; }
        let kind;
        try { kind = (await readManifest(p)).kind; } catch { kind = 'auto'; }
        const dest = kind === 'manual' ? cfg.manualDir : cfg.autoDir;
        if (await pathExists(join(dest, entry.name))) { skipped++; continue; }
        await fs.cp(p, join(dest, entry.name), { recursive: true });
        imported++;
      }
    };
    await walk(tmp);
    return { ok: true, imported, skipped, source: zipPath };
  } catch (error) {
    return { ok: false, error: String(error?.message ?? error) };
  } finally {
    await fs.rm(tmp, { recursive: true, force: true }).catch(() => { /* noop */ });
  }
}

function renderRestoreResult(r) {
  if (!r.ok) return `undo_restore failed: ${r.error}`;
  if (r.unchanged) return r.message ?? 'No undoable changes.';
  const lines = [
    `Restored snapshot ${r.targetId} (${r.targetKind}${r.targetReason ? `: ${r.targetReason}` : ''})`,
    `Files restored: ${r.restored.length > 0 ? r.restored.join(', ') : '(none)'}`,
    `Current state preserved as ${r.preSnapshotId} (redo target)`,
  ];
  if (r.stepped) lines.push('(stepped back past a post-change record)');
  if (r.remounted) lines.push('dsh-undo-savepoint mount re-ensured in cordis.patch.yml');
  return lines.join('\n');
}

function publicSettings(cfg) {
  return {
    autoEnabled: cfg.autoEnabled,
    watchDebounceMs: cfg.watchDebounceMs,
    keepAuto: cfg.keepAuto,
    keepPre: cfg.keepPre,
    autoCleanup: cfg.autoCleanup,
    manualDir: cfg.manualDir,
    autoDir: cfg.autoDir,
    snapshotDir: LEGACY_ROOT,
  };
}

const TEXT_OUTPUT = {
  schema: { type: 'string' },
  render: (_args, value) => [{ type: 'text', text: String(value) }],
};

const PROMPT_TEXT = `## Undo / rollback (dsh-undo-savepoint)
When the user asks to undo the previous action ("撤销上一步", "回退", "恢复", "redo", "保存快照", "查看快照") — typically after installing a plugin, applying a skin, or changing settings — do NOT guess or hand-edit config files:
1. Call undo_list to show available snapshots (auto-created on config changes, plus manual ones).
2. Call undo_restore with mode "undo" to revert the latest change, mode "redo" to re-apply the state saved before the last undo, or mode "id" with a snapshot id from undo_list. Use undo_diff to preview first when unsure.
3. undo_restore never destroys the current state (kept as a pre-restore snapshot) and re-ensures the dsh-undo-savepoint mount itself.
4. Manual snapshots are stored separately from auto snapshots (settings: manualDir / autoDir).
5. PROACTIVE notice: whenever the user mentions or performs a config change (installing a plugin, applying a skin, changing a setting), proactively tell them "配置已自动保存为快照,改错了随时可以撤销/回退", and offer to show the recent snapshots via undo_list. Do not wait to be asked.
6. Crash alert: if undo_list output starts with "⚠️ Previous DSH run did not finish starting", proactively suggest undoing back to the last good state (undo_restore mode "undo") and explain that the previous run crashed before this plugin finished starting.
Note: this system only reverts DSH config/plugin/skin state, not chat history.`;

/**
 * Host plugin body.
 * @param {import('@deepseek-ai/cordis').Context} ctx
 * @param {object} config
 */
export function apply(ctx, config = {}) {
  const fileSettings = loadSettingsFile();
  // Legacy option: config.snapshotDir (old flat root) derives the new stores.
  const legacyRoot = config.snapshotDir ?? undefined;
  const cfg = {
    settingsFile: SETTINGS_FILE,
    homeDir: config.homeDir ?? undefined,
    profileDir: config.profileDir ?? undefined,
    manualDir: config.manualDir ?? (legacyRoot ? join(legacyRoot, 'manual') : undefined) ?? fileSettings.manualDir,
    autoDir: config.autoDir ?? (legacyRoot ? join(legacyRoot, 'auto') : undefined) ?? fileSettings.autoDir,
    keepAuto: config.keepAuto ?? fileSettings.keepAuto,
    keepPre: config.keepPre ?? fileSettings.keepPre ?? DEFAULT_SETTINGS.keepPre,
    autoCleanup: config.autoCleanup ?? fileSettings.autoCleanup ?? DEFAULT_SETTINGS.autoCleanup,
    watchDebounceMs: config.watchDebounceMs ?? fileSettings.watchDebounceMs,
    autoEnabled: config.autoEnabled ?? fileSettings.autoEnabled,
    /** >0 while a restore is writing files: the watcher must NOT auto-snapshot
     * the restore's own writes, or the new auto snapshot would block redo. */
    suppressAuto: 0,
    /** destName -> sha1 of what the last restore wrote (echo detection). */
    restoredHashes: new Map(),
  };

  void (async () => {
    try {
      await fs.mkdir(cfg.manualDir, { recursive: true });
      await fs.mkdir(cfg.autoDir, { recursive: true });
      const moved = await migrateLegacy(cfg);
      if (moved > 0) ctx.logger.info(`[dsh-undo-savepoint] migrated ${moved} legacy snapshot(s)`);
      const snap = await createSnapshot(cfg, 'baseline', 'plugin-mounted');
      const list = await listSnapshots(cfg);
      const pruned = await pruneAuto(cfg, list);
      const prunedN = pruned.removedAuto + pruned.removedPre;
      ctx.logger.info(`[dsh-undo-savepoint] baseline snapshot ${snap.id}${prunedN > 0 ? ` (pruned ${prunedN})` : ''}`);
    } catch (error) {
      ctx.logger.warn(`[dsh-undo-savepoint] startup: ${String(error?.message ?? error)}`);
    }
  })();

  // ── crash self-check: a leftover ".booting" marker means the previous
  //    DSH run never finished starting (crashed / killed before the marker
  //    was cleared 30 s after boot). We remember that and warn in undo_list
  //    and the WebUI, so the user is offered a rollback right away.
  cfg.bootAlert = false;
  const bootingPath = join(cfg.autoDir, '.booting');
  ctx.effect(async () => {
    try {
      await fs.mkdir(cfg.autoDir, { recursive: true });
      cfg.bootAlert = await pathExists(bootingPath);
      await fs.writeFile(bootingPath, new Date().toISOString(), 'utf8');
      const timer = setTimeout(async () => {
        try { await fs.rm(bootingPath, { force: true }); } catch { /* noop */ }
      }, 30000);
      return () => {
        clearTimeout(timer);
        fs.rm(bootingPath, { force: true }).catch(() => { /* noop */ });
      };
    } catch (error) {
      ctx.logger.warn(`[dsh-undo-savepoint] boot marker failed: ${String(error?.message ?? error)}`);
      return () => { /* noop */ };
    }
  }, 'dsh-undo-savepoint.bootmarker');

  // ── tools ──────────────────────────────────────────────────────────────
  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_snapshot',
    description: 'Create a MANUAL config snapshot (stored in the manual store, never auto-pruned; e.g. "before installing X", "known-good baseline"). Snapshots are also auto-created on config changes (auto store).',
    parameters: {
      reason: { type: 'string', description: 'Why this snapshot is taken.' },
    },
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async (args) => {
      const reason = typeof args?.reason === 'string' && args.reason !== '' ? args.reason : 'manual';
      const snap = await createSnapshot(cfg, 'manual', reason);
      return `Manual snapshot ${snap.id} created (${snap.files.length} file(s), reason: ${reason}). Store: ${cfg.manualDir}`;
    },
  })), 'dsh-undo-savepoint.tool.snapshot');

  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_list',
    description: 'List all undo snapshots (newest first): id, time, kind (auto/manual/baseline/pre-restore), store (manual/auto), reason, file count, markers (stepped/consumed). Use before undo_restore to pick a target.',
    parameters: {},
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async () => {
      const list = await listSnapshots(cfg);
      if (list.length === 0) return 'No snapshots yet. They appear automatically when config files change.';
      const rows = list.map((s) => {
        const mark = [s.stepped ? 'stepped' : '', s.consumed ? 'consumed' : ''].filter(Boolean).join(',');
        const loc = s._store ?? dirLabel(cfg, s._dir);
        return `${s.id}  ${(s.time ?? '').replace('T', ' ').slice(0, 19)}  ${s.kind}${mark ? ` [${mark}]` : ''}  [${loc}]  ${(s.reason ?? '').slice(0, 50)}  (${s.files.length} file(s))`;
      });
      const alert = cfg.bootAlert
        ? '⚠️ Previous DSH run did not finish starting (crashed or was killed). You may want to undo back to the last good state: undo_restore mode "undo".\n'
        : '';
      return `${alert}Snapshots (newest first):\n${rows.join('\n')}\n\nManual store: ${cfg.manualDir}\nAuto store: ${cfg.autoDir}`;
    },
  })), 'dsh-undo-savepoint.tool.list');

  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_diff',
    description: 'Preview the difference between the current config and a snapshot, before restoring it.',
    parameters: {
      snapshot_id: { type: 'string', required: true, description: 'Snapshot id from undo_list, or "latest" for the newest one.' },
    },
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async (args) => {
      const id = typeof args?.snapshot_id === 'string' ? args.snapshot_id : '';
      const list = await listSnapshots(cfg);
      const snap = id === 'latest' ? list[0] ?? null : findSnapshot(list, id);
      if (!snap) return `Snapshot not found: ${id ?? '(empty)'}. Run undo_list first.`;
      return `Diff of ${snap.id} vs current:\n${await diffSnapshot(cfg, snap)}`;
    },
  })), 'dsh-undo-savepoint.tool.diff');

  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_restore',
    description: 'Roll back DSH config to a snapshot. mode "undo" reverts the latest change (undo last action; repeats walk further back); mode "redo" re-applies the state saved before the last undo (only when nothing changed since); mode "id" restores an explicit snapshot from undo_list (restore to a fixed version). The current state is always preserved as a pre-restore snapshot first, and the dsh-undo-savepoint mount itself is re-ensured.',
    parameters: {
      mode: { type: 'string', required: true, description: '"undo" | "redo" | "id"' },
      snapshot_id: { type: 'string', description: 'Required when mode is "id".' },
    },
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async (args) => {
      const mode = typeof args?.mode === 'string' ? args.mode : 'undo';
      const id = typeof args?.snapshot_id === 'string' ? args.snapshot_id : undefined;
      if (!['undo', 'redo', 'id'].includes(mode)) return `undo_restore: unknown mode "${mode}" (use undo | redo | id)`;
      return renderRestoreResult(await restore(cfg, mode, id));
    },
  })), 'dsh-undo-savepoint.tool.restore');

  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_prune',
    description: 'Delete expired snapshots right now: auto/baseline beyond keepAuto and pre-restore beyond keepPre (respects the autoCleanup setting; manual snapshots are never touched). Use when the user asks to clean up snapshots.',
    parameters: {},
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async () => {
      const list = await listSnapshots(cfg);
      const r = await pruneAuto(cfg, list);
      if (cfg.autoCleanup === false) return 'Auto-cleanup is disabled in settings — no snapshots were deleted.';
      return `Pruned ${r.removedAuto} auto/baseline and ${r.removedPre} pre-restore snapshot(s). Auto keeps ${cfg.keepAuto}, pre-restore keeps ${cfg.keepPre}.`;
    },
  })), 'dsh-undo-savepoint.tool.prune');

  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_export',
    description: 'Export ALL snapshots (manual + auto) into a portable ZIP archive (default: <snapshot root>/../undo-exports). Use for backup or moving to another machine. Returns the archive path.',
    parameters: {},
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async () => {
      const r = await exportSnapshots(cfg);
      if (!r.ok) return `undo_export failed: ${r.error}`;
      return `Exported ${r.count} snapshot(s) to ${r.path}`;
    },
  })), 'dsh-undo-savepoint.tool.export');

  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_import',
    description: 'Import snapshots from a dsh-undo-savepoint export ZIP. Snapshots are restored into the matching store by kind; same-id snapshots are skipped. The user can give you the zip path, or you can ask them to click Import in the snapshot panel.',
    parameters: {
      path: { type: 'string', required: true, description: 'Absolute path of the export zip file.' },
    },
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async (args) => {
      const path = typeof args?.path === 'string' ? args.path : '';
      const r = await importSnapshots(cfg, path);
      if (!r.ok) return `undo_import failed: ${r.error}`;
      return `Imported ${r.imported} snapshot(s) from ${r.source}${r.skipped > 0 ? ` (${r.skipped} skipped: already present)` : ''}.`;
    },
  })), 'dsh-undo-savepoint.tool.import');

  ctx.effect(() => ctx.systemPrompt.section({
    name: 'tool:dsh-undo-savepoint',
    order: 117,
    text: PROMPT_TEXT,
  }), 'dsh-undo-savepoint.prompt');

  // ── auto-archive watcher (debounced, rebuildable) ──────────────────────
  let watcherDispose = null;
  const startWatcher = () => {
    if (watcherDispose) { try { watcherDispose(); } catch { /* noop */ } watcherDispose = null; }
    if (!cfg.autoEnabled) return;
    let timer = null;
    const pending = new Set();
    const schedule = () => {
      if (cfg.suppressAuto > 0) return; // a restore is writing files right now
      if (timer) clearTimeout(timer);
      timer = setTimeout(async () => {
        timer = null;
        const changed = [...pending];
        pending.clear();
        if (changed.length === 0) return;
        // Skip the restore's own echo: every changed file still matches what
        // applySnapshot just wrote. A real change differs and snapshots.
        if (cfg.restoredHashes && cfg.restoredHashes.size > 0) {
          let allEcho = true;
          for (const filename of changed) {
            const spec = FILE_SPECS.find((s) => basename(s.rel) === filename);
            if (!spec) { allEcho = false; break; }
            try {
              const p = filePath(cfg, spec);
              const h = createHash('sha1').update(await fs.readFile(p)).digest('hex');
              if (h !== cfg.restoredHashes.get(destName(spec))) { allEcho = false; break; }
            } catch { allEcho = false; break; }
          }
          if (allEcho) return; // our own restore; keep the record for later echo batches
        }
        cfg.restoredHashes = new Map(); // a real change supersedes echo records
        try {
          const reason = classifyChange(changed);
          const snap = await createSnapshot(cfg, 'auto', reason);
          const list = await listSnapshots(cfg);
          const pruned = await pruneAuto(cfg, list);
          const prunedN = pruned.removedAuto + pruned.removedPre;
          if (snap.files.length > 0) ctx.logger.info(`[dsh-undo-savepoint] auto snapshot ${snap.id} (${snap.files.length} file(s), ${reason}${prunedN > 0 ? `, pruned ${prunedN}` : ''})`);
        } catch (error) {
          ctx.logger.warn(`[dsh-undo-savepoint] auto snapshot failed: ${String(error?.message ?? error)}`);
        }
      }, cfg.watchDebounceMs);
    };
    const onEvent = (_event, filename) => {
      if (typeof filename !== 'string' || !WATCHED_BASENAMES.has(basename(filename))) return;
      pending.add(filename);
      schedule();
    };
    watcherDispose = ctx.effect(() => {
      const watchers = [];
      for (const dir of [rootDir(cfg, 'profile'), rootDir(cfg, 'home')]) {
        if (!existsSync(dir)) continue;
        try {
          watchers.push(fsWatch(dir, onEvent));
        } catch (error) {
          ctx.logger.warn(`[dsh-undo-savepoint] cannot watch ${dir}: ${String(error?.message ?? error)}`);
        }
      }
      return () => {
        for (const w of watchers) { try { w.close(); } catch { /* noop */ } }
        if (timer) clearTimeout(timer);
      };
    }, 'dsh-undo-savepoint.watch');
  };
  startWatcher();

  // ── REST API for the WebUI ─────────────────────────────────────────────
  const webServer = ctx.webServer ?? ctx.get('webServer');
  if (webServer) {
    const send = (res, status, body) => {
      const text = JSON.stringify(body);
      res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
      res.end(text);
    };
    const readJson = (req) => new Promise((resolve) => {
      const chunks = [];
      let size = 0;
      req.on('data', (c) => { size += c.length; if (size > 65536) { req.destroy(); return; } chunks.push(c); });
      req.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf8').trim();
        if (raw === '') return resolve({});
        try { resolve(JSON.parse(raw)); } catch { resolve({}); }
      });
      req.on('error', () => resolve({}));
    });
    const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
    ctx.effect(() => webServer.register({
      kind: 'prefix',
      path: '/api/undo',
      handler: async (req, res) => {
        try {
          const url = new URL(req.url ?? '/', 'http://dsh.local');
          const path = url.pathname;
          const method = (req.method ?? 'GET').toUpperCase();
          if (method === 'GET' && path === '/api/undo/list') {
            const snapshots = (await listSnapshots(cfg)).map((s) => {
              const { _dir, _store, ...rest } = s;
              return { ...rest, location: _store ?? dirLabel(cfg, _dir) };
            });
            return send(res, 200, { ok: true, snapshots });
          }
          if (method === 'GET' && path === '/api/undo/status') {
            const list = await listSnapshots(cfg);
            const cur = await currentState(cfg);
            const candidates = await undoCandidates(cfg, list);
            const canUndo = candidates.some((c) => !sameState(cur, c.st));
            const pre = list.find((s) => s.kind === 'pre-restore' && !s.consumed);
            const canRedo = pre !== undefined
              && !list.some((s) => s.time > pre.time && (s.kind !== 'pre-restore' || !s.consumed));
            return send(res, 200, { ok: true, canUndo, canRedo, total: list.length, bootAlert: cfg.bootAlert === true });
          }
          if (method === 'GET' && path === '/api/undo/settings') {
            return send(res, 200, { ok: true, settings: publicSettings(cfg) });
          }
          if (method === 'GET' && path === '/api/undo/diff') {
            const id = url.searchParams.get('id') ?? '';
            const list = await listSnapshots(cfg);
            const snap = id === 'latest' ? list[0] ?? null : findSnapshot(list, id);
            if (!snap) return send(res, 404, { ok: false, error: { code: 'not-found', message: `snapshot not found: ${id}` } });
            return send(res, 200, { ok: true, id: snap.id, diff: await diffSnapshotStructured(cfg, snap) });
          }
          if (method === 'POST' && path === '/api/undo/settings') {
            const body = await readJson(req);
            if (typeof body.autoEnabled === 'boolean') cfg.autoEnabled = body.autoEnabled;
            if (typeof body.autoCleanup === 'boolean') cfg.autoCleanup = body.autoCleanup;
            if (Number.isFinite(body.watchDebounceMs)) cfg.watchDebounceMs = clamp(Math.round(body.watchDebounceMs), 200, 60000);
            if (Number.isFinite(body.keepAuto)) cfg.keepAuto = clamp(Math.round(body.keepAuto), 1, 500);
            if (Number.isFinite(body.keepPre)) cfg.keepPre = clamp(Math.round(body.keepPre), 0, 500);
            const normDir = (v) => (typeof v === 'string' ? v.trim().replace(/[\\/]+$/, '') : '');
            if (normDir(body.manualDir) !== '') cfg.manualDir = normDir(body.manualDir);
            if (normDir(body.autoDir) !== '') cfg.autoDir = normDir(body.autoDir);
            await fs.mkdir(dirname(cfg.settingsFile), { recursive: true });
            await fs.writeFile(cfg.settingsFile, JSON.stringify(publicSettings(cfg), null, 2), 'utf8');
            await fs.mkdir(cfg.manualDir, { recursive: true });
            await fs.mkdir(cfg.autoDir, { recursive: true });
            startWatcher();
            // apply the new retention limits immediately
            const pruned = await pruneAuto(cfg, await listSnapshots(cfg));
            return send(res, 200, { ok: true, settings: publicSettings(cfg), pruned });
          }
          if (method === 'POST' && path === '/api/undo/prune') {
            const r = await pruneAuto(cfg, await listSnapshots(cfg));
            return send(res, 200, { ok: true, ...r });
          }
          if (method === 'POST' && path === '/api/undo/undo') {
            return send(res, 200, { ok: true, ...await restore(cfg, 'undo') });
          }
          if (method === 'POST' && path === '/api/undo/redo') {
            return send(res, 200, { ok: true, ...await restore(cfg, 'redo') });
          }
          if (method === 'POST' && path === '/api/undo/restore') {
            const body = await readJson(req);
            return send(res, 200, { ok: true, ...await restore(cfg, 'id', body?.id) });
          }
          if (method === 'POST' && path === '/api/undo/remove') {
            const body = await readJson(req);
            return send(res, 200, { ok: true, ...await removeSnapshot(cfg, body?.id) });
          }
          if (method === 'POST' && path === '/api/undo/snapshot') {
            const body = await readJson(req);
            return send(res, 200, { ok: true, snapshot: await createSnapshot(cfg, 'manual', body?.reason ?? 'manual:api') });
          }
          if (method === 'POST' && path === '/api/undo/pick-dir') {
            return send(res, 200, { ok: true, ...await pickDirectory() });
          }
          if (method === 'POST' && path === '/api/undo/export') {
            return send(res, 200, { ok: true, ...await exportSnapshots(cfg) });
          }
          if (method === 'POST' && path === '/api/undo/pick-file') {
            return send(res, 200, { ok: true, ...await pickFile() });
          }
          if (method === 'POST' && path === '/api/undo/import') {
            const body = await readJson(req);
            return send(res, 200, { ok: true, ...await importSnapshots(cfg, body?.path) });
          }
          return send(res, 404, { ok: false, error: { code: 'not-found', message: `unknown route ${path}` } });
        } catch (error) {
          return send(res, 500, { ok: false, error: { code: 'internal', message: String(error?.message ?? error) } });
        }
      },
    }), 'dsh-undo-savepoint.api');
  }
}
