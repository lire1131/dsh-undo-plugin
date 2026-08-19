# make-desktop-shortcut.ps1 — 在桌面一键创建「DSH 撤销管理器」快捷方式
#
# 用途：解决"装完插件找不到局外撤销工具"的问题。
# 自动定位插件目录（按顺序）：
#   1) 本脚本自己就在插件的 tools 目录里（方式 B：clone + junction）；
#   2) 常见安装位置（方式 A：dsh plugin add → profile 依赖树；方式 B：用户 node_modules）。
# 找到后把 dsh-undo-savepoint-gui.bat 的快捷方式放到桌面，双击即可打开
# 「DSH 撤销管理器」窗口（DSH 崩溃、启动不了时也能用）。
#
# 用法：
#   双击 tools\make-desktop-shortcut.bat（推荐，会自动保持窗口）
#   或：powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-desktop-shortcut.ps1

$ErrorActionPreference = 'Stop'

# 定位插件的 tools 目录；找不到返回 $null
function Find-UndoToolsDir {
    # 1) 自身就在插件 tools 目录里（最常见：直接双击仓库/安装目录里的 bat）
    $self = Join-Path $PSScriptRoot 'dsh-undo-savepoint-gui.bat'
    if (Test-Path -LiteralPath $self) { return $PSScriptRoot }

    # 2) 搜索常见安装位置（只查固定候选路径，避免递归扫整个 node_modules 树）
    #    issue #6:优先 $DSH_HOME（自定义家目录客户端），否则 %USERPROFILE%\.dsh
    $dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
    $candidates = @(
        (Join-Path $dshHome 'profiles\web\node_modules\dsh-undo-savepoint'),
        (Join-Path $dshHome 'profiles\node_modules\dsh-undo-savepoint'),
        (Join-Path $env:USERPROFILE 'node_modules\dsh-undo-savepoint')
    )
    foreach ($c in $candidates) {
        $tools = Join-Path $c 'tools'
        if (Test-Path -LiteralPath (Join-Path $tools 'dsh-undo-savepoint-gui.bat')) {
            return $tools
        }
    }
    return $null
}

$toolsDir = Find-UndoToolsDir
if (-not $toolsDir) {
    Write-Host '未找到 dsh-undo-savepoint 插件（tools 目录不存在）。请先安装插件：'
    Write-Host '  dsh plugin --profile web add github:lire1131/dsh-undo-savepoint#master'
    Write-Host '安装后重跑本脚本。'
    Read-Host '按回车退出'
    exit 1
}

$guiBat = Join-Path $toolsDir 'dsh-undo-savepoint-gui.bat'
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop 'DSH撤销管理器.lnk'

$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath = $guiBat                    # 双击快捷方式 → 启动 GUI（bat 自带隐藏窗口）
$sc.WorkingDirectory = $toolsDir            # 工作目录设为 tools，保证相对路径解析正确
$sc.Description = 'DSH 撤销管理器（dsh-undo-savepoint 局外工具）'
$sc.Save()

Write-Host "已创建桌面快捷方式：$lnk"
Write-Host '双击桌面的「DSH撤销管理器」即可打开撤销工具（DSH 打不开时也能用）。'
Write-Host '如需删除：右键快捷方式 → 删除即可，不影响插件本身。'
Read-Host '按回车退出'
