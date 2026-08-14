# dsh-undo.ps1 - external undo/rollback CLI for DSH config (works even when DSH cannot boot)
#
# Usage:
#   .\dsh-undo.ps1 snapshot [-Label "before installing X"]   # manual save
#   .\dsh-undo.ps1 undo                                       # undo the last change
#   .\dsh-undo.ps1 redo                                       # redo the last undo
#   .\dsh-undo.ps1 list                                       # visual list
#   .\dsh-undo.ps1 diff -Id <id|latest>
#   .\dsh-undo.ps1 restore -Id <id|latest> [-Force]           # restore a fixed version
#   .\dsh-undo.ps1 remove -Id <id>                            # delete a snapshot
#   .\dsh-undo.ps1 prune [-KeepAuto 20]
#   .\dsh-undo.ps1 status
#   .\dsh-undo.ps1 settings                                   # show current settings
#
# Snapshot stores: D:\dsh\undo-snapshots\manual and \auto (shared with the
# dsh-undo DSH plugin; legacy flat snapshots are read too).

param(
    [Parameter(Position = 0)]
    [ValidateSet('snapshot', 'list', 'diff', 'restore', 'undo', 'redo', 'remove', 'prune', 'status', 'settings')]
    [string]$Command = 'status',
    [string]$Label = '',
    [string]$Id = '',
    [int]$KeepAuto = 20,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'dsh-undo-lib.ps1')

switch ($Command) {
    'snapshot' {
        $reason = if ($Label) { $Label } else { 'manual' }
        $s = New-UndoSnapshot 'manual' $reason
        Write-Host "Manual snapshot $($s.id) created ($(@($s.files).Count) file(s), reason: $reason). Store: $((Get-UndoSettings).manualDir)"
    }
    'undo' {
        $r = Invoke-UndoRestore 'undo' ''
        if (-not $r.ok) { Write-Host "undo failed: $($r.error)"; exit 1 }
        if ($r.unchanged) { Write-Host $r.message; exit 0 }
        Write-Host "Undone: restored $($r.targetId) ($($r.targetKind): $($r.targetReason))"
        Write-Host "Files: $($r.restored -join ', ')"
        Write-Host "Pre-restore safety snapshot: $($r.preSnapshotId) (redo target)"
        if ($r.remounted) { Write-Host 'dsh-undo mount re-ensured in cordis.patch.yml' }
    }
    'redo' {
        $r = Invoke-UndoRestore 'redo' ''
        if (-not $r.ok) { Write-Host "redo failed: $($r.error)"; exit 1 }
        Write-Host "Redone: re-applied $($r.targetId)"
        Write-Host "Files: $($r.restored -join ', ')"
    }
    'list' {
        $list = Get-UndoSnapshots
        if (@($list).Count -eq 0) { Write-Host 'No snapshots yet.'; break }
        Write-Host ('{0,-22} {1,-11} {2,-8} {3,-9} {4,-10} {5,-40} {6}' -f 'ID', 'KIND', 'TIME', 'STORE', 'MARK', 'REASON', 'FILES')
        foreach ($s in $list) {
            $t = ([datetime]$s.time).ToLocalTime().ToString('MM-dd HH:mm')
            $mark = if ($s.stepped) { 'stepped' } elseif ($s.consumed) { 'consumed' } else { '' }
            Write-Host ('{0,-22} {1,-11} {2,-8} {3,-9} {4,-10} {5,-40} {6}' -f $s.id, $s.kind, $t, $s._Store, $mark, ($s.reason | Out-String).Trim(), @($s.files).Count)
        }
        $settings = Get-UndoSettings
        Write-Host "Manual store: $($settings.manualDir)"
        Write-Host "Auto store:   $($settings.autoDir)"
    }
    'diff' {
        if ([string]::IsNullOrEmpty($Id)) { throw 'diff requires -Id <id|latest>' }
        $target = if ($Id -eq 'latest') { @(Get-UndoSnapshots)[0] } else { Get-UndoSnapshotById $Id }
        if ($null -eq $target) { throw "Snapshot not found: $Id" }
        foreach ($f in $script:UndoFileSpecs) {
            $snapPath = Join-Path $target._Dir (Get-UndoDestName $f)
            $curPath = Join-Path $f.Root $f.Name
            $hasSnap = Test-Path -LiteralPath $snapPath
            $hasCur = Test-Path -LiteralPath $curPath
            if (-not $hasSnap -and -not $hasCur) { continue }
            if ($hasSnap -and -not $hasCur) { Write-Host "$(Get-UndoDestName $f): file did not exist at snapshot time"; continue }
            if (-not $hasSnap -and $hasCur) { Write-Host "$(Get-UndoDestName $f): NEW file (absent in snapshot)"; continue }
            $a = @(Get-Content -LiteralPath $snapPath)
            $b = @(Get-Content -LiteralPath $curPath)
            $onlyA = @($a | Where-Object { $_ -notin $b })
            $onlyB = @($b | Where-Object { $_ -notin $a })
            if (@($onlyA).Count -eq 0 -and @($onlyB).Count -eq 0) { continue }
            Write-Host "$(Get-UndoDestName $f): snapshot has $(@($onlyA).Count) unique line(s), current has $(@($onlyB).Count) unique line(s)"
            foreach ($l in ($onlyA | Select-Object -First 6)) { Write-Host "  - (snapshot) $l" }
            foreach ($l in ($onlyB | Select-Object -First 6)) { Write-Host "  + (current)  $l" }
        }
    }
    'restore' {
        if ([string]::IsNullOrEmpty($Id)) { throw 'restore requires -Id <id|latest>' }
        $targetId = if ($Id -eq 'latest') { @(Get-UndoSnapshots)[0].id } else { $Id }
        $r = Invoke-UndoRestore 'id' $targetId
        if (-not $r.ok) { Write-Host "restore failed: $($r.error)"; exit 1 }
        Write-Host "Restored $($r.targetId) ($($r.targetKind): $($r.targetReason))"
        Write-Host "Files: $($r.restored -join ', ')"
        Write-Host "Pre-restore safety snapshot: $($r.preSnapshotId)"
        if ($r.remounted) { Write-Host 'dsh-undo mount re-ensured in cordis.patch.yml' }
    }
    'remove' {
        if ([string]::IsNullOrEmpty($Id)) { throw 'remove requires -Id <id>' }
        $r = Remove-UndoSnapshot $Id
        if (-not $r.ok) { Write-Host "remove failed: $($r.error)"; exit 1 }
        Write-Host "Removed snapshot $($r.removed)"
    }
    'prune' {
        $n = Invoke-UndoPrune $KeepAuto
        Write-Host "Pruned $n snapshot(s); kept $KeepAuto auto/baseline."
    }
    'status' {
        $settings = Get-UndoSettings
        $list = Get-UndoSnapshots
        Write-Host "Manual store: $($settings.manualDir)"
        Write-Host "Auto store:   $($settings.autoDir)"
        Write-Host "Auto-save enabled: $($settings.autoEnabled) (debounce $($settings.watchDebounceMs)ms, keep $($settings.keepAuto))"
        Write-Host "Total snapshots: $(@($list).Count)"
        Write-Host ("  manual:       {0}" -f @($list | Where-Object { $_.kind -eq 'manual' }).Count)
        Write-Host ("  auto:         {0}" -f @($list | Where-Object { $_.kind -eq 'auto' }).Count)
        Write-Host ("  baseline:     {0}" -f @($list | Where-Object { $_.kind -eq 'baseline' }).Count)
        Write-Host ("  pre-restore:  {0}" -f @($list | Where-Object { $_.kind -eq 'pre-restore' }).Count)
        if (@($list).Count -gt 0) { Write-Host "Newest: $($list[0].id) ($($list[0].kind): $($list[0].reason))" }
    }
    'settings' {
        $settings = Get-UndoSettings
        $settings | ConvertTo-Json
    }
}
