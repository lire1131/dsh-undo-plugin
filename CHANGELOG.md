# 更新日志

dsh-undo-savepoint 的重要变更。日期为本地时间(UTC+8)。English version: [CHANGELOG.en.md](CHANGELOG.en.md)

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
