# 更新日志

dsh-undo-savepoint 的重要变更。日期为本地时间(UTC+8)。English version: [CHANGELOG.en.md](CHANGELOG.en.md)

## [Unreleased]

### 新增
- **快照入口相机图标**：会话头部「快照」按钮与快照管理面板标题新增官方填充式风格的相机图标（16×16 单色 `currentColor`，机身轮廓 + 取景器凸起 + 镜头圆环，随主题色自适应；`CameraIcon` 组件可复用）

## [0.3.3] - 2026-08-16

### 新增
- **多 profile 支持**（issue #3）：从 `process.argv` 解析当前 profile（`--profile mine` / `--profile=mine`，`dsh web` 回退 `web`），`config.profileName` 可显式覆盖
  - `profileDir` 默认改为当前 profile 目录（此前硬编码 `web`——非 web profile 下快照读错、watcher 漏监听、恢复写错位置）
  - 快照仓库按 profile 隔离：`<快照根>/<profileName>/{auto,manual}`；兼容旧数据——profile 作用域目录不存在而旧平铺目录存在时自动回退平铺（不隐身旧快照）
  - manifest 增加 `profile` 字段，`undo_list` 显示当前 profile
  - 离线 CLI/GUI 同步：`DSH_UNDO_PROFILE` 环境变量或 settings `profileName` 指定（离线无法看到 argv）
  - 显式配置（`profileDir` / `manualDir` / `autoDir` / `profileName`）优先级不变
- **ps1 离线工具支持 `DSH_UNDO_ROOT` / `DSH_UNDO_SETTINGS` 环境变量**（与 Node 插件对齐；此前 ps1 只认默认路径，自定义库用户离线工具会错位）
- **package.json 声明 `dsh.runtime: "host"`**（WhaleHarness 审计门槛：使用 child_process 必须声明 host runtime）

### 修复
- settings.json 默认位置迁移兼容：旧位置（如 `D:\dsh\undo\settings.json`）配置的数据不再"隐身"——新位置读取后按配置目录继续工作

### 测试
- smoke 98 → 101（argv 解析 / manifest profile 字段 / 显式 profileName 覆盖）；e2e 10/10

## [0.3.2] - 2026-08-15

### 新增
- **敏感信息脱敏 + 本机 vault**（默认开启）：`.env` 与 `.credentials.yaml` 进快照时值替换为 `***REDACTED***`（键名/export/引号/注释/结构全保留），快照与导出 ZIP 可自由外传零泄露；真实值存本机 vault（`<autoDir>/env-vault/`，内容寻址），**本机回滚完整还原含值**，换机回滚得到占位 + 提示填写
  - `sensitiveMode` 设置：`redact`（默认）/ `keep`（明文旧行为）；旧快照自动兼容
  - **diff 两侧都脱敏**（快照侧与当前侧，含旧快照明文），界面永不出现真实值
- **`.credentials.yaml` 纳入快照范围**（此前不在——DSH 真凭据文件损坏时局内外都救不了）
- **局外急救补齐**（DSH 挂了也能救全）：
  - **GUI 崩溃横幅升级**：读 boot-state.json（旧逻辑查已废弃的 .booting，v0.3 后失效已修复），显示 last-good 快照 + 一键回退到该快照
  - **GUI 一键安全模式按钮**（on/off 确认框）；**GUI 标题栏显示当前敏感模式**
  - **CLI 新增 `recent` 命令**：查看回滚日志（WebUI 的 undo_recent 对等能力）
  - **CLI `settings -Label "key=value;..."`**：离线修改设置（此前只读）
  - **CLI undo/redo/restore 输出增强**：needsRestart / 跨机 preflight 警告 / 脱敏占位 Note 提示
- **WebUI 设置独立侧栏栏目**：「快照」栏目一页展示全部设置（不再挤在"通用"里），含敏感模式下拉、插件目录白名单、目录 📁 选择
- **设置双端同步修复**：ps1 补读 keepPre/autoCleanup（此前 GUI 打开显示为空并覆盖 WebUI 值）；GUI 目录选择用「浏览」按钮
- **孤儿 blob 清理**：`undo_prune` / 清理过期顺带删除"无任何快照引用"的插件代码 blob（跨机导入残留不再占空间）
- **导出敏感警告**：keep 模式或旧快照含明文敏感文件时，导出（对话/WebUI/CLI）明确警告"包含真实密钥,请勿外传"
- **`undo_list` 显示敏感模式**：附当前模式 + 最近快照脱敏文件数

### 修复
- ps1 `Get-UndoBootAlert` 升级为读 boot-state.json（含 lastGoodAt），新增 `Get-UndoLastGoodId`
- GUI 工具栏 11 按钮溢出被列表遮挡（两行排列 + 单实例 Mutex 防重复后台）
- diff 泄露：当前文件侧明文直接显示（如 `DEEPSEEK_API_KEY: sk-...`）——两侧统一脱敏

### 测试
- smoke 76 → 98（脱敏规则各形态 / vault 本机完整恢复 / 换机占位 / diff 双侧零泄露 / keep 明文 / 孤儿 blob 清理 / 旧快照兼容）；e2e 10/10

## [0.3.1] - 2026-08-15

### 新增
- **跨机一致性预检**:恢复(undo/redo/restore)时自动扫描目标快照引用的插件(patch 挂载条目 + package.json bundles),本机解析不到的**明确列出并提示**"恢复后可能启动失败",建议先装插件或安全模式启动
  - 多锚点探测(用户 node_modules / profile 依赖树 / 插件位置链),任一可解析即视为已装,避免 junction 布局误报
  - 本地文件条目(`name: './xxx'`)不探测;预检结果写入回滚日志
- **docs/migration 双语文档**:跨机迁移行为说明(插件代码不会塞入目标机、blob 残留、patch 缺插件的坑)+ 最佳实践,中英双语

### 修复
- `toolsRequire` 从块级作用域提升为模块级(此前外部函数引用会被 try/catch 静默吞掉 ReferenceError,预检的多锚点解析依赖它)

## [0.3.0] - 2026-08-15

### 新增（兜底三件套：崩溃归因 + 安全模式 + 重启联动，第 2 期）
- **崩溃归因升级**:`.booting` 标记升级为 `boot-state.json`,记录每次启动的结果与"最后正常启动时间";上次异常退出时,`undo_list` 与 WebUI 直接给出**具体的最后正常快照 id 与一键回退按钮**,不再只说"上次崩溃了"
- **一键安全模式**:`undo_safe_mode` 工具(对话可直接用)+ WebUI 快照面板「安全模式」按钮 + 离线 CLI `safe-mode on|off|status`——进入时自动手动快照并备份 `cordis.patch.yml`,把 patch 最小化(只留撤销系统),保证 DSH 一定能启动;退出时恢复原配置。DSH 完全起不来时的终极兜底
- **重启联动**:undo/redo/restore 涉及插件代码或挂载配置时,报告与 WebUI 明确提示"重启 DSH 后生效",回滚日志同步记录

## [0.2.1] - 2026-08-15

### 新增
- **一键桌面快捷方式**:`tools/make-desktop-shortcut.bat`(双击)/ `.ps1`(命令行)自动定位插件目录,在桌面创建「DSH撤销管理器」快捷方式——解决"装完找不到局外工具"
- **README 新增「局外工具在哪」章节**:写明两种安装方式的工具路径 + 一段无需先找文件的一行命令(自动定位并创建快捷方式)+ 打开工具目录命令

### 修复
- 澄清包名/仓库名差异:安装命令写 `dsh-undo-plugin`,装好后目录名是**包名 `dsh-undo-savepoint`**——按仓库名找目录必然找不到,README 已标注

## [0.2.0] - 2026-08-15

### 新增（插件代码级撤销，第 1 期）
- **插件代码树快照**:自动发现用户插件(`node_modules` 下的 junction,如 `D:\dsh\plugins\*`)与 profile 本地代码文件(`cordis.patch.yml` 里 `name: './xxx'` 引用的 `router-global.mjs` 等),插件代码被改坏也能撤销——配置没变也能撤(如 whale-kit "yield* is not async iterable" 这类纯代码事故)
- **体积 4 道保险**:扩展名白名单(只收 `.js/.mjs/.cjs/.ts/.json/.yml` 等代码文件,资源如 gif/png 不进快照,实测 pet 57MB→47KB)、内容寻址 blob 库去重(`<快照根>/blobs`,没变的文件零拷贝)、单文件/单快照上限(超限记录 skipped)、按引用恢复(缺失明确报告)
- **插件文件 diff**:`undo_diff` 与 WebUI 差异预览显示 `plugin:xxx` / `profile:xxx` 条目
- **插件 watcher**:插件代码目录变化自动快照(`plugin-code-change`),恢复动作自身不误伤(echo 检测)
- **单一清单 `lib/spec.json`**:快照范围 Node 与 PowerShell 共用一份配置,不再双写漂移
- **`pluginDirs` 设置**:可显式指定插件目录白名单(空数组 = 关闭自动发现,测试/隔离用)
- **导出/导入含 blob 库**:ZIP 备份迁移后 restore 不缺内容
- 快照 manifest 记录插件名/版本/跳过项;`undo_list` 显示插件文件数;恢复报告列出未恢复项(missing)

### 修复
- 旧快照(无 plugins 字段)在 PowerShell 离线工具下被 `@($null)` 单元素数组污染状态与 diff(过滤空值)
- 离线 CLI diff 分支改用统一实现(Get-UndoDiffText),支持插件文件
- ps1 文件统一 UTF-8 BOM,PowerShell 5.1 正确解析中文注释

## [0.1.1] - 2026-08-15

### 新增
- **回滚事件日志**:每次 undo / redo / restore 成功后追加一条 JSON 记录(时间、模式、目标快照、被回滚的文件),保留最近 100 条
- **`undo_recent` 工具**:随时查看最近的回滚操作,排查"配置怎么突然变了"——回滚可能发生在其他会话或离线工具里
- **提示词规则 7**:用户对配置状态困惑时,AI 先调 `undo_recent` 确认是否为回滚所致

## [0.1.0] - 2026-08-14

### 新增
- **自动快照 + 手动快照分库存储**(`manual` / `auto`):配置每次变更自动存档(1.5 秒防抖),启动生成 baseline;手动快照永不自动清理
- **undo / redo / 恢复到任意版本**:pre-restore 重做点机制,存在更新的真实变更时禁止 redo
- **快照管理面板**:逐条 diff 预览、恢复前变更摘要确认、删除、清理、导出 / 导入(ZIP 备份迁移)
- **WebUI 撤销/重做/快照按钮 + 全局快捷键**(Ctrl+Alt+Z / Ctrl+Alt+Y,可自定义)
- **崩溃自检**:上次 DSH 未正常启动时提示,可一键回滚
- **主动告知**:配置变更后 AI 提示"已自动保存,随时可撤销"
- **离线 CLI + GUI v2**:DSH 启动不了也能用(快照/撤销/回退/diff/清理/导出导入/设置/托盘)
- **双语 GUI**(系统语言自动检测,`DSH_UNDO_LANG` 可覆盖)
- **dsh.bundle 生态安装**:`dsh plugin add github:lire1131/dsh-undo-plugin#master`
- 设置项:自动保存开关、防抖、保留数量、自动清理、快照目录(原生文件夹选择器)

### 变更
- 插件由 `dsh-undo` 更名为 **`dsh-undo-savepoint`**
- 依赖解析不再硬编码作者路径(基于插件位置解析,回退 `$DSH_ROOT`)
- 默认存储/设置基于用户主目录;旧版平铺存储自动迁移到分库结构

### 修复
- 硬编码作者路径导致其他机器启动失败(issue #1)
- undo/redo 被监听器自身写入的自动快照误拦(内容哈希回显检测)
- prune 从未真正执行,自动快照无限堆积;保留上限现在真正生效
- 双加载 bug(社区反馈):bundle 安装不再追加手动挂载,并清理历史遗留
- README 安装命令指向错误仓库名

## [0.0.1] - 2026-08-14

本地原型:配置变更快照 + undo / redo,后并入 0.1.0。
