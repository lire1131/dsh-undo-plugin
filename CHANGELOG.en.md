# Changelog

Notable changes to dsh-undo-savepoint. Dates are in local time (UTC+8). 中文版:[CHANGELOG.md](CHANGELOG.md)

## [0.3.3.1] - 2026-08-16

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
