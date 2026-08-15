# Cross-Machine Migration Guide

> Scenario: export a snapshot ZIP on machine A → copy it to machine B → import and roll back there.
> 中文版：[migration.md](migration.md)

---

## 1. What happens

### 1.1 Config files: restored normally
The 6 config files captured in a snapshot (`cordis.patch.yml`, `package.json`, `settings.yaml`, etc.) are written back to B's matching locations.

### 1.2 Plugin code files: **never** dumped into B (since v0.2)
Snapshots include plugin code trees (blob references), but restore has a hard guard (the `liveDirs` check):

- Plugin not installed on B → the whole plugin entry is skipped, **zero bytes written**, the report lists "directory no longer present";
- Plugin installed on B with the same path → its code is overwritten with the snapshot version (restore = make B look like A at snapshot time — be aware).

### 1.3 Blob leftovers: disk space only, no file writes
Export/import carry A's plugin blobs along (by design, so restores keep working). After import they only occupy disk space; nothing is written back automatically.

### 1.4 The real pitfall: the patch references plugins B does not have → startup error
The snapshot's `cordis.patch.yml` is restored verbatim. If it mounts a plugin from A that B has not installed, the DSH loader fails at startup (MODULE_NOT_FOUND).

**Restoring cross-machine means "make B's config look like A's" — B must have all of A's plugins installed to boot.** This is not new to the plugin-code-tree feature; config restore always behaved this way.

---

## 2. Cross-machine preflight (automatic since v0.4)

Restore scans the target snapshot's plugin references (patch mount entries + `package.json` bundles) and probes whether this machine can resolve them. Missing plugins are reported clearly:

```
⚠️ Cross-machine preflight: referenced but NOT resolvable on this machine: dsh-xxx
DSH may fail to start after restore — install them first, or use undo_safe_mode action "on" ...
```

- Local file entries (`name: './xxx'`) are not probed;
- Multi-anchor probing (user `node_modules` / profile dependency tree / plugin location chain) — resolvable from any anchor counts as installed, avoiding false positives;
- Preflight currently reports only and never blocks (phase 1); auto-restore that skips missing mounts is planned.

## 3. Best practice

| Step | Action |
|---|---|
| 1 | Export the snapshot ZIP on A |
| 2 | **Install A's plugins on B first** (`dsh plugin --profile web add <plugin>`), then import the ZIP |
| 3 | Restore on B and read the preflight notice |
| 4 | Still won't boot? **SAFE MODE** fallback: `undo_safe_mode on` → DSH always boots → then decide to install plugins or roll back further |
