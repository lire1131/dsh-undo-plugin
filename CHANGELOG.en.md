# Changelog

Notable changes to dsh-undo-savepoint. Dates are in local time (UTC+8). 中文版:[CHANGELOG.md](CHANGELOG.md)

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
