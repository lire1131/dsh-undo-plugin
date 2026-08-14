# dsh-undo-gui.ps1 - DSH Undo Manager (standalone window, works without DSH)
# Bilingual (zh/en, auto-detected from the system UI language).
# Open via dsh-undo-gui.bat or the desktop "DSH Undo Manager" shortcut.
# Features: view/maintain snapshots, manual save, undo, redo, restore-to-version, delete.
# The script hides its own console window, so no -WindowStyle Hidden is needed
# (that flag combination tends to trigger antivirus false positives).
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

# ── UI language: $env:DSH_UNDO_LANG (zh|en) overrides; otherwise the system
#    UI language decides (zh* -> Chinese, anything else -> English) ─────────
$script:UndoLang = $env:DSH_UNDO_LANG
if (-not $script:UndoLang) {
    $script:UndoLang = if ([System.Globalization.CultureInfo]::CurrentUICulture.Name -like 'zh*') { 'zh' } else { 'en' }
}
$script:IsZh = ($script:UndoLang -eq 'zh')
if ($script:IsZh) {
    $script:UI = @{
        title = 'DSH 撤销管理器'
        btnSave = '💾 手动保存'
        btnUndo = '↩ 撤销'
        btnRedo = '↪ 恢复'
        btnRestore = '⏪ 回退所选'
        btnDelete = '🗑 删除所选'
        btnRefresh = '🔄 刷新'
        colTime = '时间'; colKind = '类型'; colStore = '库'; colReason = '原因'; colFiles = '文件'
        kindManual = '手动'; kindAuto = '自动'; kindBaseline = '基线'; kindPre = '后悔档'
        storeManual = '手动库'; storeAuto = '自动库'; storeLegacy = '旧库'
        statusReady = '就绪'
        statusCount = '共 {0} 个快照(最新在上)。双击某行 = 回退到该版本。'
        saved = '已手动保存快照 {0}'
        saveFail = '保存失败: {0}'
        fail = '失败: {0}'
        undone = '已撤销:{0} · 后悔档 {1}'
        redone = '已恢复:{0}'
        selectFirst = '请先选中一个快照'
        confirmRestoreTitle = '确认回退'
        confirmRestore = '确认回退到快照 {0} 吗?当前状态会先保存为后悔档,可再恢复。'
        restoreFail = '回退失败: {0}'
        restored = '已回退到 {0},后悔档 {1}'
        confirmDeleteTitle = '确认删除'
        confirmDelete = '确认删除快照 {0} 吗?此操作不可恢复。'
        deleteFail = '删除失败: {0}'
        deleted = '已删除快照 {0}'
    }
} else {
    $script:UI = @{
        title = 'DSH Undo Manager'
        btnSave = '💾 Save'
        btnUndo = '↩ Undo'
        btnRedo = '↪ Redo'
        btnRestore = '⏪ Restore Sel.'
        btnDelete = '🗑 Delete Sel.'
        btnRefresh = '🔄 Refresh'
        colTime = 'Time'; colKind = 'Type'; colStore = 'Store'; colReason = 'Reason'; colFiles = 'Files'
        kindManual = 'Manual'; kindAuto = 'Auto'; kindBaseline = 'Baseline'; kindPre = 'Pre-restore'
        storeManual = 'Manual'; storeAuto = 'Auto'; storeLegacy = 'Legacy'
        statusReady = 'Ready'
        statusCount = '{0} snapshot(s) (newest on top). Double-click a row to restore to that version.'
        saved = 'Manual snapshot {0} saved'
        saveFail = 'Save failed: {0}'
        fail = 'Failed: {0}'
        undone = 'Undone: {0} · redo point {1}'
        redone = 'Redone: {0}'
        selectFirst = 'Select a snapshot first'
        confirmRestoreTitle = 'Confirm restore'
        confirmRestore = 'Restore to snapshot {0}? The current state is kept as a redo point first.'
        restoreFail = 'Restore failed: {0}'
        restored = 'Restored to {0}, redo point {1}'
        confirmDeleteTitle = 'Confirm delete'
        confirmDelete = 'Delete snapshot {0}? This cannot be undone.'
        deleteFail = 'Delete failed: {0}'
        deleted = 'Deleted snapshot {0}'
    }
}

[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-KindLabel([string]$Kind) {
    switch ($Kind) {
        'manual' { $script:UI.kindManual }
        'auto' { $script:UI.kindAuto }
        'baseline' { $script:UI.kindBaseline }
        'pre-restore' { $script:UI.kindPre }
        default { $Kind }
    }
}

function Get-StoreLabel([string]$Store) {
    switch ($Store) {
        'manual' { $script:UI.storeManual }
        'auto' { $script:UI.storeAuto }
        default { $script:UI.storeLegacy }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:UI.title
$form.Size = New-Object System.Drawing.Size(980, 600)
$form.MinimumSize = New-Object System.Drawing.Size(760, 420)
$form.StartPosition = 'CenterScreen'

# toolbar
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

$btnSave = New-ToolButton $script:UI.btnSave 110 { Save-Snapshot }
$btnUndo = New-ToolButton $script:UI.btnUndo 90 { Invoke-QuickUndo 'undo' }
$btnRedo = New-ToolButton $script:UI.btnRedo 90 { Invoke-QuickUndo 'redo' }
$btnRestore = New-ToolButton $script:UI.btnRestore 120 { Restore-Selected }
$btnDelete = New-ToolButton $script:UI.btnDelete 120 { Delete-Selected }
$btnRefresh = New-ToolButton $script:UI.btnRefresh 90 { Update-List }

$toolbar.Controls.Add($btnSave)
$toolbar.Controls.Add($btnUndo)
$toolbar.Controls.Add($btnRedo)
$toolbar.Controls.Add($btnRestore)
$toolbar.Controls.Add($btnDelete)
$toolbar.Controls.Add($btnRefresh)

# list
$list = New-Object System.Windows.Forms.ListView
$list.Dock = 'Fill'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.GridLines = $false
$list.MultiSelect = $false
$list.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$colTime = $list.Columns.Add($script:UI.colTime, 150)
$colKind = $list.Columns.Add($script:UI.colKind, 80)
$colStore = $list.Columns.Add($script:UI.colStore, 80)
$colReason = $list.Columns.Add($script:UI.colReason, 320)
$colFiles = $list.Columns.Add($script:UI.colFiles, 60)

# status bar
$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Bottom'
$status.Height = 26
$status.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 0)
$status.Text = $script:UI.statusReady

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
    Set-Status ($script:UI.statusCount -f @($snaps).Count)
}

function Save-Snapshot {
    try {
        $s = New-UndoSnapshot 'manual' 'manual:gui'
        Set-Status ($script:UI.saved -f $s.id)
        Update-List
    } catch {
        Set-Status ($script:UI.saveFail -f $_.Exception.Message)
    }
}

function Invoke-QuickUndo([string]$Mode) {
    try {
        $r = Invoke-UndoRestore $Mode ''
        if (-not $r.ok) { Set-Status ($script:UI.fail -f $r.error); Update-List; return }
        if ($r.unchanged) { Set-Status $r.message; return }
        if ($Mode -eq 'undo') {
            Set-Status ($script:UI.undone -f $r.targetId, $r.preSnapshotId)
        } else {
            Set-Status ($script:UI.redone -f $r.targetId)
        }
        Update-List
    } catch {
        Set-Status ($script:UI.fail -f $_.Exception.Message)
    }
}

function Get-SelectedId {
    if ($list.SelectedItems.Count -eq 0) { return $null }
    return $list.SelectedItems[0].Tag
}

function Restore-Selected {
    $id = Get-SelectedId
    if ($null -eq $id) { Set-Status $script:UI.selectFirst; return }
    if ([System.Windows.Forms.MessageBox]::Show(($script:UI.confirmRestore -f $id), $script:UI.confirmRestoreTitle, 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        $r = Invoke-UndoRestore 'id' $id
        if (-not $r.ok) { Set-Status ($script:UI.restoreFail -f $r.error); return }
        Set-Status ($script:UI.restored -f $r.targetId, $r.preSnapshotId)
        Update-List
    } catch {
        Set-Status ($script:UI.restoreFail -f $_.Exception.Message)
    }
}

function Delete-Selected {
    $id = Get-SelectedId
    if ($null -eq $id) { Set-Status $script:UI.selectFirst; return }
    if ([System.Windows.Forms.MessageBox]::Show(($script:UI.confirmDelete -f $id), $script:UI.confirmDeleteTitle, 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        $r = Remove-UndoSnapshot $id
        if (-not $r.ok) { Set-Status ($script:UI.deleteFail -f $r.error); return }
        Set-Status ($script:UI.deleted -f $r.removed)
        Update-List
    } catch {
        Set-Status ($script:UI.deleteFail -f $_.Exception.Message)
    }
}

$list.Add_DoubleClick({ Restore-Selected })

$form.Add_Shown({ Update-List })
[System.Windows.Forms.Application]::Run($form)
