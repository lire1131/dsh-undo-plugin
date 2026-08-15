# dsh-undo-savepoint-gui.ps1 - DSH Undo Manager (standalone window, works without DSH)
# v2: crash banner + one-click rollback, export/import, double-click diff,
#     clean-up, settings panel, system tray.
# Bilingual (zh/en): $env:DSH_UNDO_LANG overrides; system UI language otherwise.
# Open via dsh-undo-savepoint-gui.bat or the desktop shortcut.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'dsh-undo-savepoint-lib.ps1')

# Hide the console window right after startup (safe no-op when none exists).
try {
    Add-Type -Namespace UndoWin -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
'@
    $null = [UndoWin.Native]::ShowWindow([UndoWin.Native]::GetConsoleWindow(), 0)
} catch { /* ignore: console hiding is cosmetic */ }

# ── UI language: $env:DSH_UNDO_LANG (zh|en) overrides; otherwise system UI ──
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
        btnCleanup = '🧹 清理过期'
        btnExport = '📦 导出'
        btnImport = '📥 导入'
        btnSettings = '⚙️ 设置'
        colTime = '时间'; colKind = '类型'; colStore = '库'; colReason = '原因'; colFiles = '文件'
        kindManual = '手动'; kindAuto = '自动'; kindBaseline = '基线'; kindPre = '后悔档'
        storeManual = '手动库'; storeAuto = '自动库'; storeLegacy = '旧库'
        statusReady = '就绪'
        statusCount = '共 {0} 个快照(最新在上)。双击某行 = 查看差异。'
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
        bootBanner = '⚠️ 检测到上次 DSH 异常退出,建议回退到上次正常状态'
        bootRollback = '回退到上次正常状态'
        btnSafeMode = '安全模式'
        safeModeOnTitle = '开启安全模式'
        safeModeOnConfirm = '除撤销系统外的所有用户插件将被临时禁用(先自动快照并备份配置),重启 DSH 后生效。继续?'
        safeModeOffTitle = '退出安全模式'
        safeModeOffConfirm = '恢复进入安全模式前的完整插件配置,重启 DSH 后生效。继续?'
        safeModeOn = '安全模式已开启。重启 DSH 后仅加载撤销系统。'
        safeModeOff = '安全模式已退出。重启 DSH 后恢复全部插件。'
        safeModeFail = '安全模式操作失败: {0}'
        restartRequired = '已回退。重启 DSH 后恢复内容才会生效。'
        exported = '已导出 {0} 个快照 → {1}'
        exportFail = '导出失败: {0}'
        imported = '已导入 {0} 个快照({1} 个重复跳过)'
        importFail = '导入失败: {0}'
        cleaned = '已清理 {0} 个自动档、{1} 个后悔档'
        cleanupDisabled = '自动清理已关闭,未删除任何快照'
        diffTitle = '差异预览'
        diffNone = '(无差异)'
        settingsTitle = '快照设置'
        settingsAuto = '自动保存(配置变化自动存档)'
        settingsDebounce = '自动保存防抖(毫秒)'
        settingsKeep = '自动档保留数量'
        settingsKeepPre = '后悔档保留数量'
        settingsCleanup = '自动清理(超量自动删除)'
        settingsManualDir = '手动快照目录'
        settingsAutoDir = '自动快照目录'
        settingsSave = '保存设置'
        settingsCancel = '取消'
        settingsSaved = '设置已保存'
        trayHint = '已最小化到托盘。双击托盘图标恢复窗口。'
        trayOpen = '打开窗口'
        traySave = '手动保存'
        trayUndo = '撤销'
        trayRedo = '恢复'
        trayExit = '退出'
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
        btnCleanup = '🧹 Clean up'
        btnExport = '📦 Export'
        btnImport = '📥 Import'
        btnSettings = '⚙️ Settings'
        colTime = 'Time'; colKind = 'Type'; colStore = 'Store'; colReason = 'Reason'; colFiles = 'Files'
        kindManual = 'Manual'; kindAuto = 'Auto'; kindBaseline = 'Baseline'; kindPre = 'Pre-restore'
        storeManual = 'Manual'; storeAuto = 'Auto'; storeLegacy = 'Legacy'
        statusReady = 'Ready'
        statusCount = '{0} snapshot(s) (newest on top). Double-click a row to view its diff.'
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
        bootBanner = '⚠️ Previous DSH run exited abnormally - consider rolling back to the last good state'
        bootRollback = 'Roll back to the last good state'
        btnSafeMode = 'Safe mode'
        safeModeOnTitle = 'Enable SAFE MODE'
        safeModeOnConfirm = 'All user plugins except the undo system will be temporarily disabled (a snapshot and config backup are taken first). Takes effect after a DSH restart. Continue?'
        safeModeOffTitle = 'Exit SAFE MODE'
        safeModeOffConfirm = 'The full plugin set from before safe mode will be restored. Takes effect after a DSH restart. Continue?'
        safeModeOn = 'Safe mode ON. Restart DSH to boot with only the undo system.'
        safeModeOff = 'Safe mode OFF. Restart DSH to load all plugins again.'
        safeModeFail = 'Safe mode failed: {0}'
        restartRequired = 'Rolled back. A DSH restart is required for the restored state to take effect.'
        exported = 'Exported {0} snapshot(s) → {1}'
        exportFail = 'Export failed: {0}'
        imported = 'Imported {0} snapshot(s) ({1} duplicate(s) skipped)'
        importFail = 'Import failed: {0}'
        cleaned = 'Pruned {0} auto and {1} pre-restore snapshot(s)'
        cleanupDisabled = 'Auto-cleanup is disabled - nothing deleted'
        diffTitle = 'Diff preview'
        diffNone = '(no differences)'
        settingsTitle = 'Snapshot Settings'
        settingsAuto = 'Auto-save (snapshot on config change)'
        settingsDebounce = 'Auto-save debounce (ms)'
        settingsKeep = 'Auto snapshots kept'
        settingsKeepPre = 'Pre-restore snapshots kept'
        settingsCleanup = 'Auto-cleanup (delete excess automatically)'
        settingsManualDir = 'Manual snapshot dir'
        settingsAutoDir = 'Auto snapshot dir'
        settingsSave = 'Save settings'
        settingsCancel = 'Cancel'
        settingsSaved = 'Settings saved'
        trayHint = 'Minimized to tray. Double-click the tray icon to restore.'
        trayOpen = 'Open window'
        traySave = 'Manual save'
        trayUndo = 'Undo'
        trayRedo = 'Redo'
        trayExit = 'Exit'
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
$form.Size = New-Object System.Drawing.Size(1080, 640)
$form.MinimumSize = New-Object System.Drawing.Size(820, 440)
$form.StartPosition = 'CenterScreen'

# crash banner (hidden unless a leftover .booting marker is found)
$banner = New-Object System.Windows.Forms.Panel
$banner.Dock = 'Top'
$banner.Height = 36
$banner.Visible = $false
$banner.BackColor = [System.Drawing.Color]::FromArgb(255, 253, 231, 232)
$bannerLabel = New-Object System.Windows.Forms.Label
$bannerLabel.Text = $script:UI.bootBanner
$bannerLabel.AutoSize = $true
$bannerLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
$bannerLabel.Location = New-Object System.Drawing.Point(10, 10)
$bannerRollback = New-Object System.Windows.Forms.Button
$bannerRollback.Text = $script:UI.bootRollback
$bannerRollback.Width = 170
$bannerRollback.Height = 26
$bannerRollback.Anchor = 'Right'
$bannerRollback.Location = New-Object System.Drawing.Point(($form.Width - 190), 5)
$bannerRollback.Add_Click({ Boot-Rollback })
$banner.Controls.Add($bannerLabel)
$banner.Controls.Add($bannerRollback)

# toolbar
$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Dock = 'Top'
$toolbar.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
$toolbar.Height = 48

function New-ToolButton([string]$Text, [int]$Width, [scriptblock]$OnClick) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Width = $Width
    $btn.Height = 28
    $btn.Add_Click($OnClick)
    return $btn
}

$btnSave = New-ToolButton $script:UI.btnSave 95 { Save-Snapshot }
$btnUndo = New-ToolButton $script:UI.btnUndo 85 { Invoke-QuickUndo 'undo' }
$btnRedo = New-ToolButton $script:UI.btnRedo 85 { Invoke-QuickUndo 'redo' }
$btnRestore = New-ToolButton $script:UI.btnRestore 100 { Restore-Selected }
$btnDelete = New-ToolButton $script:UI.btnDelete 100 { Delete-Selected }
$btnRefresh = New-ToolButton $script:UI.btnRefresh 80 { Update-List }
$btnCleanup = New-ToolButton $script:UI.btnCleanup 95 { Cleanup-Now }
$btnExport = New-ToolButton $script:UI.btnExport 90 { Export-Now }
$btnImport = New-ToolButton $script:UI.btnImport 90 { Import-Now }
$btnSettings = New-ToolButton $script:UI.btnSettings 90 { Show-Settings }
$btnSafeMode = New-ToolButton $script:UI.btnSafeMode 95 { Toggle-SafeMode }
$toolbar.AutoScroll = $true # v0.3.2: window smaller than the toolbar -> scroll instead of hiding buttons

$toolbar.Controls.Add($btnSave)
$toolbar.Controls.Add($btnUndo)
$toolbar.Controls.Add($btnRedo)
$toolbar.Controls.Add($btnRestore)
$toolbar.Controls.Add($btnDelete)
$toolbar.Controls.Add($btnRefresh)
$toolbar.Controls.Add($btnCleanup)
$toolbar.Controls.Add($btnExport)
$toolbar.Controls.Add($btnImport)
$toolbar.Controls.Add($btnSettings)
$toolbar.Controls.Add($btnSafeMode)

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
$colReason = $list.Columns.Add($script:UI.colReason, 340)
$colFiles = $list.Columns.Add($script:UI.colFiles, 60)

# status bar
$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Bottom'
$status.Height = 26
$status.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 0)
$status.Text = $script:UI.statusReady

$form.Controls.Add($list)
$form.Controls.Add($toolbar)
$form.Controls.Add($banner)
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

function Cleanup-Now {
    try {
        $r = Invoke-UndoPrune
        if ($r.disabled) { Set-Status $script:UI.cleanupDisabled } else { Set-Status ($script:UI.cleaned -f $r.removedAuto, $r.removedPre) }
        Update-List
    } catch {
        Set-Status ($script:UI.fail -f $_.Exception.Message)
    }
}

function Export-Now {
    try {
        $r = Export-UndoSnapshots
        if (-not $r.ok) { Set-Status ($script:UI.exportFail -f $r.error); return }
        Set-Status ($script:UI.exported -f $r.count, $r.path)
    } catch {
        Set-Status ($script:UI.exportFail -f $_.Exception.Message)
    }
}

function Import-Now {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'ZIP archives (*.zip)|*.zip|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $r = Import-UndoSnapshots $dlg.FileName
        if (-not $r.ok) { Set-Status ($script:UI.importFail -f $r.error); return }
        Set-Status ($script:UI.imported -f $r.imported, $r.skipped)
        Update-List
    } catch {
        Set-Status ($script:UI.importFail -f $_.Exception.Message)
    }
}

function Show-Diff([string]$Id) {
    $text = Get-UndoDiffText $Id
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$($script:UI.diffTitle) $Id"
    $dlg.Size = New-Object System.Drawing.Size(680, 440)
    $dlg.StartPosition = 'CenterParent'
    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Both'
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.Dock = 'Fill'
    $box.Text = $text
    $dlg.Controls.Add($box)
    $null = $dlg.ShowDialog()
}

function Boot-Rollback {
    # v0.3: roll back to the concrete last-known-good snapshot when known
    $goodId = $script:lastGoodId
    if ($goodId) {
        $r = Invoke-UndoRestore 'id' $goodId
    } else {
        $r = Invoke-UndoRestore 'undo' ''
    }
    if (-not $r.ok) { Set-Status ($script:UI.fail -f $r.error); return }
    if ($r.unchanged) { Set-Status $r.message; return }
    Set-Status ($script:UI.undone -f $r.targetId, $r.preSnapshotId)
    if ($r.needsRestart) { [void][System.Windows.Forms.MessageBox]::Show($script:UI.restartRequired, 'DSH Undo', 'OK', 'Information') }
    Update-List
}

function Toggle-SafeMode {
    # v0.3.2: one-click SAFE MODE in the offline GUI (the tool that saves you
    # when DSH cannot boot at all)
    $st = Get-UndoSafeModeState
    $on = [bool]$st.active
    if ($on) {
        if ([System.Windows.Forms.MessageBox]::Show($script:UI.safeModeOffConfirm, $script:UI.safeModeOffTitle, 'YesNo', 'Warning') -ne 'Yes') { return }
    } else {
        if ([System.Windows.Forms.MessageBox]::Show($script:UI.safeModeOnConfirm, $script:UI.safeModeOnTitle, 'YesNo', 'Warning') -ne 'Yes') { return }
    }
    $r = Set-UndoSafeMode (-not $on)
    if (-not $r.ok) { Set-Status ($script:UI.safeModeFail -f $r.error); return }
    if ($r.active) { Set-Status $script:UI.safeModeOn } else { Set-Status $script:UI.safeModeOff }
}

function Show-Settings {
    $s = Get-UndoSettings
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $script:UI.settingsTitle
    $dlg.Size = New-Object System.Drawing.Size(480, 420)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $y = 14
    $lblAuto = New-Object System.Windows.Forms.Label; $lblAuto.Text = $script:UI.settingsAuto; $lblAuto.SetBounds(16, $y + 4, 300, 20); $dlg.Controls.Add($lblAuto)
    $chkAuto = New-Object System.Windows.Forms.CheckBox; $chkAuto.Checked = $s.autoEnabled; $chkAuto.SetBounds(330, $y, 20, 20); $dlg.Controls.Add($chkAuto)
    $y += 34
    $lblDeb = New-Object System.Windows.Forms.Label; $lblDeb.Text = $script:UI.settingsDebounce; $lblDeb.SetBounds(16, $y + 4, 220, 20); $dlg.Controls.Add($lblDeb)
    $txtDeb = New-Object System.Windows.Forms.TextBox; $txtDeb.Text = [string]$s.watchDebounceMs; $txtDeb.SetBounds(250, $y, 90, 24); $dlg.Controls.Add($txtDeb)
    $y += 34
    $lblKeep = New-Object System.Windows.Forms.Label; $lblKeep.Text = $script:UI.settingsKeep; $lblKeep.SetBounds(16, $y + 4, 220, 20); $dlg.Controls.Add($lblKeep)
    $txtKeep = New-Object System.Windows.Forms.TextBox; $txtKeep.Text = [string]$s.keepAuto; $txtKeep.SetBounds(250, $y, 90, 24); $dlg.Controls.Add($txtKeep)
    $y += 34
    $lblPre = New-Object System.Windows.Forms.Label; $lblPre.Text = $script:UI.settingsKeepPre; $lblPre.SetBounds(16, $y + 4, 220, 20); $dlg.Controls.Add($lblPre)
    $txtPre = New-Object System.Windows.Forms.TextBox; $txtPre.Text = [string]$s.keepPre; $txtPre.SetBounds(250, $y, 90, 24); $dlg.Controls.Add($txtPre)
    $y += 34
    $lblClean = New-Object System.Windows.Forms.Label; $lblClean.Text = $script:UI.settingsCleanup; $lblClean.SetBounds(16, $y + 4, 300, 20); $dlg.Controls.Add($lblClean)
    $chkClean = New-Object System.Windows.Forms.CheckBox; $chkClean.Checked = $s.autoCleanup; $chkClean.SetBounds(330, $y, 20, 20); $dlg.Controls.Add($chkClean)
    $y += 34
    $lblMDir = New-Object System.Windows.Forms.Label; $lblMDir.Text = $script:UI.settingsManualDir; $lblMDir.SetBounds(16, $y + 4, 150, 20); $dlg.Controls.Add($lblMDir)
    $txtMDir = New-Object System.Windows.Forms.TextBox; $txtMDir.Text = [string]$s.manualDir; $txtMDir.SetBounds(170, $y, 270, 24); $dlg.Controls.Add($txtMDir)
    $y += 34
    $lblADir = New-Object System.Windows.Forms.Label; $lblADir.Text = $script:UI.settingsAutoDir; $lblADir.SetBounds(16, $y + 4, 150, 20); $dlg.Controls.Add($lblADir)
    $txtADir = New-Object System.Windows.Forms.TextBox; $txtADir.Text = [string]$s.autoDir; $txtADir.SetBounds(170, $y, 270, 24); $dlg.Controls.Add($txtADir)
    $y += 44
    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = $script:UI.settingsSave; $btnOk.SetBounds(160, $y, 110, 30); $dlg.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = $script:UI.settingsCancel; $btnCancel.SetBounds(280, $y, 90, 30); $dlg.Controls.Add($btnCancel)
    $btnOk.Add_Click({
        try {
            $new = @{
                autoEnabled = $chkAuto.Checked
                autoCleanup = $chkClean.Checked
                watchDebounceMs = [int]$txtDeb.Text
                keepAuto = [int]$txtKeep.Text
                keepPre = [int]$txtPre.Text
                manualDir = $txtMDir.Text.Trim()
                autoDir = $txtADir.Text.Trim()
            }
            Set-UndoSettings $new
            [System.Windows.Forms.MessageBox]::Show($script:UI.settingsSaved, $script:UI.settingsTitle, 'OK', 'Information')
            $dlg.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show(($script:UI.fail -f $_.Exception.Message), $script:UI.settingsTitle, 'OK', 'Error')
        }
    })
    $btnCancel.Add_Click({ $dlg.Close() })
    $null = $dlg.ShowDialog()
}

$list.Add_DoubleClick({ Show-Diff (Get-SelectedId) })

# ── system tray ──────────────────────────────────────────────────────────
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Text = $script:UI.title
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = New-Object System.Windows.Forms.ToolStripMenuItem
$miOpen.Text = $script:UI.trayOpen
$miOpen.Add_Click({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$miSave = New-Object System.Windows.Forms.ToolStripMenuItem
$miSave.Text = $script:UI.traySave
$miSave.Add_Click({ Save-Snapshot })
$miUndo = New-Object System.Windows.Forms.ToolStripMenuItem
$miUndo.Text = $script:UI.trayUndo
$miUndo.Add_Click({ Invoke-QuickUndo 'undo' })
$miRedo = New-Object System.Windows.Forms.ToolStripMenuItem
$miRedo.Text = $script:UI.trayRedo
$miRedo.Add_Click({ Invoke-QuickUndo 'redo' })
$miExit = New-Object System.Windows.Forms.ToolStripMenuItem
$miExit.Text = $script:UI.trayExit
$miExit.Add_Click({ $script:ReallyExit = $true; $notify.Visible = $false; $form.Close() })
$trayMenu.Items.Add($miOpen) | Out-Null
$trayMenu.Items.Add($miSave) | Out-Null
$trayMenu.Items.Add($miUndo) | Out-Null
$trayMenu.Items.Add($miRedo) | Out-Null
$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$trayMenu.Items.Add($miExit) | Out-Null
$notify.ContextMenuStrip = $trayMenu
$notify.Visible = $true
$notify.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })

$script:ReallyExit = $false
$form.Add_Resize({
    if ($form.WindowState -eq 'Minimized') {
        $form.Hide()
        $notify.ShowBalloonTip(2000, $script:UI.title, $script:UI.trayHint, 'Info')
    }
})
$form.Add_FormClosing({
    param($s, $e)
    if (-not $script:ReallyExit) {
        $e.Cancel = $true
        $form.Hide()
        $notify.ShowBalloonTip(2000, $script:UI.title, $script:UI.trayHint, 'Info')
    }
})

$form.Add_Shown({
    Update-List
    $boot = Get-UndoBootAlert
    if ($boot.crashed) {
        # v0.3: remember the concrete last-known-good snapshot for one-click rollback
        $script:lastGoodId = Get-UndoLastGoodId
        $banner.Visible = $true
    }
})
[System.Windows.Forms.Application]::Run($form)
