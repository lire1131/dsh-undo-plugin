# Changelog

Notable changes to dsh-undo-savepoint. Dates are in local time (UTC+8). 中文版:[CHANGELOG.md](CHANGELOG.md)

## [0.3.9] - 2026-08-22

### Added (roadmap R1+R4+I13)

- **R1 · i18n (host / CLI / WebUI together)**:
  - New `lib/i18n/{zh,en}.json` is the single dictionary source (140 keys covering every user-visible host message and all WebUI strings); a zero-dependency translator `lib/i18n.mjs` (`t(key, vars?, lang?)`) picks language with priority `DSH_UNDO_LANG` > machine `Intl`/`LANG` Chinese > en fallback
  - Host `lib/index.js` now routes user-visible text through `t()`: safe mode (enter / already-on / rescan / neutralized / patch note / status / exit / corrupt-package refusal), undo/redo/restore result rendering, busy guard, and snapshot/list/diff/prune/export/import/recent output. `smoke` pins `DSH_UNDO_LANG=en` so existing English assertions stay valid
  - WebUI (`lib/client.js`) keeps `ctx.locale.register/bind` (confirmed compatible with rc8), and its inline zh/en dictionary is cross-checked against `lib/i18n` with a **single-source consistency assertion** (every client key exists non-empty in JSON, zh/en key sets match), preventing the two from drifting
  - Offline CLI (`dsh-undo.ps1` / `dsh-undo-savepoint-lib.ps1`): new `Get-UndoLanguage` / `Get-UndoText` (reads `lib/i18n/*.json`, selects via `DSH_UNDO_LANG` / `$PSUICulture`); `snapshot`, `undo` and other result text are bilingual. `.ps1` files keep UTF-8 with BOM
- **R4 · artifact size gate tightened to 5M**: new `tools/check-size.mjs` scans `lib/` + `tools/` + top-level `package.json`/README/CHANGELOG/LICENSE/`cordis.patch.yml`, skipping `node_modules/.git/.github/docs`; `npm test` runs it first and fails on >5MB. Current artifact ≈565KB
- **I13 · theme variables (`--dsw-alias-*`)**: WebUI `client.js` hard-coded colors moved to `--dsw-alias-bg-layer-1 / --dsw-alias-bg-mask-1 / --dsw-alias-border-l3 / --dsw-alias-state-error-primary / --dsw-alias-state-success-primary / --dsw-alias-state-business-primary` (`--dsw-specific-tip` kept), for theme switching

### Tests
- smoke 174 → 180 (+6 WebUI/dictionary consistency assertions); full `npm test` chain (check-size → check-version → smoke → home-resolution → e2e) green
- e2e 10/10 no regression; CLI `status` runs under `DSH_UNDO_LANG=en`

### Entry points
- Env var: `DSH_UNDO_LANG` (`zh`/`en`; defaults to Chinese on Chinese hosts, otherwise English)

## [0.3.8] - 2026-08-21

### Added (Safe Mode 2.0, roadmap R2+P1+B4+B5+B6)

- **P1 · Safe-mode bundle neutralization**: safe mode previously only minimized the patch layer — useless when DSH cannot boot because a profile bundle fails the loader's hard checks. On entry, every `dsh.profile.bundles` entry is now validated with the same three rules as dsh-app-boot `loadProfile` (resolvable / has `dsh.bundle.patch` / patch file exists); failing entries are removed and written back (the original `package.json` is double-backed-up: snapshot + dedicated `safe-mode-pkg-<id>.json`). On exit the file is restored in full and the report names how many entries were neutralized. Edges: a missing `package.json` is skipped without blocking entry; a corrupt one refuses entry and is never destructively rewritten. Idempotent rescan: re-running `on` while active only rescans and reports, never rewrites
- **B5 · Crash attribution v2 (crashReason)**: after a crash, the next startup scans the tail of candidate logs and classifies the crash as `session-corrupt` (session file damage) / `bundle-check` (bundle hard-check failure) / `patch-tree` (plugin mount/load failure) / `unknown`, persisted in `boot-state.json` (reused on the next boot so log rotation cannot lose the attribution). The `undo_list` crash banner now suggests a remedy per class (session-corrupt → `undo_scan`, bundle-check → safe mode), and `/api/undo/status` exposes `crashReason`
- **B6 · `undo_scan` session health scan & repair**: scans `<home>/sessions/**/session.jsonl.zstd` and classifies each as `ok` / `fixable` (single-frame layout violation, the 8/18 crash root cause) / `corrupt` (undecodable / invalid first header line / bad JSON lines). With `quarantine=true`, `fixable` files are repaired in place: the original is copied to `<undo root>/corrupt-quarantine/` and kept as `.bak`, then recoded to "header frame + event frame" with triple verification (round-trip text identical / per-line JSON / re-analysis); `corrupt` files are only isolated (copied, never touched). Also ships `dsh-undo.ps1 scan [--fix] [-Label <home>]` and the offline script `tools/session-scan.mjs` (usable when DSH cannot boot). **Requires Node ≥22.15** (the `node:zlib` zstd API); on Node 20 `undo_scan` degrades to a clear "unsupported" notice while the rest of the plugin keeps working
- **B4 · dsh-session-persistence-jsonl patch hosting**: the 3 tolerance patches (`appendBatch` self-heal / `listArtifacts` isolation / `readFirstZstdLine` tolerant) are hosted as `tools/dsh-patches.json` (old = rc8 original code, new = rc6 verified patches); `tools/apply-dsh-patches.ps1 status|verify|apply|remove` applies/reverts them offline (per-patch backup `.bak-<id>`, aborts on unknown state without writing). The plugin verifies read-only at startup and warns (never auto-edits files), and safe-mode entry reports missing patches too

### Polish
- `undo_safe_mode` tool description and WebUI confirm copy updated to v0.3.8 capabilities (bundle neutralization)

### Tests
- smoke 146 → 174 (5 new sections, 28 new assertions): P1 bundle-neutralization round trip + corrupt-package.json refusal, B5 log-signature classification (session-corrupt / bundle-check scenarios), B6 scan/repair/isolate/rescan, patch manifest old/new exactly matching the real rc8/rc6 targets
- Fixed: edited `.ps1` files carry UTF-8 BOM again (case 25 encoding audit regression guard)
- Final verification: smoke 174 green; e2e 10/10 no regression; home-resolution 2 branches green

## [0.3.7] - 2026-08-21

### Fixed (emergency release)
- **issue #11: desktop-shortcut script encoding**: `tools/make-desktop-shortcut.ps1` converted to UTF-8 with BOM (Windows PowerShell 5.x on a Chinese system parsed the BOM-less UTF-8 file as GBK, breaking string quotes → ParserError → shortcut creation failed). A new smoke encoding-audit case fails any non-ASCII `.ps1/.bat` without BOM, preventing regression
- **Safe mode self-deletion / dangling-reference fixes (completing the 8/17 retro)**
  - Empty-backup fallback: when the profile patch is missing on entry, the backup is written as `[]` (semantics: no user plugins to disable) instead of leaving a dangling reference that could never exit
  - Invariant assertion: `active ⇒ every backup file exists`; entry is refused if the assertion fails
  - Dual-level patches: the home-level `cordis.patch.yml` is now backed up/minimized/restored together with the profile one (previously safe mode only managed the profile patch, so plugins mounted at home level were unaffected)
  - Home fingerprint: the state records a fingerprint (home root + profile + settings.yaml stats); a rebuilt home / machine switch degrades any leftover state to inactive with a warning, never carrying the old home's safe mode into the new home
  - Startup self-heal: if the undo mount is missing while safe mode is active (profile-init race), it is re-ensured automatically at startup
- **rc8 double-mount startup crash (2026-08-21 incident)**
  - `dedupeMount` startup dedup: scans every mount source (bundles / profile patch incl. includes / home patch) and keeps only the canonical one (bundle > profile patch > home patch), backing up files to `.dsh-undo-bak` before touching them
  - `registerToolOnce` registration guard: a duplicate tool registration only warns and skips — startup never dies
  - The `safeEffect` rc8 compatibility lid (already in the working tree) is now part of the release

### Improved
- **5 MB per-snapshot budget (R3)**: `pluginMaxSnapshotBytes` 10 MB → 5 MB; manifests now record `totalBytes` (materialized size) and `undo_list` shows size plus a `[truncated]` marker. Over-budget snapshots keep the existing "manifest-only + warn, no data loss" behavior
- **Tiny-snapshot guarantee**: new smoke assertion — a snapshot with no external plugins stays under 100 KB total

### Tests
- smoke 114 → 146 (+10 sections, +32 assertions): encoding audit, tiny snapshot + totalBytes, safe mode with missing patch, brand-new home roundtrip, dual-level patch backup/restore, home-fingerprint degradation, startup self-heal, 5 MB truncation, double-mount dedup (patch+patch / patch+bundle), duplicate-registration degradation + safeEffect lid
- Cleanup robustness: `fs.rm` now retries on Windows' occasional ENOTEMPTY (AV/indexer briefly holding directory handles)
- e2e 10/10 no regression; home-resolution 2 branches green; CI runs on windows-latest × node[20,22]

## [0.3.6] - 2026-08-20

### Fixed
- **Boot-critical snapshot coverage**: profile-level `pnpm-lock.yaml` and home-level `cordis.patch.yml` are now snapshotted, matching the state `dsh plugin add/update/remove` actually mutates (issue #8)
- **Dependency reconciliation after restore**: when undo/redo/restore touches `package.json` / `pnpm-lock.yaml` / `pnpm-workspace.yaml`, the default result reports that `node_modules` may be out of sync and prints the rebuild command. An explicit sync runs `pnpm install --frozen-lockfile` (plain `pnpm install` without a lockfile); a failed install never rolls back the restored config files
- **Watcher fault tolerance (surfaced by the node 20 CI job)**: `fs.watch` now attaches an `error` handler. When a watched directory is deleted or renamed (test temp-dir cleanup, real-world plugin uninstall/rename), the Windows FSWatcher asynchronously throws `EPERM`; previously it crashed the whole process as an unhandled exception. Now the watcher is closed and logged instead

### Improved
- **npm install removed from docs**: README no longer advertises the npm-registry install; install options are now GitHub direct (way A) and local source (way B)

### Entry points
- Offline CLI: `dsh-undo.ps1 undo|redo|restore -SyncDeps`
- Model tool: `undo_restore` gains an optional `sync_deps` boolean
- REST: `/api/undo/undo|redo|restore` accept optional `syncDeps`

### CI (Windows-only, no cross-platform)
- **CI moved to windows-latest**: the plugin is Windows-only (`runPnpm` goes through `cmd.exe`, tests use a `.cmd` fake pnpm, bundled `.ps1/.bat` tools). CI previously ran on ubuntu-latest, where section 24's fake-pnpm test always failed (`pnpm.cmd` never runs on Linux; the missing marker then threw an uncaught ENOENT). CI now matches the real deployment environment
- **fail-fast: false**: the node 20 / 22 matrix jobs each finish and report independently instead of cancelling each other
- **home-resolution-test.mjs now runs in CI**: aligns CI with the 4-script `npm test` suite (the issue #6 DSH_HOME regression was previously skipped)
- **smoke-test §24 diagnostics hardened**: a sync_deps failure prints the restore output tail, and a missing marker yields a clear assertion instead of an uncaught ENOENT masking the real failure

### Tests
- smoke 106 → 114 (lockfile/home-patch snapshots, byte-level restore, default report-only, explicit sync command verification, spec.json consistency assertion)
- e2e 10/10, no regressions; CI green on windows-latest × node[20,22]

## [0.3.5] - 2026-08-17

### Fixed
- **`DSH_HOME` support** (issue #6): home resolution now prefers the `DSH_HOME` env var and falls back to `~/.dsh`, matching the official DSH launcher. Previously every `.dsh`-relative path (settings file, snapshot root, profile dir) was hardcoded to `~/.dsh`, so third-party clients with a non-default home lost settings and custom snapshot dirs reverted after restart
  - `lib/index.js`: new `DSH_HOME_DIR` constant (`DSH_HOME` ?? `join(HOME, '.dsh')`) used by `LEGACY_ROOT` / `SETTINGS_FILE` / `rootDir()` / `profileDir`
  - `tools/dsh-undo-savepoint-lib.ps1`: aligned, `$script:DshHome` prefers `$env:DSH_HOME`
  - `tools/make-desktop-shortcut.ps1`: shortcut candidates honor `$DSH_HOME` (custom-home clients can still auto-locate the plugin)
  - `DSH_UNDO_ROOT` / `DSH_UNDO_SETTINGS` explicit overrides keep their precedence
  - `node_modules` discovery stays on `HOME` (user-level, not inside `.dsh`)

### Improved
- **README preview images now load via the jsDelivr CDN** (`cdn.jsdelivr.net/gh/lire1131/dsh-undo-plugin@master/docs/*.png`): `raw.githubusercontent.com` is frequently blocked on mainland-China networks, which broke the repo-page images; the CDN loads reliably. Images are cached (~12h); force-refresh via `https://purge.jsdelivr.net/gh/lire1131/dsh-undo-plugin@master/`

### Tests
- smoke 106/106, e2e 10/10 (no regressions)
- Manual DSH_HOME validation: with `DSH_HOME=/tmp/fake`, snapshots and settings are written under that path with no `~/.dsh` residue; unset keeps the old fallback
- New automated regression `tools/home-resolution-test.mjs` (both branches: `DSH_HOME` honored / default `~/.dsh` fallback; asserts snapshot capture sources and settings-file location), wired into `npm test` and CI

## [0.3.4] - 2026-08-16

### Added
- **WebUI snapshot entry points overhaul** (replaces community PR #4's two-tiny-camera-icons approach with a full UI pass):
  - The conversation-header **Undo / Redo / Snapshots** buttons are all iconized (red ↶ / green ↷ / camera; monochrome `currentColor`, theme-adaptive)
  - The **Snapshots button now performs a one-click manual snapshot** (equivalent to the panel's Save; the header flashes "Snapshot <id>" on success) instead of opening the panel
  - New **auto-snapshot status badge** in the header: green dot + "N snapshot(s) · x min ago", auto-refreshing every 30 s (the badge updates the moment a config change lands as an auto-snapshot); **clicking the badge opens the snapshot panel**
  - Snapshot-panel header: camera icon + title + current-**profile** subtitle (read from the newest snapshot's manifest `profile` field — making the v0.3.3 multi-profile support visible)
- Client-only change (`lib/client.js`); host logic and snapshots untouched

### Fixed
- **Undo/redo/restore/safe-mode are rejected while any live session has an open turn (agent in progress)**: the operation is refused with a clear message (host-side guard + WebUI-specific notice). Previously an undo rewrote `cordis.patch.yml` and triggered DSH's built-in HMR plugin-tree rebuild, interrupting every running session beyond recovery (the reported "accidental undo crashed the whole workspace"); behavior is fully unchanged when idle

### Tests
- smoke 101 → 106 (running-session guard: open turn rejected and config untouched / safe-mode rejected and patch untouched / closed turn allowed)

## [0.3.3] - 2026-08-16

### Added
- **Multi-profile support** (issue #3): the current profile is parsed from `process.argv` (`--profile mine` / `--profile=mine`; `dsh web` falls back to `web`), overridable via `config.profileName`
  - `profileDir` now defaults to the CURRENT profile directory (previously hardcoded to `web` — under any other profile snapshots read the wrong files, the watcher missed changes, and restores wrote to the wrong place)
  - Snapshot stores are per-profile: `<snapshotRoot>/<profileName>/{auto,manual}`; legacy fallback keeps working — if the scoped dir does not exist but the old flat store does, the flat store is used (old data never hidden)
  - manifest gains a `profile` field; `undo_list` shows the current profile
  - Offline CLI/GUI: `DSH_UNDO_PROFILE` env var or `profileName` in settings (offline tools cannot see argv)
  - Explicit config (`profileDir` / `manualDir` / `autoDir` / `profileName`) still wins
- **ps1 offline tools honor `DSH_UNDO_ROOT` / `DSH_UNDO_SETTINGS`** (matching the Node plugin; previously the CLI only knew the default paths, so custom-store users got out of sync offline)
- **package.json declares `dsh.runtime: "host"`** (WhaleHarness audit gate: using child_process requires the host runtime declaration)

### Fixed
- settings.json default-location migration: data configured at the legacy location (e.g. `D:\dsh\undo\settings.json`) no longer goes "missing" — the new location reads it and keeps using the configured directories

### Tests
- smoke 98 → 101 (argv parsing / manifest profile / explicit profileName override); e2e 10/10

## [0.3.2] - 2026-08-15

### Added
- **Sensitive-info redaction + local vault** (on by default): `.env` and `.credentials.yaml` enter snapshots with values replaced by `***REDACTED***` (keys / `export` / quotes / comments / structure fully preserved) — snapshots and exported ZIPs are safe to share; the real values live in a local vault (`<autoDir>/env-vault/`, content-addressed), so **local rollbacks restore values completely**, while cross-machine rollbacks yield placeholders with a clear note
  - `sensitiveMode` setting: `redact` (default) / `keep` (plaintext legacy); old snapshots stay compatible
  - **diff redacts BOTH sides** (snapshot and current, incl. old plaintext snapshots) — real values never appear in the UI
- **`.credentials.yaml` added to the snapshot scope** (it was missing before — a broken credentials file was unrecoverable both in-UI and offline)
- **Offline emergency tooling completed** (everything needed when DSH is down):
  - **GUI crash banner fixed & upgraded**: reads `boot-state.json` (the old `.booting` check silently broke after v0.3), shows the last-known-good snapshot with one-click rollback to that exact snapshot
  - **GUI one-click SAFE MODE button** (on/off with confirmation); **GUI title bar shows the current sensitive mode**
  - **CLI `recent` command**: rollback log viewer (WebUI `undo_recent` counterpart)
  - **CLI `settings -Label "key=value;..."`**: edit settings offline (previously read-only)
  - **CLI undo/redo/restore output enriched**: needsRestart / cross-machine preflight warning / redacted-placeholder notes
- **WebUI settings moved to their own sidebar section** ("Snapshots"): one full page with sensitive-mode dropdown, plugin-dirs whitelist and 📁 dir pickers — no longer squeezed into General
- **Settings parity fixed**: ps1 now reads back keepPre/autoCleanup (the GUI used to open them empty and overwrite WebUI-set values); GUI dir pickers use a "Browse" button
- **Orphan blob cleanup**: `undo_prune` also deletes plugin-code blobs no snapshot references anymore (cross-machine import leftovers no longer waste space)
- **Export sensitive warning**: when keep-mode or legacy snapshots hold plaintext secrets, export (chat / WebUI / CLI) warns "contains REAL secrets — do not share"
- **`undo_list` shows the sensitive mode** plus how many files the latest snapshot redacted

### Fixed
- ps1 `Get-UndoBootAlert` upgraded to read `boot-state.json` (incl. `lastGoodAt`); new `Get-UndoLastGoodId`
- GUI toolbar overflow hid buttons behind the list (two-row layout + single-instance Mutex)
- diff leaked real values from the current-file side (e.g. `DEEPSEEK_API_KEY: sk-...`) — both sides redacted now

### Tests
- smoke 76 → 98 (redaction shapes / vault full local restore / cross-machine placeholder / diff zero-leak both sides / keep plaintext / orphan blob cleanup / old-snapshot compat); e2e 10/10

## [0.3.1] - 2026-08-15

### Added
- **Cross-machine preflight**: undo/redo/restore now scan the target snapshot's plugin references (patch mount entries + `package.json` bundles) and clearly report any that this machine cannot resolve, warning "DSH may fail to start after restore" and suggesting installing them first or booting via safe mode
  - Multi-anchor probing (user `node_modules` / profile dependency tree / plugin location chain) — resolvable from any anchor counts as installed, avoiding false positives under junction installs
  - Local file entries (`name: './xxx'`) are not probed; preflight results are written to the rollback log
- **docs/migration bilingual guide**: cross-machine restore behavior (plugin code is never dumped into the target machine, blob leftovers, the missing-plugin pitfall) + best practices, in Chinese and English

### Fixed
- `toolsRequire` hoisted from block scope to module scope (its ReferenceError used to be silently swallowed by a try/catch; multi-anchor probing depends on it)

## [0.3.0] - 2026-08-15

### Added (safety net: crash attribution + safe mode + restart notice, phase 2)
- **Crash attribution upgrade**: the `.booting` marker becomes `boot-state.json` (per-run result + last-good-boot timestamp); after an abnormal exit, `undo_list` and the WebUI name the **concrete last-known-good snapshot** with a one-click rollback button
- **One-click SAFE MODE**: `undo_safe_mode` tool (usable in chat) + WebUI "Safe mode" button in the snapshot panel + offline CLI `safe-mode on|off|status` — entering auto-snapshots, backs up `cordis.patch.yml` and minimizes the patch (undo only) so DSH can always boot; exiting restores the previous set. Ultimate fallback when DSH cannot boot at all
- **Restart notice**: when an undo/redo/restore touches plugin code or the mount config, the report and WebUI clearly say "a DSH restart is required"; the rollback log records it too

## [0.2.1] - 2026-08-15

### Added
- **One-click desktop shortcut**: `tools/make-desktop-shortcut.bat` (double-click) / `.ps1` (CLI) auto-locates the plugin directory and creates a **DSH Undo Manager** shortcut on the desktop — fixes "I installed it and cannot find the external tools"
- **README "Where are the external tools?" section**: exact tool paths for both install methods + a self-contained one-liner (auto-locates and creates the shortcut, no need to find any file first) + a command to open the tools folder

### Fixed
- Documented the repo/package name mismatch: the install command says `dsh-undo-plugin`, but the installed folder is named after the **package name `dsh-undo-savepoint`** — searching by repo name can never find it

## [0.2.0] - 2026-08-15

### Added (plugin-code-level rollback, phase 1)
- **Plugin code tree snapshots**: auto-discovers user plugins (junctions under `node_modules`, e.g. `D:\dsh\plugins\*`) plus profile-local code files (`name: './xxx'` entries in `cordis.patch.yml`, e.g. `router-global.mjs`) — a broken plugin EDIT is now undoable even when no config file changed (e.g. the whale-kit "yield* is not async iterable" incident)
- **4 size safeguards**: extension whitelist (only code/config files — assets like gif/png never enter snapshots; dsh-pet 57MB -> ~47KB), content-addressed blob store (`<snapshotRoot>/blobs`, unchanged files cost nothing), per-file / per-snapshot caps (oversized files recorded as `skipped`), restore resolves by reference (missing blobs reported explicitly)
- **Plugin-file diff**: `undo_diff` and the WebUI diff preview show `plugin:xxx` / `profile:xxx` entries
- **Plugin watcher**: code changes in plugin trees auto-snapshot as `plugin-code-change`; the restore's own writes are echo-suppressed
- **Single source of truth `lib/spec.json`**: Node and PowerShell tooling share one snapshot-scope definition
- **`pluginDirs` setting**: explicit plugin whitelist (`[]` disables auto-discovery for tests/isolated use)
- **Export/import include the blob store**: restores keep working after backup/migration
- Manifest records plugin name/version/skips; `undo_list` shows plugin file counts; restore reports `missing` items

### Fixed
- Old snapshots (no `plugins` field) polluted state/diff under the PowerShell tools via the `@($null)` single-element-array trap (now filtered)
- Offline CLI `diff` now uses the shared `Get-UndoDiffText` implementation (plugin files included)
- ps1 files saved as UTF-8 with BOM so PowerShell 5.1 parses the Chinese comments correctly

## [0.1.1] - 2026-08-15

### Added
- **Rollback-event log**: every successful undo / redo / restore appends a JSON record (timestamp, mode, target snapshot, files rolled back); last 100 kept
- **`undo_recent` tool**: check the most recent rollback operations from any session — rollbacks may have happened elsewhere, answering "why did my config suddenly change?"
- **Prompt rule 7**: on config-state confusion, the AI first calls `undo_recent` to check whether a recent rollback explains it

## [0.1.0] - 2026-08-14

### Added
- **Auto + manual snapshots in separate stores** (`manual` / `auto`): auto-save on every config change (1.5 s debounce), baseline on boot; manual snapshots are never auto-pruned
- **Undo / redo / restore-to-any-version**: pre-restore redo points; redo blocked when real newer changes exist
- **Snapshot manager panel**: per-row diff preview, restore confirmation with change summary, delete, clean-up, export / import (ZIP backup & migration)
- **WebUI Undo/Redo/Snapshots buttons + global shortcuts** (Ctrl+Alt+Z / Ctrl+Alt+Y, customizable)
- **Crash self-check**: warns when the previous DSH run did not finish, with one-click rollback
- **Proactive notice**: after a config change the AI mentions "auto-saved, you can undo anytime"
- **Offline CLI + GUI v2**: fully usable even when DSH fails to boot (snapshot/undo/restore/diff/clean-up/export/import/settings/tray)
- **Bilingual GUI** (system-language auto-detect, `DSH_UNDO_LANG` override)
- **Ecosystem install**: `dsh plugin add github:lire1131/dsh-undo-plugin#master` (dsh.bundle manifest)
- Settings: auto-save toggle, debounce, keep counts, auto-cleanup, snapshot dirs (native folder picker)

### Changed
- Plugin renamed from `dsh-undo` to **`dsh-undo-savepoint`**
- Dependency resolution no longer hardcodes author paths (resolves from the plugin location, falls back to `$DSH_ROOT`)
- Defaults based on the user home; legacy flat stores auto-migrate to the split layout

### Fixed
- Hardcoded author paths broke startup on other machines (issue #1)
- Undo/redo blocked by the watcher's own auto-snapshot (content-hash echo detection)
- Prune never ran — auto snapshots piled up; retention limits now actually apply
- Double-load bug (community report): no manual mount added for bundle installs, leftovers cleaned
- README install command pointed at a wrong repo name

## [0.0.1] - 2026-08-14

Initial local prototype: snapshot on change + undo/redo, later folded into 0.1.0.
