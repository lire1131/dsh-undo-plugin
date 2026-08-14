/**
 * dsh-undo: undo/rollback system for DeepSeek Harness.
 *
 * - Tools: undo_snapshot / undo_list / undo_diff / undo_restore
 * - Auto-archiving: snapshots config files whenever they change (debounced),
 *   plus a baseline on mount, so every plugin install / skin apply / settings
 *   save is automatically reversible.
 * - WebUI: REST endpoints under /api/undo/* power the undo/redo buttons in the
 *   input dock (client half in lib/client.js).
 * - Undo/redo stack: snapshots are records of config states. Because an auto
 *   snapshot captures the state AFTER a change, "undo last action" restores
 *   the newest snapshot whose state differs from the current one (stepping
 *   back one record when current already matches the newest). Every restore
 *   first stores the current state as a "pre-restore" snapshot; redo
 *   re-applies the newest unconsumed pre-restore (blocked when newer changes
 *   exist). Restoring cordis.patch.yml re-ensures this plugin's own mount
 *   line, so undo can never undo itself out of existence.
 *
 * Snapshot store: <snapshotDir>/<id>/manifest.json + copies of the config
 * files. The external PowerShell tool (tools/dsh-undo.ps1) shares the same
 * store and format and works even when DSH cannot boot.
 *
 * @module dsh-undo
 */
import { createRequire } from 'node:module';
import { promises as fs, watch as fsWatch, existsSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash, randomBytes } from 'node:crypto';

/** DSH install root; override via $DSH_ROOT when the harness lives elsewhere. */
const DSH_ROOT = process.env.DSH_ROOT ?? 'C:/Users/yzf';
const require = createRequire(join(DSH_ROOT, 'package.json'));

let defineTool;
try {
  ({ defineTool } = require('@deepseek-ai/dsh-tools'));
} catch {
  // Older Node without require(esm): fall back to a file:// dynamic import.
  const mod = await import(pathToFileURL(join(DSH_ROOT, 'node_modules/@deepseek-ai/dsh-tools/lib/index.js')).href);
  defineTool = mod.defineTool;
}

export const name = 'dsh-undo';
export const inject = ['tools', 'systemPrompt'];

const HOST_DEFAULTS = {
  /** Where snapshots live. Outside ~/.dsh on purpose: survives reinstall. */
  snapshotDir: 'D:/dsh/undo-snapshots',
  /** DSH user-data root (~/.dsh). */
  homeDir: join(process.env.USERPROFILE ?? 'C:/Users/yzf', '.dsh'),
  /** Profile directory whose config files are snapshotted. */
  profileDir: join(process.env.USERPROFILE ?? 'C:/Users/yzf', '.dsh', 'profiles', 'web'),
  /** Auto/baseline snapshots kept; manual and pre-restore snapshots are never pruned. */
  keepAuto: 20,
  /** Debounce for the config-file watcher (ms). */
  watchDebounceMs: 1500,
};

/** The config files that make up a "DSH state". Must mirror tools/dsh-undo.ps1. */
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
  return root === 'profile' ? cfg.profileDir : cfg.homeDir;
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

async function readManifest(dir) {
  const text = await fs.readFile(join(dir, 'manifest.json'), 'utf8');
  return JSON.parse(text.replace(/^\uFEFF/, '')); // tolerate a BOM (PS5.1 wrote it)
}

async function writeManifest(dir, snap) {
  await fs.writeFile(join(dir, 'manifest.json'), JSON.stringify(snap, null, 2), 'utf8');
}

/** Create a snapshot: copy every existing config file into <dir>/ and write manifest.json. */
async function createSnapshot(cfg, kind, reason) {
  await fs.mkdir(cfg.snapshotDir, { recursive: true });
  const id = makeId();
  const dir = join(cfg.snapshotDir, id);
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

/** List snapshots newest-first. */
async function listSnapshots(cfg) {
  if (!(await pathExists(cfg.snapshotDir))) return [];
  const out = [];
  for (const entry of await fs.readdir(cfg.snapshotDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    try { out.push(await readManifest(join(cfg.snapshotDir, entry.name))); } catch { /* ignore broken */ }
  }
  out.sort((a, b) => (a.time < b.time ? 1 : a.time > b.time ? -1 : 0));
  return out;
}

function findSnapshot(list, id) {
  return list.find((s) => s.id === id) ?? null;
}

/** Content-hash the state a snapshot recorded: sorted [name, sha1] pairs of its files. */
async function stateOf(cfg, snap) {
  const dir = join(cfg.snapshotDir, snap.id);
  const pairs = [];
  for (const file of (snap.files ?? [])) {
    try {
      const buf = await fs.readFile(join(dir, file.name));
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
  const dir = join(cfg.snapshotDir, snap.id);
  const restored = [];
  const hashes = new Map();
  for (const file of (snap.files ?? [])) {
    const spec = findSpec(file.name);
    if (!spec) continue;
    const src = join(dir, file.name);
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
async function ensureMount(cfg) {
  const patch = filePath(cfg, { root: 'profile', rel: 'cordis.patch.yml' });
  if (!(await pathExists(patch))) return false;
  let text = await fs.readFile(patch, 'utf8');
  if (text.includes('dsh-undo')) return false;
  // A bare `[]` flow array cannot be extended by appending block items; drop it.
  text = text.replace(/^\s*\[\]\s*$/m, '');
  const block = `\n# dsh-undo mount (re-ensured by dsh-undo)\n- insert:\n    - id: dsh-undo\n      name: dsh-undo\n`;
  await fs.writeFile(patch, text.replace(/\s*$/, '') + block, 'utf8');
  return true;
}

/** Prune auto/baseline snapshots beyond keepAuto (oldest first). */
async function pruneAuto(cfg, list) {
  const auto = list.filter((s) => s.kind === 'auto' || s.kind === 'baseline')
    .sort((a, b) => (a.time < b.time ? -1 : 1));
  const excess = auto.slice(0, Math.max(0, auto.length - cfg.keepAuto));
  for (const snap of excess) {
    await fs.rm(join(cfg.snapshotDir, snap.id), { recursive: true, force: true });
  }
  return excess.length;
}

async function markFlag(cfg, snap, flag, value) {
  const dir = join(cfg.snapshotDir, snap.id);
  if (!(await pathExists(join(dir, 'manifest.json')))) return;
  snap[flag] = value;
  await writeManifest(dir, snap);
}

/** Simple line-level diff summary between current files and a snapshot. */
async function diffSnapshot(cfg, snap) {
  const lines = [];
  const dir = join(cfg.snapshotDir, snap.id);
  for (const spec of FILE_SPECS) {
    const src = filePath(cfg, spec);
    const name = destName(spec);
    const snapPath = join(dir, name);
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
  for (const p of unconsumedPre) preStates.push(await stateOf(cfg, p));
  const candidates = [];
  for (const s of list) {
    if (s.kind === 'pre-restore') continue;
    const st = await stateOf(cfg, s);
    if (preStates.some((p) => sameState(p, st))) continue; // undid from this state
    candidates.push({ s, st });
  }
  return candidates;
}

/**
 * Undo/redo stack.
 * undo: if the current state matches the newest candidate, step back one
 *   record (the newest candidate is the post-change record); otherwise
 *   restore the newest candidate (drift case). The current state is always
 *   preserved as a pre-restore snapshot first.
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
    // Undo only snaps back to a state that actually differs from the current
    // one; identical snapshots (e.g. nothing changed since they were taken)
    // are skipped, and if none differs we say so instead of pretending.
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
      if (stepped) await markFlag(cfg, candidates[0].s, 'stepped', true);
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
      await markFlag(cfg, pre, 'consumed', true);
      // Un-step any regular snapshot whose state matches the consumed pre-restore,
      // so a later undo can walk back through it again.
      const preState = await stateOf(cfg, pre);
      for (const s of list) {
        if (s.kind === 'pre-restore' || !s.stepped) continue;
        if (sameState(preState, await stateOf(cfg, s))) await markFlag(cfg, s, 'stepped', false);
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

function renderRestoreResult(r) {
  if (!r.ok) return `undo_restore failed: ${r.error}`;
  if (r.unchanged) return r.message ?? 'No undoable changes.';
  const lines = [
    `Restored snapshot ${r.targetId} (${r.targetKind}${r.targetReason ? `: ${r.targetReason}` : ''})`,
    `Files restored: ${r.restored.length > 0 ? r.restored.join(', ') : '(none)'}`,
    `Current state preserved as ${r.preSnapshotId} (redo target)`,
  ];
  if (r.stepped) lines.push('(stepped back past a post-change record)');
  if (r.remounted) lines.push('dsh-undo mount re-ensured in cordis.patch.yml');
  return lines.join('\n');
}

const TEXT_OUTPUT = {
  schema: { type: 'string' },
  render: (_args, value) => [{ type: 'text', text: String(value) }],
};

const PROMPT_TEXT = `## Undo / rollback (dsh-undo)
When the user asks to undo the previous action ("撤销上一步", "回退", "恢复", "redo") — typically after installing a plugin, applying a skin, or changing settings — do NOT guess or hand-edit config files:
1. Call undo_list to show available snapshots (auto-created whenever config files change, plus manual ones).
2. Call undo_restore with mode "undo" to revert the latest change, mode "redo" to re-apply the state saved before the last undo, or mode "id" with a snapshot id from undo_list. Use undo_diff to preview first when unsure.
3. undo_restore never destroys the current state (it is kept as a pre-restore snapshot) and always re-ensures the dsh-undo mount itself.
Note: this system only reverts DSH config/plugin/skin state, not chat history.`;

/**
 * Host plugin body.
 * @param {import('@deepseek-ai/cordis').Context} ctx
 * @param {object} config
 */
export function apply(ctx, config = {}) {
  const cfg = {
    snapshotDir: config.snapshotDir ?? HOST_DEFAULTS.snapshotDir,
    homeDir: config.homeDir ?? HOST_DEFAULTS.homeDir,
    profileDir: config.profileDir ?? HOST_DEFAULTS.profileDir,
    keepAuto: config.keepAuto ?? HOST_DEFAULTS.keepAuto,
    watchDebounceMs: config.watchDebounceMs ?? HOST_DEFAULTS.watchDebounceMs,
    /** >0 while a restore is writing files: the watcher must NOT auto-snapshot
     * the restore's own writes, or the new auto snapshot would block redo. */
    suppressAuto: 0,
    /** destName -> sha1 of what the last restore wrote (echo detection). */
    restoredHashes: new Map(),
  };

  // ── tools ──────────────────────────────────────────────────────────────
  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_snapshot',
    description: 'Create a manual config snapshot (DSH config files: cordis.patch.yml, package.json, settings.yaml, .env…). Snapshots are auto-created on config changes anyway; use this to pin a known-good state with a reason.',
    parameters: {
      reason: { type: 'string', description: 'Why this snapshot is taken (e.g. "before installing X", "known-good baseline").' },
    },
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async (args) => {
      const reason = typeof args?.reason === 'string' && args.reason !== '' ? args.reason : 'manual';
      const snap = await createSnapshot(cfg, 'manual', reason);
      return `Snapshot ${snap.id} created (${snap.files.length} file(s), reason: ${reason}). Store: ${cfg.snapshotDir}`;
    },
  })), 'dsh-undo.tool.snapshot');

  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_list',
    description: 'List all undo snapshots (newest first): id, time, kind (auto/manual/baseline/pre-restore), reason, file count, markers (stepped/consumed). Use before undo_restore to pick a target.',
    parameters: {},
    output: TEXT_OUTPUT,
    isConcurrencySafe: () => true,
    execute: async () => {
      const list = await listSnapshots(cfg);
      if (list.length === 0) return 'No snapshots yet. They appear automatically when config files change.';
      const rows = list.map((s) => {
        const mark = [s.stepped ? 'stepped' : '', s.consumed ? 'consumed' : ''].filter(Boolean).join(',');
        return `${s.id}  ${(s.time ?? '').replace('T', ' ').slice(0, 19)}  ${s.kind}${mark ? ` [${mark}]` : ''}  ${(s.reason ?? '').slice(0, 60)}  (${s.files.length} file(s))`;
      });
      return `Snapshots (newest first):\n${rows.join('\n')}\n\nStore: ${cfg.snapshotDir}`;
    },
  })), 'dsh-undo.tool.list');

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
  })), 'dsh-undo.tool.diff');

  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'undo_restore',
    description: 'Roll back DSH config to a snapshot. mode "undo" reverts the latest change (undo last action; repeats walk further back); mode "redo" re-applies the state saved before the last undo (only when nothing changed since); mode "id" restores an explicit snapshot from undo_list. The current state is always preserved as a pre-restore snapshot first, and the dsh-undo mount itself is re-ensured.',
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
  })), 'dsh-undo.tool.restore');

  ctx.effect(() => ctx.systemPrompt.section({
    name: 'tool:dsh-undo',
    order: 117,
    text: PROMPT_TEXT,
  }), 'dsh-undo.prompt');

  // ── baseline snapshot (one per mount) ──────────────────────────────────
  void (async () => {
    try {
      const snap = await createSnapshot(cfg, 'baseline', 'plugin-mounted');
      const list = await listSnapshots(cfg);
      const pruned = await pruneAuto(cfg, list);
      ctx.logger.info(`[dsh-undo] baseline snapshot ${snap.id}${pruned > 0 ? ` (pruned ${pruned})` : ''}`);
    } catch (error) {
      ctx.logger.warn(`[dsh-undo] baseline failed: ${String(error?.message ?? error)}`);
    }
  })();

  // ── auto-archive watcher (debounced) ───────────────────────────────────
  if (config.watch !== false) {
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
          const snap = await createSnapshot(cfg, 'auto', 'config-change');
          const list = await listSnapshots(cfg);
          const pruned = await pruneAuto(cfg, list);
          if (snap.files.length > 0) ctx.logger.info(`[dsh-undo] auto snapshot ${snap.id} (${snap.files.length} file(s)${pruned > 0 ? `, pruned ${pruned}` : ''})`);
        } catch (error) {
          ctx.logger.warn(`[dsh-undo] auto snapshot failed: ${String(error?.message ?? error)}`);
        }
      }, cfg.watchDebounceMs);
    };
    const onEvent = (_event, filename) => {
      if (typeof filename !== 'string' || !WATCHED_BASENAMES.has(basename(filename))) return;
      pending.add(filename);
      schedule();
    };
    ctx.effect(() => {
      const watchers = [];
      for (const dir of [cfg.profileDir, cfg.homeDir]) {
        if (!existsSync(dir)) continue;
        try {
          watchers.push(fsWatch(dir, onEvent));
        } catch (error) {
          ctx.logger.warn(`[dsh-undo] cannot watch ${dir}: ${String(error?.message ?? error)}`);
        }
      }
      return () => {
        for (const w of watchers) { try { w.close(); } catch { /* noop */ } }
        if (timer) clearTimeout(timer);
      };
    }, 'dsh-undo.watch');
  }

  // ── REST API for the WebUI buttons ─────────────────────────────────────
  const webServer = ctx.get('webServer');
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
    ctx.effect(() => webServer.register({
      kind: 'prefix',
      path: '/api/undo',
      handler: async (req, res) => {
        try {
          const url = new URL(req.url ?? '/', 'http://dsh.local');
          const path = url.pathname;
          const method = (req.method ?? 'GET').toUpperCase();
          if (method === 'GET' && path === '/api/undo/list') {
            return send(res, 200, { ok: true, snapshots: await listSnapshots(cfg) });
          }
          if (method === 'GET' && path === '/api/undo/status') {
            const list = await listSnapshots(cfg);
            const cur = await currentState(cfg);
            const candidates = await undoCandidates(cfg, list);
            const canUndo = candidates.some((c) => !sameState(cur, c.st));
            const pre = list.find((s) => s.kind === 'pre-restore' && !s.consumed);
            const canRedo = pre !== undefined
              && !list.some((s) => s.time > pre.time && (s.kind !== 'pre-restore' || !s.consumed));
            return send(res, 200, { ok: true, canUndo, canRedo, total: list.length });
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
          if (method === 'POST' && path === '/api/undo/snapshot') {
            const body = await readJson(req);
            return send(res, 200, { ok: true, snapshot: await createSnapshot(cfg, 'manual', body?.reason ?? 'manual:api') });
          }
          return send(res, 404, { ok: false, error: { code: 'not-found', message: `unknown route ${path}` } });
        } catch (error) {
          return send(res, 500, { ok: false, error: { code: 'internal', message: String(error?.message ?? error) } });
        }
      },
    }), 'dsh-undo.api');
  }
}
