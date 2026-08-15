# Changelog

All notable changes to dsh-undo-savepoint. Dates are in local time (UTC+8).

## [0.1.0] - 2026-08-14

### Added
- Auto-snapshot on every config change (debounced 1.5 s), baseline on every boot
- Manual snapshots (never auto-pruned) and auto snapshots (keep latest N, default 20) in **separate stores** (`manual` / `auto`)
- Undo / redo stack with "pre-restore" redo points; redo blocked when real newer changes exist
- Restore to any snapshot version (snapshot manager panel / chat tools / CLI / GUI)
- Snapshot manager panel: per-row **diff preview** (added/removed lines), restore confirmation with change summary, delete, clean-up, refresh
- WebUI header buttons (Undo / Redo / Snapshots) + global keyboard shortcuts (**Ctrl+Alt+Z** / **Ctrl+Alt+Y**, customizable in Settings)
- Snapshot settings (Settings → General): auto-save toggle, debounce ms, keep counts, auto-cleanup toggle, manual/auto directories with native folder picker
- Auto-cleanup: auto/baseline beyond keepAuto, pre-restore beyond keepPre (consumed first); manual snapshots never deleted
- Crash self-check: detects a previous DSH run that crashed before finishing, warns in the snapshot list/panel and offers rollback
- Proactive notice: after a config change the AI mentions "auto-saved, you can undo anytime"
- **Rollback log** (`<settings dir>/rollback-log.jsonl`, last 100 entries) + `undo_recent` tool: lets any session/AI see which files were rolled back and when
- Export / import: one-click ZIP export of all snapshots (backup / migration); import restores by kind and skips duplicates (panel buttons, chat tools `undo_export`/`undo_import`, offline CLI `export`/`import`)
- Offline CLI (`dsh-undo-savepoint.ps1`): snapshot/list/diff/restore/undo/redo/remove/prune/export/import/status
- Offline GUI v2 (desktop shortcut): crash banner with one-click rollback, export/import, double-click diff preview, clean-up, settings panel, system tray
- GitHub Actions CI (Node 20/22), MIT license, bilingual README with 7 screenshots

### Changed
- Plugin renamed from `dsh-undo` to **`dsh-undo-savepoint`** (repo stays `lire1131/dsh-undo-plugin`)
- Dependency resolution no longer hardcodes author paths: resolves `@deepseek-ai/dsh-tools` from the plugin location, falls back to `$DSH_ROOT`, clear error otherwise
- Default stores/settings based on the user home (`~/.dsh/undo-snapshots`, `~/.dsh/undo/settings.json`); existing `settings.json` values take precedence
- Auto snapshot reasons are classified (`plugin-change` / `patch-change` / `settings-change` / `config-change`)

### Fixed
- Hardcoded author paths broke startup on other machines (issue #1)
- Undo/redo: the watcher auto-snapshot of a restore's own writes blocked redo (content-hash echo detection)
- Undo with identical snapshots now says "nothing to undo" instead of pretending
- Prune never ran (store-directory comparison bug) — auto snapshots piled up; now the retention limits actually apply
- Double-load bug (community report): `ensureMount` no longer adds a manual patch mount for bundle-installed plugins, and removes leftover duplicates
- Diff preview was covered by other layers — now a topmost floating overlay
- Settings row showed `[object Object]` for the auto-save checkbox label; GUI status bar showed a literal `@(...)` count
- Launcher bat: paren-in-if-block parse error caused instant window exit
- Install command in READMEs pointed at a wrong repo name (regression from the rename sweep)

## [0.0.1] - 2026-08-14

Initial local prototype: snapshot on change + undo/redo, later folded into 0.1.0.
