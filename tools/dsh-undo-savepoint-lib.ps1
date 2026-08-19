# dsh-undo-savepoint-lib.ps1 - shared logic for the dsh-undo-savepoint external tooling.
# Dot-source this from dsh-undo-savepoint.ps1 (CLI) and dsh-undo-savepoint-gui.ps1 (window).
# Works WITHOUT DSH running: reads/writes the same snapshot stores and the
# same manifest format as the dsh-undo-savepoint DSH plugin.
#
# Store layout (mirrors lib/index.js): defaults are based on DSH_HOME
# (issue #6: DSH_HOME env var, fallback ~/.dsh — same as the official launcher).
# Values stored in the settings file take precedence via Get-UndoSettings.
# The same environment overrides as the Node plugin are honored
# (DSH_UNDO_ROOT / DSH_UNDO_SETTINGS).

$script:DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$script:UndoSnapshotRoot = if ($env:DSH_UNDO_ROOT) { $env:DSH_UNDO_ROOT } else { Join-Path $script:DshHome 'undo-snapshots' }
$script:UndoLegacyRoot = $script:UndoSnapshotRoot
$script:UndoManualDir = Join-Path $script:UndoSnapshotRoot 'manual'
$script:UndoAutoDir = Join-Path $script:UndoSnapshotRoot 'auto'
$script:UndoHome = if ($env:DSH_UNDO_SETTINGS) { Split-Path $env:DSH_UNDO_SETTINGS -Parent } else { Join-Path $script:DshHome 'undo' }
$script:UndoSettingsFile = if ($env:DSH_UNDO_SETTINGS) { $env:DSH_UNDO_SETTINGS } else { Join-Path $script:UndoHome 'settings.json' }
$script:UndoHomeRoot = $script:DshHome
# v0.3.3 (issue #3): multi-profile support. The offline tools cannot see the
# CLI argv, so the profile name comes from $env:DSH_UNDO_PROFILE or the
# settings file (profileName), defaulting to 'web'.
$script:UndoProfileName = if ($env:DSH_UNDO_PROFILE) { $env:DSH_UNDO_PROFILE } else { 'web' }
$script:UndoProfileRoot = Join-Path $script:UndoHomeRoot "profiles\$script:UndoProfileName"

# Store defaults per profile with legacy fallback (mirrors resolveStoreRoots
# in lib/index.js): use <root>/<profile>/{auto,manual} when it exists or when
# no flat store exists; otherwise keep the flat store (don't hide old data).
function Get-UndoStoreDefaults {
    $scoped = Join-Path $script:UndoSnapshotRoot $script:UndoProfileName
    $hasScoped = (Test-Path -LiteralPath (Join-Path $scoped 'auto')) -or (Test-Path -LiteralPath (Join-Path $scoped 'manual'))
    $hasFlat = (Test-Path -LiteralPath (Join-Path $script:UndoSnapshotRoot 'auto')) -or (Test-Path -LiteralPath (Join-Path $script:UndoSnapshotRoot 'manual'))
    if ($hasScoped -or -not $hasFlat) {
        return @{ manualDir = (Join-Path $scoped 'manual'); autoDir = (Join-Path $scoped 'auto') }
    }
    return @{ manualDir = (Join-Path $script:UndoSnapshotRoot 'manual'); autoDir = (Join-Path $script:UndoSnapshotRoot 'auto') }
}

# Must mirror FILE_SPECS in the dsh-undo-savepoint plugin (lib/index.js).
# v0.2: the real source of truth is lib/spec.json (module 7) — this built-in
# list is only a fallback when spec.json is missing/unreadable.
$script:UndoFileSpecs = @(
    @{ RootKey = 'profile'; Root = $script:UndoProfileRoot; Name = 'cordis.patch.yml' },
    @{ RootKey = 'profile'; Root = $script:UndoProfileRoot; Name = 'package.json' },
    @{ RootKey = 'profile'; Root = $script:UndoProfileRoot; Name = 'cordis.yml' },
    @{ RootKey = 'profile'; Root = $script:UndoProfileRoot; Name = 'pnpm-workspace.yaml' },
    @{ RootKey = 'home';    Root = $script:UndoHomeRoot;    Name = 'settings.yaml' },
    @{ RootKey = 'home';    Root = $script:UndoHomeRoot;    Name = '.env' },
    @{ RootKey = 'home';    Root = $script:UndoHomeRoot;    Name = '.credentials.yaml' }
)

# ── sensitive-file handling (v0.3.2): redact + local vault ─────────────────
# Sensitive files (.env / .credentials.yaml) go into snapshots REDACTED; the
# real values live in the local vault (<autoDir>/env-vault/<sha1>.env) so
# local rollbacks restore fully while exported snapshots carry no secrets.
$script:UndoSensitiveDests = @('home-.env', 'profile-.env', 'home-.credentials.yaml')
$script:UndoRedactPlaceholder = '***REDACTED***'

# ── plugin code tree rules (v0.2, module 1) ────────────────────────────────
# Defaults mirror lib/spec.json; Initialize-UndoSpec overrides them when the
# file is readable. Only "code/config" files enter snapshots — assets (gif/png
# etc.) are excluded so snapshots stay tiny (dsh-pet 57MB -> ~47KB of code).
$script:UndoCodeExts = @('.js', '.mjs', '.cjs', '.ts', '.mts', '.cts', '.json', '.yml', '.yaml')
$script:UndoExcludeDirs = @('node_modules', '.git', 'dist', 'build', 'cache', '.cache', 'coverage', '.turbo')
$script:UndoExcludeNames = @('package-lock.json', 'pnpm-lock.yaml', 'yarn.lock', '.DS_Store')
$script:UndoMaxFileBytes = 262144
$script:UndoMaxSnapBytes = 10485760

# Read lib/spec.json (single source of truth shared with the Node plugin).
function Initialize-UndoSpec {
    $specPath = Join-Path $PSScriptRoot '..\lib\spec.json'
    if (-not (Test-Path -LiteralPath $specPath)) { return }
    try {
        $spec = Get-Content -LiteralPath $specPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($spec.configFiles) {
            $list = @()
            foreach ($f in $spec.configFiles) {
                $root = if ($f.root -eq 'profile') { $script:UndoProfileRoot }
                        elseif ($f.root -eq 'home') { $script:UndoHomeRoot } else { $null }
                if ($root) { $list += @{ RootKey = $f.root; Root = $root; Name = $f.rel } }
            }
            if ($list.Count -gt 0) { $script:UndoFileSpecs = $list }
        }
        if ($spec.pluginCodeExts) { $script:UndoCodeExts = @($spec.pluginCodeExts | ForEach-Object { $_.ToLower() }) }
        if ($spec.pluginExcludeDirNames) { $script:UndoExcludeDirs = @($spec.pluginExcludeDirNames) }
        if ($spec.pluginExcludeFileNames) { $script:UndoExcludeNames = @($spec.pluginExcludeFileNames) }
        if ($spec.pluginMaxFileBytes) { $script:UndoMaxFileBytes = [int]$spec.pluginMaxFileBytes }
        if ($spec.pluginMaxSnapshotBytes) { $script:UndoMaxSnapBytes = [int]$spec.pluginMaxSnapshotBytes }
    } catch { }
}
Initialize-UndoSpec

function Get-UndoDestName([hashtable]$Spec) {
    return "$($Spec.RootKey)-$($Spec.Name -replace '[\\/]', '-')"
}

# ── plugin discovery & collection (v0.2, module 1) ─────────────────────────
# Find user plugins: explicit pluginDirs (settings / DSH_PLUGIN_DIRS) first,
# otherwise auto-detect junctions under the user node_modules (the standard
# `mklink /J` install layout). Returns @( @{name;dir;version} ).
function Get-UndoPlugins {
    $settings = Get-UndoSettings
    $out = @()
    $seen = @{}
    $explicit = @()
    if ($settings.pluginDirs) { $explicit += @($settings.pluginDirs) }
    if ($env:DSH_PLUGIN_DIRS) { $explicit += @(($env:DSH_PLUGIN_DIRS -split '[;,]') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    if ($explicit.Count -gt 0) {
        foreach ($d in $explicit) {
            if (-not (Test-Path -LiteralPath $d)) { continue }
            $real = (Get-Item -LiteralPath $d).FullName
            if ($seen.ContainsKey($real)) { continue }
            $seen[$real] = $true
            $ver = ''
            $pkg = Join-Path $real 'package.json'
            if (Test-Path -LiteralPath $pkg) { try { $ver = [string]((Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json).version) } catch { } }
            $out += @{ name = (Split-Path $real -Leaf); dir = $real; version = $ver }
        }
        return @($out)
    }
    $roots = @((Join-Path $script:DshHome 'node_modules'))
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($item in Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue) {
            if ($item.LinkType -ne 'Junction') { continue }
            $target = $item.Target
            if (-not $target -or -not (Test-Path -LiteralPath $target)) { continue }
            if ($seen.ContainsKey($target)) { continue }
            $seen[$target] = $true
            $ver = ''
            $pkg = Join-Path $target 'package.json'
            if (Test-Path -LiteralPath $pkg) { try { $ver = [string]((Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json).version) } catch { } }
            $out += @{ name = $item.Name; dir = $target; version = $ver }
        }
    }
    return @($out)
}

function Test-UndoCodeFile([string]$Name) {
    if ($script:UndoExcludeNames -contains $Name) { return $false }
    $ext = ''
    $idx = $Name.LastIndexOf('.')
    if ($idx -ge 0) { $ext = $Name.Substring($idx).ToLower() }
    return ($script:UndoCodeExts -contains $ext)
}

# Collect code files of one plugin dir (whitelist + size caps).
# Returns @{ files = @( @{rel;abs;hash;size} ); skipped; dirs; truncated }.
function Get-UndoPluginTree([string]$Dir) {
    $files = @(); $skipped = @(); $dirs = @()
    $total = 0; $truncated = $false
    $stack = New-Object System.Collections.Stack
    $stack.Push('')
    while ($stack.Count -gt 0 -and -not $truncated) {
        $rel = $stack.Pop()
        $abs = if ($rel) { Join-Path $Dir $rel } else { $Dir }
        foreach ($e in Get-ChildItem -LiteralPath $abs -Force -ErrorAction SilentlyContinue) {
            $r = if ($rel) { "$rel/$($e.Name)" } else { $e.Name }
            if ($e.PSIsContainer) {
                if ($script:UndoExcludeDirs -contains $e.Name) { continue }
                $dirs += $r
                $stack.Push($r)
            } else {
                if (-not (Test-UndoCodeFile $e.Name)) { continue }
                if ($e.Length -gt $script:UndoMaxFileBytes) { $skipped += @{ path = $r; reason = 'too-large' }; continue }
                if ($total + $e.Length -gt $script:UndoMaxSnapBytes) { $truncated = $true; break }
                $h = (Get-FileHash -LiteralPath $e.FullName -Algorithm SHA1).Hash
                $files += @{ rel = $r; abs = $e.FullName; hash = $h; size = $e.Length }
                $total += $e.Length
            }
        }
    }
    return @{ files = @($files); skipped = @($skipped); dirs = @($dirs); truncated = $truncated }
}

# profile-local code files referenced as `name: './xxx'` in cordis.patch.yml.
function Get-UndoProfileRefs {
    $refs = @()
    $patch = Join-Path $script:UndoProfileRoot 'cordis.patch.yml'
    if (-not (Test-Path -LiteralPath $patch)) { return @($refs) }
    $content = Get-Content -LiteralPath $patch -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($content, "name:\s*['""]?\./([^'""\s]+)['""]?")) {
        $rel = $m.Groups[1].Value
        if ($rel -match '\.\.' -or $rel -match '^[/\\]' -or $rel -match '^[A-Za-z]:') { continue }
        $abs = Join-Path $script:UndoProfileRoot $rel
        if (-not (Test-Path -LiteralPath $abs)) { continue }
        $item = Get-Item -LiteralPath $abs
        if ($item.PSIsContainer -or $item.Length -gt $script:UndoMaxFileBytes) { continue }
        $h = (Get-FileHash -LiteralPath $abs -Algorithm SHA1).Hash
        $refs += @{ path = $rel; hash = $h; size = $item.Length }
    }
    return @($refs)
}

# Shared blob store: <snapshotRoot>/blobs/<sha1> (content-addressed dedup).
function Get-UndoBlobDir {
    $settings = Get-UndoSettings
    return (Join-Path (Split-Path $settings.autoDir -Parent) 'blobs')
}
function Add-UndoBlob([string]$Hash, [string]$SrcPath) {
    $dir = Get-UndoBlobDir
    $dest = Join-Path $dir $Hash
    if (Test-Path -LiteralPath $dest) { return }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -LiteralPath $SrcPath -Destination $dest -Force
}
function Read-UndoBlob([string]$Hash) {
    $p = Join-Path (Get-UndoBlobDir) $Hash
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

# ── sensitive-file redaction + vault (v0.3.2) ──────────────────────────────
function Test-UndoSensitiveName([string]$DestName) {
    return ($script:UndoSensitiveDests -contains $DestName)
}
function Test-UndoRedacting {
    $settings = Get-UndoSettings
    return ($settings.sensitiveMode -ne 'keep')
}
# .env line-level redaction: keep key / export / quotes / comments, replace value.
function Get-UndoRedactedEnv([string]$Text) {
    $out = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^(\s*(?:export\s+)?[A-Za-z_][A-Za-z0-9_.]*)(\s*=\s*)(.*)$') {
            $val = $matches[3]
            $quote = ''
            if ($val.StartsWith('"')) { $quote = '"' } elseif ($val.StartsWith("'")) { $quote = "'" }
            $out += "$($matches[1])$($matches[2])$quote$($script:UndoRedactPlaceholder)$quote"
        } else {
            $out += $line
        }
    }
    return ($out -join "`n")
}
# YAML key-value redaction (.credentials.yaml): keep indent/key, replace value.
function Get-UndoRedactedYaml([string]$Text) {
    $out = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^(\s*[A-Za-z_][A-Za-z0-9_.-]*\s*:\s*)(.*)$') {
            $val = $matches[2].Trim()
            if ($val -ne '' -and -not $val.StartsWith('#')) {
                $out += "$($matches[1])$($script:UndoRedactPlaceholder)"
                continue
            }
        }
        $out += $line
    }
    return ($out -join "`n")
}
# Pick the redaction by destination name; idempotent on already-redacted text.
function Get-UndoRedactedForDest([string]$DestName, [string]$Text) {
    if ($DestName -eq 'home-.credentials.yaml') { return (Get-UndoRedactedYaml $Text) }
    return (Get-UndoRedactedEnv $Text)
}
function Get-UndoVaultDir {
    $settings = Get-UndoSettings
    return (Join-Path $settings.autoDir 'env-vault')
}
function Add-UndoVault([string]$Hash, [string]$SrcPath) {
    $dir = Get-UndoVaultDir
    $dest = Join-Path $dir "$Hash.env"
    if (Test-Path -LiteralPath $dest) { return }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -LiteralPath $SrcPath -Destination $dest -Force
}
function Read-UndoVault([string]$Hash) {
    $p = Join-Path (Get-UndoVaultDir) "$Hash.env"
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

# ── SAFE MODE (v0.3, module 4): disable all user plugins except undo ──────
# State file: <autoDir>/safe-mode.json. Entering backs up cordis.patch.yml and
# writes a minimal patch; exiting restores the backup. Works OFFLINE (when DSH
# cannot boot at all: dsh-undo.ps1 safe-mode -Label on still works).
function Get-UndoSafeModeState {
    $settings = Get-UndoSettings
    $stateFile = Join-Path $settings.autoDir 'safe-mode.json'
    $st = @{ active = $false }
    if (Test-Path -LiteralPath $stateFile) {
        try { $st = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    return $st
}

function Set-UndoSafeMode([bool]$On) {
    $settings = Get-UndoSettings
    $patch = Join-Path $script:UndoProfileRoot 'cordis.patch.yml'
    $stateFile = Join-Path $settings.autoDir 'safe-mode.json'
    $st = Get-UndoSafeModeState
    if ($On) {
        if ($st.active) { return @{ ok = $true; active = $true; message = "Safe mode is already ON (entered $($st.enteredAt))." } }
        $snap = New-UndoSnapshot 'manual' 'safe-mode-before'
        $backup = Join-Path $settings.autoDir "safe-mode-backup-$($snap.id).yml"
        if (Test-Path -LiteralPath $patch) { Copy-Item -LiteralPath $patch -Destination $backup -Force }
        $minimal = "# dsh-undo-savepoint SAFE MODE (entered $(Get-Date -Format o))`n# All user plugins except dsh-undo-savepoint are temporarily disabled.`n- insert:`n    - id: dsh-undo-savepoint`n      name: dsh-undo-savepoint`n"
        [System.IO.File]::WriteAllText($patch, $minimal, (New-Object System.Text.UTF8Encoding($false)))
        New-Item -ItemType Directory -Force -Path $settings.autoDir | Out-Null
        $stJson = @{ active = $true; enteredAt = (Get-Date).ToUniversalTime().ToString('o'); backup = $backup; snapshotId = $snap.id } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($stateFile, $stJson, (New-Object System.Text.UTF8Encoding($false)))
        return @{ ok = $true; active = $true; snapshotId = $snap.id; message = "Safe mode ON (pre-snapshot $($snap.id)). Restart DSH to boot with only dsh-undo-savepoint." }
    }
    if (-not $st.active) { return @{ ok = $true; active = $false; message = 'Safe mode is not active.' } }
    if (-not $st.backup -or -not (Test-Path -LiteralPath $st.backup)) {
        return @{ ok = $false; error = 'Safe-mode backup missing. Restore a snapshot from before the crash first (dsh-undo.ps1 list / restore).' }
    }
    Copy-Item -LiteralPath $st.backup -Destination $patch -Force
    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    return @{ ok = $true; active = $false; message = 'Safe mode OFF. Restart DSH to load all plugins again.' }
}

function Get-UndoSpecByName([string]$DestName) {
    foreach ($f in $script:UndoFileSpecs) { if ((Get-UndoDestName $f) -eq $DestName) { return $f } }
    return $null
}

function Get-UndoFileSpecByBase([string]$BaseName) {
    foreach ($f in $script:UndoFileSpecs) { if ([System.IO.Path]::GetFileName($f.Name) -eq $BaseName) { return $f } }
    return $null
}

function Get-UndoSettings {
    $storeDefaults = Get-UndoStoreDefaults
    $defaults = @{
        autoEnabled = $true
        watchDebounceMs = 1500
        keepAuto = 20
        keepPre = 10
        autoCleanup = $true
        manualDir = $storeDefaults.manualDir
        autoDir = $storeDefaults.autoDir
        pluginDirs = @()
        sensitiveMode = 'redact'
        profileName = $script:UndoProfileName
    }
    if (Test-Path -LiteralPath $script:UndoSettingsFile) {
        try {
            $j = Get-Content -LiteralPath $script:UndoSettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.manualDir) { $defaults.manualDir = $j.manualDir }
            if ($j.autoDir) { $defaults.autoDir = $j.autoDir }
            if ($j.autoEnabled -is [bool]) { $defaults.autoEnabled = $j.autoEnabled }
            if ($j.watchDebounceMs) { $defaults.watchDebounceMs = [int]$j.watchDebounceMs }
            if ($j.keepAuto) { $defaults.keepAuto = [int]$j.keepAuto }
            # v0.3.2: keepPre / autoCleanup MUST be read back too, otherwise the
            # GUI opens them empty and overwrites WebUI-set values on save
            if ($null -ne $j.keepPre) { $defaults.keepPre = [int]$j.keepPre }
            if ($null -ne $j.autoCleanup) { $defaults.autoCleanup = [bool]$j.autoCleanup }
            if ($j.pluginDirs) { $defaults.pluginDirs = @($j.pluginDirs) }
            if ($j.sensitiveMode) { $defaults.sensitiveMode = $j.sensitiveMode }
            # v0.3.3 (issue #3): settings.profileName overrides the default;
            # then recompute store defaults UNLESS explicit dirs are present
            if ($j.profileName) {
                $defaults.profileName = $j.profileName
                $script:UndoProfileName = $j.profileName
                $script:UndoProfileRoot = Join-Path $script:UndoHomeRoot "profiles\$($script:UndoProfileName)"
                if (-not $j.manualDir -or -not $j.autoDir) {
                    $storeDefaults = Get-UndoStoreDefaults
                    if (-not $j.manualDir) { $defaults.manualDir = $storeDefaults.manualDir }
                    if (-not $j.autoDir) { $defaults.autoDir = $storeDefaults.autoDir }
                }
            }
        } catch { }
    }
    return $defaults
}

function Get-UndoStores {
    $settings = Get-UndoSettings
    return @($settings.manualDir, $settings.autoDir, $script:UndoLegacyRoot)
}

function Get-UndoStoreLabel([string]$Base) {
    $settings = Get-UndoSettings
    if ($Base -eq $settings.manualDir) { return 'manual' }
    if ($Base -eq $settings.autoDir) { return 'auto' }
    return 'legacy'
}

function Get-UndoSnapshots {
    $out = @()
    foreach ($base in (Get-UndoStores)) {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($d in Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue) {
            $m = Join-Path $d.FullName 'manifest.json'
            if (-not (Test-Path -LiteralPath $m)) { continue }
            try {
                $s = Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json
                $s | Add-Member -NotePropertyName _Dir -NotePropertyValue $d.FullName -Force
                $s | Add-Member -NotePropertyName _Store -NotePropertyValue (Get-UndoStoreLabel $base) -Force
                $out += $s
            } catch { }
        }
    }
    return @($out | Sort-Object -Property time -Descending)
}

function Get-UndoSnapshotById([string]$Id) {
    foreach ($s in (Get-UndoSnapshots)) { if ($s.id -eq $Id) { return $s } }
    return $null
}

function New-UndoSnapshot([string]$Kind, [string]$Reason) {
    $settings = Get-UndoSettings
    $base = if ($Kind -eq 'manual') { $settings.manualDir } else { $settings.autoDir }
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    $id = '{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), ([System.Guid]::NewGuid().ToString('N').Substring(0, 4))
    $dir = Join-Path $base $id
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $fileList = @()
    $envVaultRefs = @{}
    $redacted = @()
    foreach ($f in $script:UndoFileSpecs) {
        $src = Join-Path $f.Root $f.Name
        if (Test-Path -LiteralPath $src) {
            $destName = Get-UndoDestName $f
            $dest = Join-Path $dir $destName
            # sensitive files (v0.3.2): redacted copy into the snapshot, real value into the vault
            if ((Test-UndoSensitiveName $destName) -and (Test-UndoRedacting)) {
                $text = [System.IO.File]::ReadAllText($src)
                $redactedText = if ($destName -eq 'home-.credentials.yaml') { Get-UndoRedactedYaml $text } else { Get-UndoRedactedEnv $text }
                [System.IO.File]::WriteAllText($dest, $redactedText, (New-Object System.Text.UTF8Encoding($false)))
                $h = (Get-FileHash -LiteralPath $src -Algorithm SHA1).Hash
                Add-UndoVault $h $src
                $envVaultRefs[$destName] = $h
                $redacted += $destName
                $fileList += @{ name = $destName; size = (Get-Item -LiteralPath $dest).Length }
                continue
            }
            Copy-Item -LiteralPath $src -Destination $dest -Force
            $fileList += @{ name = $destName; size = (Get-Item -LiteralPath $dest).Length }
        }
    }
    # v0.2: plugin code trees -> content-addressed blobs, manifest keeps refs
    $pluginEntries = @()
    foreach ($p in (Get-UndoPlugins)) {
        $tree = Get-UndoPluginTree $p.dir
        $refs = @()
        foreach ($f in $tree.files) {
            Add-UndoBlob $f.hash $f.abs
            $refs += @{ path = $f.rel; hash = $f.hash; size = $f.size }
        }
        $pluginEntries += @{ name = $p.name; dir = $p.dir; version = $p.version; files = @($refs); skipped = @($tree.skipped); truncated = $tree.truncated }
    }
    # profile-local code files (name: './xxx' in cordis.patch.yml)
    $profileRefs = @()
    foreach ($f in (Get-UndoProfileRefs)) {
        Add-UndoBlob $f.hash (Join-Path $script:UndoProfileRoot $f.path)
        $profileRefs += @{ path = $f.path; hash = $f.hash; size = $f.size }
    }
    $manifest = @{ id = $id; time = (Get-Date).ToUniversalTime().ToString('o'); kind = $Kind; reason = $Reason; files = $fileList; plugins = @($pluginEntries); profileFiles = @($profileRefs); sensitiveMode = $settings.sensitiveMode; redacted = @($redacted); envVaultRefs = $envVaultRefs }
    $json = $manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    return $manifest
}

function Get-UndoState([object]$Snap) {
    $pairs = @()
    foreach ($file in @($Snap.files)) {
        # sensitive files (v0.3.2): state = real-value sha1 from envVaultRefs,
        # matching Get-UndoCurrentState which hashes the live real file
        $vaultRef = $null
        if ($null -ne $Snap.envVaultRefs) {
            try { $vaultRef = $Snap.envVaultRefs.PSObject.Properties[$file.name].Value } catch { }
        }
        if ((Test-UndoSensitiveName $file.name) -and $vaultRef) {
            $pairs += , @($file.name, [string]$vaultRef)
            continue
        }
        $p = Join-Path $Snap._Dir $file.name
        if (Test-Path -LiteralPath $p) {
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA1).Hash
            $pairs += , @($file.name, $h)
        }
    }
    # v0.2: plugin code trees + profile-local code (hashes come from manifest refs)
    # NOTE: @($null) is a 1-element array in PowerShell — always filter empties
    # so OLD snapshots without plugins/profileFiles stay clean.
    foreach ($p in @($Snap.plugins | Where-Object { $_ })) {
        foreach ($f in @($p.files | Where-Object { $_ })) { $pairs += , @("plugin:$($p.name)/$($f.path)", $f.hash) }
    }
    foreach ($f in @($Snap.profileFiles | Where-Object { $_ -and $_.hash })) {
        $pairs += , @("profile:$($f.path)", $f.hash)
    }
    return @($pairs | Sort-Object { $_[0] })
}

function Get-UndoCurrentState {
    $pairs = @()
    foreach ($f in $script:UndoFileSpecs) {
        $p = Join-Path $f.Root $f.Name
        if (Test-Path -LiteralPath $p) {
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA1).Hash
            $pairs += , @((Get-UndoDestName $f), $h)
        }
    }
    # v0.2: plugin code changed without any config change must be undoable too
    foreach ($p in (Get-UndoPlugins)) {
        $tree = Get-UndoPluginTree $p.dir
        foreach ($f in $tree.files) { $pairs += , @("plugin:$($p.name)/$($f.rel)", $f.hash) }
    }
    foreach ($f in (Get-UndoProfileRefs)) { $pairs += , @("profile:$($f.path)", $f.hash) }
    return @($pairs | Sort-Object { $_[0] })
}

function Test-UndoSameState($A, $B) {
    if (@($A).Count -ne @($B).Count) { return $false }
    for ($i = 0; $i -lt @($A).Count; $i++) {
        if ($A[$i][0] -ne $B[$i][0] -or $A[$i][1] -ne $B[$i][1]) { return $false }
    }
    return $true
}

function Get-UndoCandidates {
    $list = Get-UndoSnapshots
    $unconsumedPre = @($list | Where-Object { $_.kind -eq 'pre-restore' -and -not $_.consumed })
    $preStates = @()
    foreach ($p in $unconsumedPre) { $preStates += , (Get-UndoState $p) }
    $candidates = @()
    foreach ($s in $list) {
        if ($s.kind -eq 'pre-restore') { continue }
        $st = Get-UndoState $s
        $matched = $false
        foreach ($ps in $preStates) { if (Test-UndoSameState $st $ps) { $matched = $true; break } }
        if ($matched) { continue }
        $candidates += , @{ s = $s; st = $st }
    }
    return $candidates
}

function Set-UndoFlag([object]$Snap, [string]$Flag, [bool]$Value) {
    $m = Join-Path $Snap._Dir 'manifest.json'
    if (-not (Test-Path -LiteralPath $m)) { return }
    $Snap | Add-Member -NotePropertyName $Flag -NotePropertyValue $Value -Force
    [System.IO.File]::WriteAllText($m, ($Snap | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-UndoApply([object]$Snap) {
    $restored = @()
    $missing = @()
    $notes = @()
    foreach ($file in @($Snap.files)) {
        $spec = Get-UndoSpecByName $file.name
        if ($null -eq $spec) { continue }
        $src = Join-Path $Snap._Dir $file.name
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $spec.Root $spec.Name
        # sensitive files (v0.3.2): vault has the real value -> full restore;
        # vault missing (other machine / cleaned) -> redacted placeholder + note
        $sensitiveNote = $null
        if (Test-UndoSensitiveName $file.name) {
            $vaultRef = $null
            if ($null -ne $Snap.envVaultRefs) {
                try { $vaultRef = $Snap.envVaultRefs.PSObject.Properties[$file.name].Value } catch { }
            }
            if ($vaultRef) {
                $real = Read-UndoVault $vaultRef
                if ($real) { Copy-Item -LiteralPath $real -Destination $dst -Force; $restored += $file.name; continue }
                $sensitiveNote = "$file.name : vault missing - redacted placeholder restored, please fill in the real values"
            } elseif ($Snap.sensitiveMode -eq 'redact') {
                $sensitiveNote = "$file.name : restored as redacted placeholder (values were stripped from this snapshot)"
            }
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $restored += $file.name
        if ($sensitiveNote) { $notes += $sensitiveNote }
    }
    # v0.2: plugin code trees — restore from blobs, only into dirs that are
    # still live plugins today (safety: never write to arbitrary paths).
    $live = @{}
    foreach ($p in (Get-UndoPlugins)) { $live[$p.dir] = $true }
    foreach ($p in @($Snap.plugins | Where-Object { $_ })) {
        if (-not $live.ContainsKey($p.dir)) {
            $missing += "plugin $($p.name): directory no longer present ($($p.dir))"
            continue
        }
        foreach ($f in @($p.files | Where-Object { $_ })) {
            if ($f.path -match '\.\.' -or $f.path -match '^[/\\]' -or $f.path -match '^[A-Za-z]:') {
                $missing += "$($p.name)/$($f.path): unsafe path, skipped"
                continue
            }
            $blob = Read-UndoBlob $f.hash
            if (-not $blob) { $missing += "$($p.name)/$($f.path): snapshot blob missing"; continue }
            $dst = Join-Path $p.dir $f.path
            $dstDir = Split-Path $dst -Parent
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
            Copy-Item -LiteralPath $blob -Destination $dst -Force
            $restored += "plugin:$($p.name)/$($f.path)"
        }
    }
    # profile-local code files
    foreach ($f in @($Snap.profileFiles | Where-Object { $_ })) {
        if (-not $f.hash -or $f.path -match '\.\.' -or $f.path -match '^[/\\]' -or $f.path -match '^[A-Za-z]:') { continue }
        $blob = Read-UndoBlob $f.hash
        if (-not $blob) { $missing += "profile:$($f.path): snapshot blob missing"; continue }
        $dst = Join-Path $script:UndoProfileRoot $f.path
        Copy-Item -LiteralPath $blob -Destination $dst -Force
        $restored += "profile:$($f.path)"
    }
    return @{ restored = @($restored); missing = @($missing); notes = @($notes) }
}

function Ensure-UndoMount {
    $patch = Join-Path $script:UndoProfileRoot 'cordis.patch.yml'
    if (-not (Test-Path -LiteralPath $patch)) { return $false }
    $content = [System.IO.File]::ReadAllText($patch)

    # BUNDLE mode (installed via `dsh plugin add`): never add a manual mount
    # (double-load bug); remove any leftover manual mount block instead.
    $pkgPath = Join-Path $script:UndoProfileRoot 'package.json'
    $bundleMode = $false
    if (Test-Path -LiteralPath $pkgPath) {
        try {
            $pkg = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $bundles = $pkg.dsh.profile.bundles
            $bundleMode = ($bundles -is [array] -and $bundles -contains 'dsh-undo-savepoint')
        } catch { }
    }
    if ($bundleMode) {
        $pattern = '(?m)^# dsh-undo-savepoint mount[^\r\n]*\r?\n- insert:\r?\n\s+- id: dsh-undo-savepoint\r?\n\s+- name: ''?dsh-undo-savepoint''?\r?\n?'
        $cleaned = $content -replace $pattern, ''
        if ($cleaned -ne $content) {
            [System.IO.File]::WriteAllText($patch, $cleaned, (New-Object System.Text.UTF8Encoding($false)))
            return $true
        }
        return $false
    }

    # PATCH mode (local junction mount): ensure the manual mount line exists.
    if ($content -match 'dsh-undo-savepoint') { return $false }
    $content = $content -replace '(?m)^\s*\[\]\s*$', ''
    $block = "`n# dsh-undo-savepoint mount (re-ensured by dsh-undo-savepoint)`n- insert:`n    - id: dsh-undo-savepoint`n      name: dsh-undo-savepoint`n"
    [System.IO.File]::WriteAllText($patch, ($content.TrimEnd() + $block), (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Invoke-UndoPrune {
    $settings = Get-UndoSettings
    if ($settings.autoCleanup -eq $false) { return @{ removedAuto = 0; removedPre = 0; disabled = $true } }
    $keepAuto = if ($settings.keepAuto) { [int]$settings.keepAuto } else { 20 }
    $keepPre = if ($null -ne $settings.keepPre) { [int]$settings.keepPre } else { 10 }
    $list = Get-UndoSnapshots
    $removedAuto = 0
    $removedPre = 0
    # auto/baseline beyond keepAuto (only the auto store; manual never touched)
    $auto = @($list | Where-Object { ($_.kind -eq 'auto' -or $_.kind -eq 'baseline') -and $_._Store -eq 'auto' } | Sort-Object -Property time)
    $excessAuto = @($auto | Select-Object -First ([Math]::Max(0, $auto.Count - $keepAuto)))
    foreach ($s in $excessAuto) {
        Remove-Item -LiteralPath $s._Dir -Recurse -Force -ErrorAction SilentlyContinue
        $removedAuto++
    }
    # pre-restore beyond keepPre (consumed ones first, then oldest)
    $pre = @($list | Where-Object { $_.kind -eq 'pre-restore' -and $_._Store -eq 'auto' } |
        Sort-Object @{ Expression = { if ($_.consumed) { 0 } else { 1 } } }, time)
    $excessPre = @($pre | Select-Object -First ([Math]::Max(0, $pre.Count - $keepPre)))
    foreach ($s in $excessPre) {
        Remove-Item -LiteralPath $s._Dir -Recurse -Force -ErrorAction SilentlyContinue
        $removedPre++
    }
    # orphan blobs (v0.3.2): no remaining snapshot references them
    $removedBlobs = 0
    $blobDir = Get-UndoBlobDir
    if (Test-Path -LiteralPath $blobDir) {
        $refs = @{}
        foreach ($s in $list) {
            foreach ($p in @($s.plugins | Where-Object { $_ })) {
                foreach ($f in @($p.files | Where-Object { $_ })) { if ($f.hash) { $refs[$f.hash] = $true } }
            }
            foreach ($f in @($s.profileFiles | Where-Object { $_ -and $_.hash })) { $refs[$f.hash] = $true }
        }
        foreach ($bf in Get-ChildItem -LiteralPath $blobDir -File -Force -ErrorAction SilentlyContinue) {
            if (-not $refs.ContainsKey($bf.Name)) {
                Remove-Item -LiteralPath $bf.FullName -Force -ErrorAction SilentlyContinue
                $removedBlobs++
            }
        }
    }
    return @{ removedAuto = $removedAuto; removedPre = $removedPre; removedBlobs = $removedBlobs }
}

# ── cross-machine preflight (v0.3.1/0.3.2): which referenced plugins resolve ─
function Test-UndoCanResolve([string]$Name) {
    if ([string]::IsNullOrEmpty($Name)) { return $false }
    $anchors = @(
        (Join-Path $script:DshHome 'node_modules'),
        (Join-Path $script:UndoProfileRoot 'node_modules'),
        (Join-Path $script:UndoProfileRoot '..\node_modules'),
        (Join-Path $PSScriptRoot '..\node_modules')
    )
    foreach ($a in $anchors) {
        if (Test-Path -LiteralPath (Join-Path $a $Name)) { return $true }
    }
    return $false
}

function Get-UndoPreflight([object]$Snap) {
    $names = @{}
    $patchFile = @($Snap.files | Where-Object { $_.name -eq 'profile-cordis.patch.yml' } | Select-Object -First 1)
    if ($patchFile.Count -gt 0) {
        $patchPath = Join-Path $Snap._Dir $patchFile[0].name
        if (Test-Path -LiteralPath $patchPath) {
            $content = [System.IO.File]::ReadAllText($patchPath)
            foreach ($m in [regex]::Matches($content, "name:\s*['""]?([^'""\s]+)['""]?")) {
                $n = $m.Groups[1].Value
                if ($n -match '^\.{1,2}[/\\]' -or $n -match '^[/\\]' -or $n -eq 'dsh-undo-savepoint') { continue }
                $names[$n] = $true
            }
        }
    }
    $pkgFile = @($Snap.files | Where-Object { $_.name -eq 'profile-package.json' } | Select-Object -First 1)
    if ($pkgFile.Count -gt 0) {
        $pkgPath = Join-Path $Snap._Dir $pkgFile[0].name
        if (Test-Path -LiteralPath $pkgPath) {
            try {
                $pkg = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($n in @($pkg.dsh.profile.bundles)) {
                    if ($n -and $n -ne 'dsh-undo-savepoint') { $names[$n] = $true }
                }
            } catch { }
        }
    }
    $missing = @()
    foreach ($n in $names.Keys) {
        if (-not (Test-UndoCanResolve $n)) { $missing += $n }
    }
    return @{ missing = @($missing); checked = $names.Count }
}

function Test-UndoNeedsRestart([string[]]$Restored) {
    foreach ($n in @($Restored)) {
        if ($n -eq 'profile-cordis.patch.yml' -or $n -eq 'profile-package.json' -or $n -like 'plugin:*' -or $n -like 'profile:*') { return $true }
    }
    return $false
}

function Invoke-UndoRestore([string]$Mode, [string]$Id) {
    if ($Mode -eq 'undo') {
        $candidates = Get-UndoCandidates
        if (@($candidates).Count -eq 0) { return @{ ok = $false; error = 'nothing to undo' } }
        $cur = Get-UndoCurrentState
        $target = $null
        foreach ($c in $candidates) { if (-not (Test-UndoSameState $cur $c.st)) { $target = $c; break } }
        if ($null -eq $target) {
            return @{ ok = $true; unchanged = $true; message = 'Current config already matches every undoable snapshot - no real change since the last snapshot, so there is nothing to undo.' }
        }
        $pre = New-UndoSnapshot 'pre-restore' "before-restore:$($target.s.id) ($($target.s.kind): $($target.s.reason))"
        $applied = Invoke-UndoApply $target.s
        if ($target -ne $candidates[0]) { Set-UndoFlag $candidates[0].s 'stepped' $true }
        $remounted = Ensure-UndoMount
        $preflight = Get-UndoPreflight $target.s
        $needsRestart = Test-UndoNeedsRestart $applied.restored
        return @{ ok = $true; restored = $applied.restored; missing = $applied.missing; notes = $applied.notes; needsRestart = $needsRestart; preflight = $preflight; targetId = $target.s.id; targetKind = $target.s.kind; targetReason = $target.s.reason; preSnapshotId = $pre.id; remounted = $remounted }
    }
    if ($Mode -eq 'redo') {
        $list = Get-UndoSnapshots
        $pre = $null
        foreach ($s in $list) { if ($s.kind -eq 'pre-restore' -and -not $s.consumed) { $pre = $s; break } }
        if ($null -eq $pre) { return @{ ok = $false; error = 'nothing to redo' } }
        foreach ($s in $list) {
            if ([datetime]$s.time -gt [datetime]$pre.time -and -not ($s.kind -eq 'pre-restore' -and $s.consumed)) {
                return @{ ok = $false; error = 'redo blocked: newer changes exist after the undo' }
            }
        }
        $applied = Invoke-UndoApply $pre
        Set-UndoFlag $pre 'consumed' $true
        $preflight = Get-UndoPreflight $pre
        $needsRestart = Test-UndoNeedsRestart $applied.restored
        return @{ ok = $true; restored = $applied.restored; missing = $applied.missing; notes = $applied.notes; needsRestart = $needsRestart; preflight = $preflight; targetId = $pre.id; remounted = $false }
    }
    # mode 'id'
    $target = Get-UndoSnapshotById $Id
    if ($null -eq $target) { return @{ ok = $false; error = "snapshot not found: $Id" } }
    $pre = New-UndoSnapshot 'pre-restore' "before-restore:$($target.id) ($($target.kind): $($target.reason))"
    $applied = Invoke-UndoApply $target
    $remounted = Ensure-UndoMount
    $preflight = Get-UndoPreflight $target
    $needsRestart = Test-UndoNeedsRestart $applied.restored
    return @{ ok = $true; restored = $applied.restored; missing = $applied.missing; notes = $applied.notes; needsRestart = $needsRestart; preflight = $preflight; targetId = $target.id; targetKind = $target.kind; targetReason = $target.reason; preSnapshotId = $pre.id; remounted = $remounted }
}

function Remove-UndoSnapshot([string]$Id) {
    $snap = Get-UndoSnapshotById $Id
    if ($null -eq $snap) { return @{ ok = $false; error = "snapshot not found: $Id" } }
    Remove-Item -LiteralPath $snap._Dir -Recurse -Force
    return @{ ok = $true; removed = $Id }
}

function Export-UndoSnapshots {
    $settings = Get-UndoSettings
    $exportRoot = Join-Path (Split-Path $settings.autoDir -Parent) 'undo-exports'
    New-Item -ItemType Directory -Force -Path $exportRoot | Out-Null
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tmp = Join-Path $exportRoot "tmp-$ts"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $exportRoot "dsh-undo-export-$ts.zip"
    $count = 0
    try {
        $sensitiveWarning = $false
        foreach ($pair in @(@('manual', $settings.manualDir), @('auto', $settings.autoDir))) {
            $label = $pair[0]
            $base = $pair[1]
            if (-not (Test-Path -LiteralPath $base)) { continue }
            foreach ($d in Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue) {
                if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'manifest.json'))) { continue }
                # v0.3.2: flag archives that hold real secrets (keep mode / legacy plaintext)
                try {
                    $m = Get-Content -LiteralPath (Join-Path $d.FullName 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($m.sensitiveMode -ne 'redact') {
                        foreach ($fl in @($m.files)) {
                            if (Test-UndoSensitiveName $fl.name) { $sensitiveWarning = $true; break }
                        }
                    }
                } catch { }
                $dest = Join-Path $tmp $label
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
                Copy-Item -LiteralPath $d.FullName -Destination $dest -Recurse -Force
                $count++
            }
        }
        # v0.2: pack the plugin-code blob store too, or restore breaks after import
        $blobDir = Get-UndoBlobDir
        if (Test-Path -LiteralPath $blobDir) {
            New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'blobs') | Out-Null
            foreach ($bf in Get-ChildItem -LiteralPath $blobDir -File -Force -ErrorAction SilentlyContinue) {
                Copy-Item -LiteralPath $bf.FullName -Destination (Join-Path $tmp 'blobs') -Force
            }
        }
        Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -Force
        return @{ ok = $true; path = $zip; count = $count; sensitiveWarning = $sensitiveWarning }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Import-UndoSnapshots([string]$ZipPath) {
    $settings = Get-UndoSettings
    if (-not (Test-Path -LiteralPath $ZipPath)) { return @{ ok = $false; error = "file not found: $ZipPath" } }
    $exportRoot = Join-Path (Split-Path $settings.autoDir -Parent) 'undo-exports'
    New-Item -ItemType Directory -Force -Path $exportRoot | Out-Null
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tmp = Join-Path $exportRoot "imp-$ts"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $imported = 0
    $skipped = 0
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $tmp -Force
        $snapDirs = Get-ChildItem -LiteralPath $tmp -Recurse -Directory -Force | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json') }
        foreach ($d in $snapDirs) {
            try { $kind = (Get-Content -LiteralPath (Join-Path $d.FullName 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).kind } catch { $kind = 'auto' }
            $dest = if ($kind -eq 'manual') { $settings.manualDir } else { $settings.autoDir }
            if (Test-Path -LiteralPath (Join-Path $dest $d.Name)) { $skipped++; continue }
            Copy-Item -LiteralPath $d.FullName -Destination $dest -Recurse -Force
            $imported++
        }
        # v0.2: import the blob store (content-addressed; skip existing hashes)
        $blobTmp = Join-Path $tmp 'blobs'
        if (Test-Path -LiteralPath $blobTmp) {
            $destBlob = Get-UndoBlobDir
            New-Item -ItemType Directory -Force -Path $destBlob | Out-Null
            foreach ($bf in Get-ChildItem -LiteralPath $blobTmp -File -Force -ErrorAction SilentlyContinue) {
                $dest = Join-Path $destBlob $bf.Name
                if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $bf.FullName -Destination $dest -Force }
            }
        }
        return @{ ok = $true; imported = $imported; skipped = $skipped; source = $ZipPath }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-UndoBootAlert {
    $settings = Get-UndoSettings
    $stateFile = Join-Path $settings.autoDir 'boot-state.json'
    $crashed = $false
    $lastGoodAt = $null
    # legacy .booting marker still counts as an abnormal exit
    if (Test-Path -LiteralPath (Join-Path $settings.autoDir '.booting')) { $crashed = $true }
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $st = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $st.ok) { $crashed = $true }
            if ($st.lastGoodAt) { $lastGoodAt = $st.lastGoodAt }
        } catch { }
    }
    return @{ crashed = $crashed; lastGoodAt = $lastGoodAt }
}

# Last-known-good snapshot id (v0.3): newest non-pre-restore snapshot not newer
# than the last successful boot. Returns $null when unknown.
function Get-UndoLastGoodId {
    $boot = Get-UndoBootAlert
    if (-not $boot.lastGoodAt) { return $null }
    try { $t = [datetime]::Parse($boot.lastGoodAt).ToUniversalTime() } catch { return $null }
    foreach ($s in (Get-UndoSnapshots)) {
        if ($s.kind -eq 'pre-restore') { continue }
        try {
            if ([datetime]$s.time -le $t) { return $s.id }
        } catch { }
    }
    return $null
}

function Set-UndoSettings([hashtable]$New) {
    $current = Get-UndoSettings
    foreach ($k in $New.Keys) {
        if ($null -ne $New[$k]) { $current[$k] = $New[$k] }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $script:UndoSettingsFile -Parent) | Out-Null
    $json = $current | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($script:UndoSettingsFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $current
}

function Get-UndoDiffText([string]$Id) {
    $target = if ($Id -eq 'latest') { @(Get-UndoSnapshots)[0] } else { Get-UndoSnapshotById $Id }
    if ($null -eq $target) { return "Snapshot not found: $Id" }
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in $script:UndoFileSpecs) {
        $snapPath = Join-Path $target._Dir (Get-UndoDestName $f)
        $curPath = Join-Path $f.Root $f.Name
        $hasSnap = Test-Path -LiteralPath $snapPath
        $hasCur = Test-Path -LiteralPath $curPath
        if (-not $hasSnap -and -not $hasCur) { continue }
        if ($hasSnap -and -not $hasCur) { [void]$sb.AppendLine("$((Get-UndoDestName $f)): file did not exist at snapshot time"); continue }
        if (-not $hasSnap -and $hasCur) { [void]$sb.AppendLine("$((Get-UndoDestName $f)): NEW file (absent in snapshot)"); continue }
        # sensitive files (v0.3.2): BOTH diff sides run through redaction —
        # the snapshot side may be an old plaintext snapshot and the current
        # side is always the live plaintext file; neither may leak real values
        $a = @(Get-Content -LiteralPath $snapPath)
        $b = @(Get-Content -LiteralPath $curPath)
        if (Test-UndoSensitiveName (Get-UndoDestName $f)) {
            $destName = Get-UndoDestName $f
            $a = @((Get-UndoRedactedForDest $destName ($a -join "`n")) -split "`n")
            $b = @((Get-UndoRedactedForDest $destName ($b -join "`n")) -split "`n")
        }
        $onlyA = @($a | Where-Object { $_ -notin $b })
        $onlyB = @($b | Where-Object { $_ -notin $a })
        if (@($onlyA).Count -eq 0 -and @($onlyB).Count -eq 0) { continue }
        [void]$sb.AppendLine("$((Get-UndoDestName $f)): +$(@($onlyB).Count) -$(@($onlyA).Count)")
        if (Test-UndoSensitiveName (Get-UndoDestName $f)) { [void]$sb.AppendLine('  (sensitive values are redacted in diffs; restore pulls real values from the local vault)') }
        foreach ($l in ($onlyA | Select-Object -First 20)) { [void]$sb.AppendLine("  - $l") }
        foreach ($l in ($onlyB | Select-Object -First 20)) { [void]$sb.AppendLine("  + $l") }
    }
    # v0.2: plugin code trees + profile-local code
    foreach ($p in @($target.plugins | Where-Object { $_ })) {
        foreach ($f in @($p.files | Where-Object { $_ })) {
            $blob = Read-UndoBlob $f.hash
            $curPath = Join-Path $p.dir $f.path
            $hasCur = Test-Path -LiteralPath $curPath
            if (-not $blob -and -not $hasCur) { continue }
            $label = "plugin $($p.name)/$($f.path)"
            if ($blob -and -not $hasCur) { [void]$sb.AppendLine("$label : file was deleted after snapshot"); continue }
            if (-not $blob -and $hasCur) { [void]$sb.AppendLine("$label : snapshot content unavailable (blob missing)"); continue }
            $a = @(Get-Content -LiteralPath $blob)
            $b = @(Get-Content -LiteralPath $curPath)
            $onlyA = @($a | Where-Object { $_ -notin $b })
            $onlyB = @($b | Where-Object { $_ -notin $a })
            if (@($onlyA).Count -eq 0 -and @($onlyB).Count -eq 0) { continue }
            [void]$sb.AppendLine("$label : +$(@($onlyB).Count) -$(@($onlyA).Count)")
            foreach ($l in ($onlyA | Select-Object -First 20)) { [void]$sb.AppendLine("  - $l") }
            foreach ($l in ($onlyB | Select-Object -First 20)) { [void]$sb.AppendLine("  + $l") }
        }
    }
    foreach ($f in @($target.profileFiles | Where-Object { $_ -and $_.hash })) {
        $blob = Read-UndoBlob $f.hash
        $curPath = Join-Path $script:UndoProfileRoot $f.path
        $hasCur = Test-Path -LiteralPath $curPath
        if (-not $blob -and -not $hasCur) { continue }
        $label = "profile ./$($f.path)"
        if ($blob -and -not $hasCur) { [void]$sb.AppendLine("$label : file was deleted after snapshot"); continue }
        if (-not $blob -and $hasCur) { [void]$sb.AppendLine("$label : snapshot content unavailable (blob missing)"); continue }
        $a = @(Get-Content -LiteralPath $blob)
        $b = @(Get-Content -LiteralPath $curPath)
        $onlyA = @($a | Where-Object { $_ -notin $b })
        $onlyB = @($b | Where-Object { $_ -notin $a })
        if (@($onlyA).Count -eq 0 -and @($onlyB).Count -eq 0) { continue }
        [void]$sb.AppendLine("$label : +$(@($onlyB).Count) -$(@($onlyA).Count)")
        foreach ($l in ($onlyA | Select-Object -First 20)) { [void]$sb.AppendLine("  - $l") }
        foreach ($l in ($onlyB | Select-Object -First 20)) { [void]$sb.AppendLine("  + $l") }
    }
    if ($sb.Length -eq 0) { return '(no differences)' }
    return $sb.ToString()
}