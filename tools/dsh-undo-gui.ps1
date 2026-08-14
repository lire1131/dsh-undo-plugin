# dsh-undo-gui.ps1 - DSH 撤销管理器(独立程序窗口,不依赖 DSH 运行)
# 双击 dsh-undo-gui.bat 或桌面「DSH 撤销管理器」快捷方式打开。
# 功能:查看/维护快照、手动保存、撤销、恢复、回退到指定版本、删除。
# 说明:本脚本自行隐藏控制台窗口,因此启动参数不需要 -WindowStyle Hidden
#      (该参数组合易被安全软件误报为木马行为)。
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'dsh-undo-lib.ps1')

# Hide the console window right after startup (safe no-op when none exists).
try {
    Add-Type -Namespace UndoWin -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
'@
    $null = [UndoWin.Native]::ShowWindow([UndoWin.Native]::GetConsoleWindow(), 0)
} catch { /* ignore: console hiding is cosmetic */ }

[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-KindLabel([string]$Kind) {
    switch ($Kind) {
        'manual' { '手动' }
        'auto' { '自动' }
        'baseline' { '基线' }
        'pre-restore' { '后悔档' }
        default { $Kind }
    }
}

function Get-StoreLabel([string]$Store) {
    switch ($Store) {
        'manual' { '手动库' }
        'auto' { '自动库' }
        default { '旧库' }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DSH 撤销管理器'
$form.Size = New-Object System.Drawing.Size(980, 600)
$form.MinimumSize = New-Object System.Drawing.Size(760, 420)
$form.StartPosition = 'CenterScreen'

# 工具栏
$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Dock = 'Top'
$toolbar.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
$toolbar.Height = 46

function New-ToolButton([string]$Text, [int]$Width, [scriptblock]$OnClick) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Width = $Width
    $btn.Height = 28
    $btn.Add_Click($OnClick)
    return $btn
}

$btnSave = New-ToolButton '💾 手动保存' 110 { Save-Snapshot }
$btnUndo = New-ToolButton '↩ 撤销' 90 { Invoke-QuickUndo 'undo' }
$btnRedo = New-ToolButton '↪ 恢复' 90 { Invoke-QuickUndo 'redo' }
$btnRestore = New-ToolButton '⏪ 回退所选' 110 { Restore-Selected }
$btnDelete = New-ToolButton '🗑 删除所选' 110 { Delete-Selected }
$btnRefresh = New-ToolButton '🔄 刷新' 90 { Update-List }

$toolbar.Controls.Add($btnSave)
$toolbar.Controls.Add($btnUndo)
$toolbar.Controls.Add($btnRedo)
$toolbar.Controls.Add($btnRestore)
$toolbar.Controls.Add($btnDelete)
$toolbar.Controls.Add($btnRefresh)

# 列表
$list = New-Object System.Windows.Forms.ListView
$list.Dock = 'Fill'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.GridLines = $false
$list.MultiSelect = $false
$list.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$colTime = $list.Columns.Add('时间', 150)
$colKind = $list.Columns.Add('类型', 70)
$colStore = $list.Columns.Add('库', 70)
$colReason = $list.Columns.Add('原因', 320)
$colFiles = $list.Columns.Add('文件', 60)

# 状态栏
$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Bottom'
$status.Height = 26
$status.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 0)
$status.Text = '就绪'

$form.Controls.Add($list)
$form.Controls.Add($toolbar)
$form.Controls.Add($status)

function Set-Status([string]$Text) { $status.Text = $Text }

function Update-List {
    $list.Items.Clear()
    $snaps = Get-UndoSnapshots
    foreach ($s in $snaps) {
        $item = New-Object System.Windows.Forms.ListViewItem
        $item.Text = ([datetime]$s.time).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
        $item.SubItems.Add((Get-KindLabel $s.kind)) | Out-Null
        $item.SubItems.Add((Get-StoreLabel $s._Store)) | Out-Null
        $item.SubItems.Add((($s.reason | Out-String).Trim())) | Out-Null
        $item.SubItems.Add([string]@($s.files).Count) | Out-Null
        $item.Tag = $s.id
        $list.Items.Add($item) | Out-Null
    }
    Set-Status "共 $($snaps.Count) 个快照(最新在上)。双击某行 = 回退到该版本。"
}

function Save-Snapshot {
    try {
        $s = New-UndoSnapshot 'manual' 'manual:gui'
        Set-Status "已手动保存快照 $($s.id)"
        Update-List
    } catch {
        Set-Status "保存失败: $($_.Exception.Message)"
    }
}

function Invoke-QuickUndo([string]$Mode) {
    try {
        $r = Invoke-UndoRestore $Mode ''
        if (-not $r.ok) { Set-Status "失败: $($r.error)"; Update-List; return }
        if ($r.unchanged) { Set-Status $r.message; return }
        Set-Status "已$(if ($Mode -eq 'undo') { '撤销' } else { '恢复' }):$($r.targetId) · 后悔档 $($r.preSnapshotId)"
        Update-List
    } catch {
        Set-Status "失败: $($_.Exception.Message)"
    }
}

function Get-SelectedId {
    if ($list.SelectedItems.Count -eq 0) { return $null }
    return $list.SelectedItems[0].Tag
}

function Restore-Selected {
    $id = Get-SelectedId
    if ($null -eq $id) { Set-Status '请先选中一个快照'; return }
    if ([System.Windows.Forms.MessageBox]::Show("确认回退到快照 $id 吗?当前状态会先保存为后悔档,可再恢复。", '确认回退', 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        $r = Invoke-UndoRestore 'id' $id
        if (-not $r.ok) { Set-Status "回退失败: $($r.error)"; return }
        Set-Status "已回退到 $($r.targetId),后悔档 $($r.preSnapshotId)"
        Update-List
    } catch {
        Set-Status "回退失败: $($_.Exception.Message)"
    }
}

function Delete-Selected {
    $id = Get-SelectedId
    if ($null -eq $id) { Set-Status '请先选中一个快照'; return }
    if ([System.Windows.Forms.MessageBox]::Show("确认删除快照 $id 吗?此操作不可恢复。", '确认删除', 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        $r = Remove-UndoSnapshot $id
        if (-not $r.ok) { Set-Status "删除失败: $($r.error)"; return }
        Set-Status "已删除快照 $($r.removed)"
        Update-List
    } catch {
        Set-Status "删除失败: $($_.Exception.Message)"
    }
}

$list.Add_DoubleClick({ Restore-Selected })

$form.Add_Shown({ Update-List })
[System.Windows.Forms.Application]::Run($form)
