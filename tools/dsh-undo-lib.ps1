# dsh-undo-lib.ps1 - shared logic for the dsh-undo external tooling.
# Dot-source this from dsh-undo.ps1 (CLI) and dsh-undo-gui.ps1 (window).
# Works WITHOUT DSH running: reads/writes the same snapshot stores and the
# same manifest format as the dsh-undo DSH plugin.
#
# Store layout (mirrors lib/index.js):
#   manual snapshots -> <root>\manual ; auto/baseline/pre-restore -> <root>\auto
#   legacy flat snapshots under <root> are read too.

$script:UndoSnapshotRoot = 'D:\dsh\undo-snapshots'
$script:UndoLegacyRoot = $script:UndoSnapshotRoot
$script:UndoManualDir = Join-Path $script:UndoSnapshotRoot 'manual'
$script:UndoAutoDir = Join-Path $script:UndoSnapshotRoot 'auto'
$script:UndoHome = 'D:\dsh\undo'
$script:UndoSettingsFile = Join-Path $script:UndoHome 'settings.json'
$script:UndoHomeRoot = Join-Path $env:USERPROFILE '.dsh'
$script:UndoProfileRoot = Join-Path $script:UndoHomeRoot 'profiles\web'

# Must mirror FILE_SPECS in the dsh-undo plugin (lib/index.js).
$script:UndoFileSpecs = @(
    @{ RootKey = 'profile'; Root = $script:UndoProfileRoot; Name = 'cordis.patch.yml' },
    @{ RootKey = 'profile'; Root = $script:UndoProfileRoot; Name = 'package.json' },
    @{ RootKey = 'profile'; Root = $script:UndoProfileRoot; Name = 'cordis.yml' },
    @{ RootKey = 'profile'; Root = $script:UndoProfileRoot; Name = 'pnpm-workspace.yaml' },
    @{ RootKey = 'home';    Root = $script:UndoHomeRoot;    Name = 'settings.yaml' },
    @{ RootKey = 'home';    Root = $script:UndoHomeRoot;    Name = '.env' }
)

function Get-UndoDestName([hashtable]$Spec) {
    return "$($Spec.RootKey)-$($Spec.Name -replace '[\\/]', '-')"
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
    $defaults = @{
        autoEnabled = $true
        watchDebounceMs = 1500
        keepAuto = 20
        manualDir = $script:UndoManualDir
        autoDir = $script:UndoAutoDir
    }
    if (Test-Path -LiteralPath $script:UndoSettingsFile) {
        try {
            $j = Get-Content -LiteralPath $script:UndoSettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.manualDir) { $defaults.manualDir = $j.manualDir }
            if ($j.autoDir) { $defaults.autoDir = $j.autoDir }
            if ($j.autoEnabled -is [bool]) { $defaults.autoEnabled = $j.autoEnabled }
            if ($j.watchDebounceMs) { $defaults.watchDebounceMs = [int]$j.watchDebounceMs }
            if ($j.keepAuto) { $defaults.keepAuto = [int]$j.keepAuto }
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
    foreach ($f in $script:UndoFileSpecs) {
        $src = Join-Path $f.Root $f.Name
        if (Test-Path -LiteralPath $src) {
            $dest = Join-Path $dir (Get-UndoDestName $f)
            Copy-Item -LiteralPath $src -Destination $dest -Force
            $fileList += @{ name = (Get-UndoDestName $f); size = (Get-Item -LiteralPath $dest).Length }
        }
    }
    $manifest = @{ id = $id; time = (Get-Date).ToUniversalTime().ToString('o'); kind = $Kind; reason = $Reason; files = $fileList }
    $json = $manifest | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    return $manifest
}

function Get-UndoState([object]$Snap) {
    $pairs = @()
    foreach ($file in @($Snap.files)) {
        $p = Join-Path $Snap._Dir $file.name
        if (Test-Path -LiteralPath $p) {
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA1).Hash
            $pairs += , @($file.name, $h)
        }
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
    foreach ($file in @($Snap.files)) {
        $spec = Get-UndoSpecByName $file.name
        if ($null -eq $spec) { continue }
        $src = Join-Path $Snap._Dir $file.name
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $spec.Root $spec.Name
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $restored += $file.name
    }
    return $restored
}

function Ensure-UndoMount {
    $patch = Join-Path $script:UndoProfileRoot 'cordis.patch.yml'
    if (-not (Test-Path -LiteralPath $patch)) { return $false }
    $content = [System.IO.File]::ReadAllText($patch)
    if ($content -match 'dsh-undo') { return $false }
    $content = $content -replace '(?m)^\s*\[\]\s*$', ''
    $block = "`n# dsh-undo mount (re-ensured by dsh-undo)`n- insert:`n    - id: dsh-undo`n      name: dsh-undo`n"
    [System.IO.File]::WriteAllText($patch, ($content.TrimEnd() + $block), (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Invoke-UndoPrune([int]$KeepAuto) {
    $list = Get-UndoSnapshots | Where-Object { ($_.kind -eq 'auto' -or $_.kind -eq 'baseline') -and $_.location -eq 'auto' } | Sort-Object -Property time
    $excess = @($list | Select-Object -First ([Math]::Max(0, @($list).Count - $KeepAuto)))
    foreach ($s in $excess) {
        Remove-Item -LiteralPath $s._Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return @($excess).Count
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
        $restored = Invoke-UndoApply $target.s
        if ($target -ne $candidates[0]) { Set-UndoFlag $candidates[0].s 'stepped' $true }
        $remounted = Ensure-UndoMount
        return @{ ok = $true; restored = $restored; targetId = $target.s.id; targetKind = $target.s.kind; targetReason = $target.s.reason; preSnapshotId = $pre.id; remounted = $remounted }
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
        $restored = Invoke-UndoApply $pre
        Set-UndoFlag $pre 'consumed' $true
        return @{ ok = $true; restored = $restored; targetId = $pre.id; remounted = $false }
    }
    # mode 'id'
    $target = Get-UndoSnapshotById $Id
    if ($null -eq $target) { return @{ ok = $false; error = "snapshot not found: $Id" } }
    $pre = New-UndoSnapshot 'pre-restore' "before-restore:$($target.id) ($($target.kind): $($target.reason))"
    $restored = Invoke-UndoApply $target
    $remounted = Ensure-UndoMount
    return @{ ok = $true; restored = $restored; targetId = $target.id; targetKind = $target.kind; targetReason = $target.reason; preSnapshotId = $pre.id; remounted = $remounted }
}

function Remove-UndoSnapshot([string]$Id) {
    $snap = Get-UndoSnapshotById $Id
    if ($null -eq $snap) { return @{ ok = $false; error = "snapshot not found: $Id" } }
    Remove-Item -LiteralPath $snap._Dir -Recurse -Force
    return @{ ok = $true; removed = $Id }
}
