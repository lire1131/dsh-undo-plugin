# dsh-undo.ps1 - external undo/rollback tool for DSH config (works even when DSH cannot boot)
#
# Usage:
#   .\dsh-undo.ps1 snapshot [-Label "before installing X"]
#   .\dsh-undo.ps1 list
#   .\dsh-undo.ps1 diff -Id <id|latest>
#   .\dsh-undo.ps1 restore -Id <id|latest> [-Force]
#   .\dsh-undo.ps1 prune [-KeepAuto 20]
#   .\dsh-undo.ps1 status
#
# The snapshot store (D:\dsh\undo-snapshots by default, override with
# $env:UNDO_SNAPSHOT_DIR) is SHARED with the dsh-undo DSH plugin: both sides
# see the same snapshots and formats.

param(
    [Parameter(Position = 0)]
    [ValidateSet('snapshot', 'list', 'diff', 'restore', 'prune', 'status')]
    [string]$Command = 'status',
    [string]$Label = '',
    [string]$Id = '',
    [int]$KeepAuto = 20,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$SnapshotRoot = if ($env:UNDO_SNAPSHOT_DIR) { $env:UNDO_SNAPSHOT_DIR } else { 'D:\dsh\undo-snapshots' }
$HomeRoot = Join-Path $env:USERPROFILE '.dsh'
$ProfileRoot = Join-Path $HomeRoot 'profiles\web'

# Must mirror FILE_SPECS in the dsh-undo plugin (lib/index.js).
$Files = @(
    @{ RootKey = 'profile'; Root = $ProfileRoot; Name = 'cordis.patch.yml' },
    @{ RootKey = 'profile'; Root = $ProfileRoot; Name = 'package.json' },
    @{ RootKey = 'profile'; Root = $ProfileRoot; Name = 'cordis.yml' },
    @{ RootKey = 'profile'; Root = $ProfileRoot; Name = 'pnpm-workspace.yaml' },
    @{ RootKey = 'home';    Root = $HomeRoot;    Name = 'settings.yaml' },
    @{ RootKey = 'home';    Root = $HomeRoot;    Name = '.env' }
)

function Get-DestName([hashtable]$Spec) {
    return "$($Spec.RootKey)-$($Spec.Name -replace '[\\/]', '-')"
}

function Get-SpecByName([string]$DestName) {
    foreach ($f in $Files) { if ((Get-DestName $f) -eq $DestName) { return $f } }
    return $null
}

function New-Snapshot([string]$Kind, [string]$Reason) {
    New-Item -ItemType Directory -Force -Path $SnapshotRoot | Out-Null
    $id = '{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), ([System.Guid]::NewGuid().ToString('N').Substring(0, 4))
    $dir = Join-Path $SnapshotRoot $id
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # NOTE: must NOT be named $files — PowerShell variables are case-insensitive
    # and would shadow the script-level $Files config list.
    $fileList = @()
    foreach ($f in $Files) {
        $src = Join-Path $f.Root $f.Name
        if (Test-Path -LiteralPath $src) {
            $dest = Join-Path $dir (Get-DestName $f)
            Copy-Item -LiteralPath $src -Destination $dest -Force
            $fileList += @{ name = (Get-DestName $f); size = (Get-Item -LiteralPath $dest).Length }
        }
    }
    $manifest = @{ id = $id; time = (Get-Date).ToUniversalTime().ToString('o'); kind = $Kind; reason = $Reason; files = $fileList }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dir 'manifest.json') -Encoding UTF8
    Write-Host "Snapshot $id created ($($fileList.Count) file(s), ${Kind}: ${Reason})"
    return $manifest
}

function Get-Snapshots {
    if (-not (Test-Path -LiteralPath $SnapshotRoot)) { return @() }
    $out = @()
    foreach ($d in Get-ChildItem -LiteralPath $SnapshotRoot -Directory -Force) {
        $m = Join-Path $d.FullName 'manifest.json'
        if (Test-Path -LiteralPath $m) {
            try {
                $out += Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch { }
        }
    }
    return @($out | Sort-Object -Property time -Descending)
}

function Find-Snapshot([string]$Id) {
    $list = Get-Snapshots
    if ($Id -eq 'latest') { return $list[0] }
    foreach ($s in $list) { if ($s.id -eq $Id) { return $s } }
    return $null
}

function Ensure-UndoMount {
    $patch = Join-Path $ProfileRoot 'cordis.patch.yml'
    if (-not (Test-Path -LiteralPath $patch)) { return $false }
    $content = [System.IO.File]::ReadAllText($patch)
    if ($content -match 'dsh-undo') { return $false }
    $content = $content -replace '(?m)^\s*\[\]\s*$', ''
    $block = "`n# dsh-undo mount (re-ensured by dsh-undo)`n- insert:`n    - id: dsh-undo`n      name: dsh-undo`n"
    $content = $content.TrimEnd() + $block
    [System.IO.File]::WriteAllText($patch, $content, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Invoke-Restore([string]$TargetId, [switch]$SkipConfirm) {
    $target = Find-Snapshot $TargetId
    if ($null -eq $target) { throw "Snapshot not found: $TargetId (use list)" }
    $dir = Join-Path $SnapshotRoot $target.id
    $pre = New-Snapshot 'pre-restore' "before-restore:$($target.id) ($($target.kind): $($target.reason))"
    $restored = @()
    foreach ($file in $target.files) {
        $spec = Get-SpecByName $file.name
        if ($null -eq $spec) { continue }
        $src = Join-Path $dir $file.name
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $spec.Root $spec.Name
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $restored += $file.name
    }
    $remounted = Ensure-UndoMount
    Write-Host "Restored $($target.id) ($($target.kind): $($target.reason))"
    Write-Host "Files: $($restored -join ', ')"
    Write-Host "Pre-restore safety snapshot: $($pre.id)"
    if ($remounted) { Write-Host 'dsh-undo mount re-ensured in cordis.patch.yml' }
}

switch ($Command) {
    'snapshot' {
        $kind = if ($Label -match '^before|^boot|^auto|^baseline') { 'manual' } else { 'manual' }
        New-Snapshot 'manual' $(if ($Label) { $Label } else { 'manual' }) | Out-Null
    }
    'list' {
        $list = Get-Snapshots
        if ($list.Count -eq 0) { Write-Host 'No snapshots yet.'; break }
        Write-Host ('{0,-22} {1,-10} {2,-14} {3,-40} {4}' -f 'ID', 'KIND', 'TIME', 'REASON', 'FILES')
        foreach ($s in $list) {
            $t = ([datetime]$s.time).ToLocalTime().ToString('MM-dd HH:mm:ss')
            Write-Host ('{0,-22} {1,-10} {2,-14} {3,-40} {4}' -f $s.id, $s.kind, $t, ($s.reason | Out-String).Trim(), ($s.files.Count))
        }
    }
    'diff' {
        $target = Find-Snapshot $Id
        if ($null -eq $target) { throw "Snapshot not found: $Id" }
        $dir = Join-Path $SnapshotRoot $target.id
        foreach ($f in $Files) {
            $snapPath = Join-Path $dir (Get-DestName $f)
            $curPath = Join-Path $f.Root $f.Name
            $hasSnap = Test-Path -LiteralPath $snapPath
            $hasCur = Test-Path -LiteralPath $curPath
            if (-not $hasSnap -and -not $hasCur) { continue }
            if ($hasSnap -and -not $hasCur) { Write-Host "$(Get-DestName $f): file did not exist at snapshot time"; continue }
            if (-not $hasSnap -and $hasCur) { Write-Host "$(Get-DestName $f): NEW file (absent in snapshot)"; continue }
            $a = Get-Content -LiteralPath $snapPath | ForEach-Object { $_ }
            $b = Get-Content -LiteralPath $curPath | ForEach-Object { $_ }
            $onlyA = @($a | Where-Object { $_ -notin $b })
            $onlyB = @($b | Where-Object { $_ -notin $a })
            if ($onlyA.Count -eq 0 -and $onlyB.Count -eq 0) { continue }
            Write-Host "$(Get-DestName $f): snapshot has $($onlyA.Count) unique line(s), current has $($onlyB.Count) unique line(s)"
            foreach ($l in ($onlyA | Select-Object -First 6)) { Write-Host "  - (snapshot) $l" }
            foreach ($l in ($onlyB | Select-Object -First 6)) { Write-Host "  + (current)  $l" }
        }
    }
    'restore' {
        if ([string]::IsNullOrEmpty($Id)) { throw 'restore requires -Id <id|latest>' }
        Invoke-Restore $Id -SkipConfirm:$Force
    }
    'prune' {
        $list = Get-Snapshots | Where-Object { $_.kind -eq 'auto' -or $_.kind -eq 'baseline' } | Sort-Object -Property time
        $excess = @($list | Select-Object -First ([Math]::Max(0, $list.Count - $KeepAuto)))
        foreach ($s in $excess) {
            Remove-Item -LiteralPath (Join-Path $SnapshotRoot $s.id) -Recurse -Force
            Write-Host "Pruned $($s.id) ($($s.kind))"
        }
        Write-Host "Pruned $($excess.Count) snapshot(s); kept $KeepAuto auto/baseline."
    }
    'status' {
        $list = Get-Snapshots
        Write-Host "Snapshot store: $SnapshotRoot"
        Write-Host "Total snapshots: $($list.Count)"
        Write-Host ("  manual:       {0}" -f @($list | Where-Object { $_.kind -eq 'manual' }).Count)
        Write-Host ("  auto:         {0}" -f @($list | Where-Object { $_.kind -eq 'auto' }).Count)
        Write-Host ("  baseline:     {0}" -f @($list | Where-Object { $_.kind -eq 'baseline' }).Count)
        Write-Host ("  pre-restore:  {0}" -f @($list | Where-Object { $_.kind -eq 'pre-restore' }).Count)
        if ($list.Count -gt 0) { Write-Host "Newest: $($list[0].id) ($($list[0].kind): $($list[0].reason))" }
    }
}
