# apply-dsh-patches.ps1 - dsh-session-persistence-jsonl 容错补丁托管（v0.3.8, B4）
#
# 背景：DSH 实际加载的 dsh-session-persistence-jsonl（全局包嵌套版本）缺 3 处
# 容错补丁（appendBatch 自愈 / listArtifacts 隔离 / readFirstZstdLine 宽容），
# 会话文件损坏/竞态会直接拖垮 DSH 启动。本脚本把 lib/ 同仓的补丁清单
# （dsh-patches.json：old = rc8 原始代码片段，new = rc6 已验证补丁代码片段）
# 精确替换到目标文件。所有操作可逆（remove 反向替换）。
#
# 用法: .\apply-dsh-patches.ps1 <status|verify|apply|remove>
#   status  只读：检测每个补丁 applied / missing / unknown（不写任何文件）
#   verify  校验清单每个补丁能在目标文件中精确匹配（applied 或 missing 都算匹配）
#   apply   逐补丁备份（<file>.bak-<id>）+ old->new 替换；已应用/未知则跳过或中止
#   remove  反向 new->old 还原全部补丁

param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'verify', 'apply', 'remove')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Stop'
$listPath = Join-Path $PSScriptRoot 'dsh-patches.json'
if (-not (Test-Path -LiteralPath $listPath)) { Write-Host "patch manifest not found: $listPath"; exit 2 }
$manifest = Get-Content -LiteralPath $listPath -Raw -Encoding UTF8 | ConvertFrom-Json

# 定位目标文件：按优先级探测候选根（全局 dsh 嵌套 > 全局顶层 > 用户级 > DSH_HOME）
$cands = @()
if ($env:APPDATA) {
    $appdataNpm = Join-Path $env:APPDATA 'npm\node_modules'
    $cands += (Join-Path $appdataNpm '@deepseek-ai\dsh\node_modules')
    $cands += $appdataNpm
}
$cands += (Join-Path $HOME 'node_modules')
if ($env:DSH_HOME) { $cands += (Join-Path $env:DSH_HOME 'node_modules') }
$target = $null
foreach ($c in $cands) {
    $p = Join-Path $c $manifest.target
    if (Test-Path -LiteralPath $p) { $target = $p; break }
}
if (-not $target) {
    Write-Host "target not found: $($manifest.target) — searched:"
    $cands | ForEach-Object { Write-Host "  $_" }
    exit 2
}

function Get-PatchState($Text, $Patch) {
    if ($Text.Contains($Patch.new)) { return 'applied' }
    if ($Text.Contains($Patch.old)) { return 'missing' }
    return 'unknown'
}

$text = Get-Content -LiteralPath $target -Raw -Encoding UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

switch ($Action) {
    'status' {
        Write-Host "target: $target"
        foreach ($p in $manifest.patches) {
            $s = Get-PatchState $text $p
            Write-Host ("  {0,-26} {1,-9} {2}" -f $p.id, $s, $p.description)
        }
    }
    'verify' {
        $bad = 0
        Write-Host "target: $target"
        foreach ($p in $manifest.patches) {
            $s = Get-PatchState $text $p
            Write-Host ("  {0,-26} {1,-9} {2}" -f $p.id, $s, $p.description)
            if ($s -eq 'unknown') { $bad++ }
        }
        if ($bad -gt 0) { Write-Host "verify FAILED: $bad patch(es) cannot be matched (manual edit of the target? run apply-dsh-patches.ps1 remove -- no, first inspect the diff)."; exit 1 }
        Write-Host 'verify OK: all patches resolve (applied or missing).'
    }
    'apply' {
        $any = $false
        Write-Host "target: $target"
        foreach ($p in $manifest.patches) {
            $s = Get-PatchState $text $p
            if ($s -eq 'applied') { Write-Host "  skip    $($p.id) (already applied)"; continue }
            if ($s -eq 'unknown') { Write-Host "  ERROR   $($p.id) (neither old nor new matches — target manually edited? aborting, nothing written)"; exit 1 }
            $bak = "$target.bak-$($p.id)"
            if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $target -Destination $bak -Force }
            $text = $text.Replace($p.old, $p.new)
            $any = $true
            Write-Host "  apply   $($p.id)"
        }
        if ($any) {
            [System.IO.File]::WriteAllText($target, $text, $utf8NoBom)
            Write-Host "written: $target"
        }
        Write-Host 'apply done. Restart DSH for the patches to take effect.'
    }
    'remove' {
        $any = $false
        Write-Host "target: $target"
        foreach ($p in $manifest.patches) {
            $s = Get-PatchState $text $p
            if ($s -eq 'missing') { Write-Host "  skip    $($p.id) (already removed)"; continue }
            if ($s -eq 'unknown') { Write-Host "  ERROR   $($p.id) (cannot match new — target manually edited? aborting, nothing written)"; exit 1 }
            $text = $text.Replace($p.new, $p.old)
            $any = $true
            Write-Host "  remove  $($p.id)"
        }
        if ($any) {
            [System.IO.File]::WriteAllText($target, $text, $utf8NoBom)
            Write-Host "written: $target"
        }
        Write-Host 'remove done. Restart DSH for the change to take effect.'
    }
}
