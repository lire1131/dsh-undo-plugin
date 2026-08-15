# dsh-undo-savepoint — DSH 撤销/回退系统

[![awesome · DSH plugin](https://awesome-dsh-plugin.com/badge.svg)](https://awesome-dsh-plugin.com)

> 中文 | [English](README.en.md) | [更新日志](CHANGELOG.md)

**还在为 DSH 崩溃而苦恼?还在担心小改动会带来大灾难?这款工具能帮到你!**

为 [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) 打造的撤销/回退系统:**装插件、换皮肤、改设置,自动保存即存档;手动保存随时存档;一键撤销/恢复/回退到任意版本**,DSH 启动不了时还有局外工具(GUI 窗口 + 命令行)兜底。

## 预览

| WebUI 快照管理面板(差异/回退/删除/清理/导出/导入/安全模式) | WebUI 设置「快照」独立栏目(敏感模式/插件白名单/目录选择) |
|---|---|
| ![panel](docs/webui-panel.png) | ![settings](docs/webui-settings-section.png) |

| 局外程序窗口(两行工具栏 + 安全模式按钮,DSH 挂了也能用) | 局外设置对话框(敏感模式/浏览选目录) |
|---|---|
| ![gui](docs/gui-main.png) | ![guisettings](docs/gui-settings.png) |

| 安全模式确认(进入/退出) | 安全模式状态提示 |
|---|---|
| ![confirm](docs/safe-mode-confirm.png) | ![done](docs/safe-mode-done.png) |

## 功能一览

| 入口 | 能力 |
|---|---|
| **WebUI 头部按钮** | 「撤销」(红)「恢复」(绿)「快照」三个按钮,所有会话可见 |
| **快照管理面板** | 可视化列表(时间/类型/原因/文件数/所在库)、**每行差异预览**(增删行高亮)、**回退到任意快照版本**(回退前确认框显示将修改的文件摘要)、**删除快照**、手动保存、清理过期、刷新 |
| **键盘快捷键** | 默认 **Ctrl+Alt+Z**(撤销)/ **Ctrl+Alt+Y**(恢复),设置 → 通用 可自定义 |
| **双模式保存** | **手动保存**(主动存档,永不被自动清理)+ **自动保存**(配置变化 1.5 秒防抖自动存档,保留最近 20 份);**两种模式存储位置不同** |
| **可配置参数** | 设置 → 通用 →「快照设置」:自动保存开关、防抖毫秒、自动档保留数量、**后悔档保留数量、自动清理开关**、手动快照目录、自动快照目录,保存即生效 |
| **自动清理** | 超量自动删除:自动档保留最近 N 份、后悔档保留最近 M 份(已消费的优先清),手动存档永不清除;可设置关闭(关闭后全部保留),面板可手动「清理过期」 |
| **对话指令** | 对 AI 说"撤销上一步 / 回退 / 恢复 / 保存快照 / 查看快照",自动调用工具完成;配置变更时 AI 会主动提示"已自动存档,随时可撤销" |
| **撤销/重做栈** | 连续多步撤销;撤销后可重做;有新变更则阻止重做;每次撤销前先把当前状态存为"后悔档" |
| **插件代码级撤销**(v0.2) | 快照包含用户插件代码树(`D:\dsh\plugins\*` 与 profile 本地代码文件),**插件代码被改坏也能一键撤销**(如 yield\* 这类纯代码事故);内容寻址 blob 去重,体积 4 道保险(白名单/去重/上限/按引用恢复) |
| **跨机一致性预检**(v0.3.1) | 恢复时自动扫描快照引用的插件,本机没装的**明确列出并提示**(多锚点探测防误报);配合 [docs/migration.md](docs/migration.md) 跨机迁移指南 |
| **敏感信息脱敏**(v0.3.2) | `.env` / `.credentials.yaml` 进快照时值替换为 `***REDACTED***`(结构全保留),快照与导出 ZIP **可自由外传零泄露**;真实值存本机 vault,**本机回滚完整还原**,换机回滚占位+提示;`sensitiveMode` 可切 `keep` 明文 |
| **局外急救全齐**(v0.3.2) | GUI:崩溃横幅(last-good 一键回退)+ **安全模式按钮**;CLI:`recent` 回滚日志、`settings -Set` 离线改设置、恢复输出 needsRestart/预检/脱敏提示——**DSH 挂了该有的急救都有** |
| **崩溃归因**(v0.3) | 上次异常退出时,**直接给出具体的"最后正常快照"id 与一键回退按钮**,不再只说"上次崩溃了" |
| **一键安全模式**(v0.3) | 除撤销系统外临时禁用所有用户插件,保证 DSH 一定能启动;进入自动快照+备份配置,退出恢复原样;对话工具 / WebUI 按钮 / 离线 CLI 均可 |
| **重启联动**(v0.3) | 撤销涉及插件代码或挂载配置时,明确提示"重启 DSH 后生效" |
| **启动异常自检** | 上次 DSH 崩溃/被杀未正常启动时,启动后自动检测并在快照列表与面板顶部警告,引导你回退到上次正常状态 |
| **导出/导入** | 一键把全部快照打包为 ZIP(备份/换机迁移);导入自动按类型分流、重复跳过不覆盖;面板按钮 / 对话工具 / 离线 CLI 均可 |
| **桌面快捷方式**(v0.2.1) | 双击 `tools/make-desktop-shortcut.bat`,桌面一键生成「DSH撤销管理器」快捷方式,不再担心"装完找不到局外工具" |
| **局外工具** | CLI(`snapshot/undo/redo/restore/remove/list/diff/prune/export/import/status/safe-mode`)+ **程序窗口 v2**(启动异常自检横幅与一键回退、导出/导入、双击行差异预览、清理过期、设置面板、系统托盘常驻)+ 安全装插件包装器 |

## 崩溃急救速查（按场景选工具）

| 场景 | 操作 |
|---|---|
| 配置/插件被改坏 | 对话/WebUI/CLI:`undo` 或 `restore -Id <id>` |
| 插件代码被改坏 | 同上(快照含插件代码树,一键还原) |
| 上次异常退出,不知回退到哪 | WebUI 横幅 / GUI 横幅 显示 last-good 快照,一键回退 |
| **DSH 完全起不来** | 桌面「DSH撤销管理器」→ **安全模式**按钮(或 CLI `safe-mode -Label on`)→ 重启 DSH 保证能启动 |
| 恢复后可能缺插件(跨机) | 恢复报告预检提示;先装插件或安全模式 |
| 配置"突然变了" | CLI `recent` / 对话 `undo_recent` 查回滚日志 |
| 撤销涉及插件/挂载 | 报告提示"重启 DSH 后生效" |

## 快照内容与存储

快照对象是 DSH 的 6 个配置文件:`cordis.patch.yml`、`package.json`、`cordis.yml`、`pnpm-workspace.yaml`(profile 下)+ `settings.yaml`、`.env`(~/.dsh 下)。

| 库 | 默认路径(可在设置中修改) | 内容 |
|---|---|---|
| 手动库 | `<快照根>\manual\` | 手动保存的快照(永不自动清理) |
| 自动库 | `<快照根>\auto\` | 自动快照、启动基线、撤销后悔档(自动档保留最近 20 份) |
| 旧库(兼容) | `<快照根>\` 根 | 旧版扁平布局,读取兼容,启动时自动迁移到新库 |

> ⚠️ 快照含 `.env` 等配置副本,可能含密钥——不要外传。

## 安装

前置:已安装 DSH(`@deepseek-ai/dsh`)与 Node.js(≥20)。

**方式 A(推荐,生态标准一条命令)** — 本插件已声明 `dsh.bundle` manifest,可直接用官方插件命令安装:

```bat
dsh plugin --profile web add github:lire1131/dsh-undo-plugin#master
```

安装完成后重启 DSH 即生效(快照目录、参数等均可在设置中修改)。

**方式 B(本地源码/免发布)** — clone 到本地目录并手工挂载:

1. **把仓库放到本地插件目录**(无中文路径更稳妥),例如 `D:\dsh\plugins\dsh-undo-savepoint`:

```bat
git clone https://github.com/lire1131/dsh-undo-plugin.git D:\dsh\plugins\dsh-undo-savepoint
```

2. **建立 junction**,让 DSH 的模块解析器通过包名 `dsh-undo-savepoint` 找到本地源码(host 插件与 WebUI client 插件都靠它):

```bat
mklink /J "<你的DSH安装>\node_modules\dsh-undo-savepoint" "D:\dsh\plugins\dsh-undo-savepoint"
```

> 说明:DSH 从它自己的 `node_modules` 向上解析包名。默认安装位置是 `C:\Users\<用户名>\node_modules`(npm 安装在用户目录时);若用 npx 缓存运行,则对 npx 缓存目录下的 `node_modules` 建 junction。执行 `npm root -g` / 检查 DSH 启动报错路径即可确认。

3. **挂载到 profile 补丁层**:编辑 `<DSH_HOME>\profiles\web\cordis.patch.yml`,追加:

```yaml
- insert:
    - id: dsh-undo-savepoint
      name: dsh-undo-savepoint
```

4. **生效**:保存即热加载(host 部分);刷新页面出现头部按钮与设置项;重启 DSH 后一切进入稳态(旧版扁平快照会自动迁移)。

> 依赖说明:host 插件通过 `createRequire('<DSH安装根>/package.json')` 加载 `@deepseek-ai/dsh-tools`。若 DSH 安装在其他位置,设置环境变量 `DSH_ROOT=<DSH安装根>` 即可,无需额外安装依赖。

## 局外工具在哪(装完找不到?)

局外撤销工具(GUI 窗口 + 命令行)**不装到桌面,而是随插件装在安装目录里**:

| 安装方式 | 工具位置 |
|---|---|
| 方式 A:`dsh plugin add` | `C:\Users\<你的用户名>\.dsh\profiles\web\node_modules\dsh-undo-savepoint\tools\` |
| 方式 B:clone + junction | 你 clone 的目录 `...\dsh-undo-savepoint\tools\` |

> ⚠️ 注意:安装命令里的仓库名是 `dsh-undo-plugin`,但装好后目录名是**包名 `dsh-undo-savepoint`**——按"仓库名"去找目录是找不到的。

**一键创建桌面快捷方式(推荐,以后从桌面直接打开):**

双击 `tools\make-desktop-shortcut.bat`(它会自动定位插件目录),桌面出现「DSH撤销管理器」图标;
或者把下面整段复制到 PowerShell 窗口回车(无需先找文件,自动定位):

```powershell
$d = @("$env:USERPROFILE\.dsh\profiles\web\node_modules\dsh-undo-savepoint", "$env:USERPROFILE\.dsh\profiles\node_modules\dsh-undo-savepoint", "$env:USERPROFILE\node_modules\dsh-undo-savepoint") | Where-Object { Test-Path (Join-Path $_ 'tools\dsh-undo-savepoint-gui.bat') } | Select-Object -First 1
if ($d) {
  $w = New-Object -ComObject WScript.Shell
  $s = $w.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'DSH撤销管理器.lnk'))
  $s.TargetPath = Join-Path $d 'tools\dsh-undo-savepoint-gui.bat'
  $s.WorkingDirectory = Join-Path $d 'tools'
  $s.Save()
  Write-Host "已创建桌面快捷方式:$($s.FullName)"
} else { Write-Host '未找到插件目录,请先安装:dsh plugin --profile web add github:lire1131/dsh-undo-plugin#master' }
```

**只想打开工具目录看一眼:**

```powershell
explorer "$env:USERPROFILE\.dsh\profiles\web\node_modules\dsh-undo-savepoint\tools"
```

之后双击桌面「DSH撤销管理器」即可打开局外工具(DSH 崩溃、启动不了时也能用)。

## 使用

- **撤销**:头部「撤销」按钮 / `Ctrl+Alt+Z` / 对 AI 说"撤销上一步"。
- **恢复**:「恢复」按钮 / `Ctrl+Alt+Y`(仅当撤销后没有新操作)。
- **手动保存**:面板里「手动保存」/ 对 AI 说"保存快照" / CLI `snapshot`。
- **回退到指定版本**:面板里点快照行「回退到此版本」;或对 AI 说"回退到 <id>";或 CLI `restore -Id <id>`。
- **删除快照**:面板里点「删除」;或 CLI `remove -Id <id>`。
- **自定义快捷键**:设置 → 通用 → 撤销/恢复快捷键(点击输入框后按组合键,Backspace 清除)。
- **保存参数**:设置 → 通用 → 快照设置(自动保存开关、防抖、保留数、两个目录,目录旁 📁 按钮可打开系统目录选择器)。

### 局外工具(DSH 挂了也能用)

> 界面语言:程序窗口按系统 UI 语言自动显示中文/英文;可用环境变量 `DSH_UNDO_LANG=zh|en` 强制指定。

进入仓库目录后:

```powershell
# 程序窗口(推荐):双击 tools\dsh-undo-savepoint-gui.bat,或:
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint-gui.ps1"

# 命令行
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" list
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" snapshot -Label "原因"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" undo
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" redo
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" restore -Id <id> -Force
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" remove -Id <id>
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-undo-savepoint.ps1" prune -KeepAuto 20

# 安全装插件(自动前后存档,失败自动回退)
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\dsh-plugin.ps1" add <包名>
```

常见事故场景:**DSH 启动报 `duplicate loader entry id` 之类错误** → 打开「DSH 撤销管理器」选中出问题前的快照 → 回退 → 重启 DSH。不用重装、不丢会话。

## REST API(WebUI 的后端)

| 端点 | 说明 |
|---|---|
| `GET /api/undo/status` | `{canUndo, canRedo, total}` |
| `GET /api/undo/list` | 快照列表(含 location: manual/auto/legacy) |
| `GET/POST /api/undo/settings` | 读/写保存参数(自动保存、防抖、保留数、目录),POST 即时生效 |
| `POST /api/undo/undo` | 撤销上一步 |
| `POST /api/undo/redo` | 恢复 |
| `POST /api/undo/restore` | body `{id}` 回退到指定版本 |
| `POST /api/undo/remove` | body `{id}` 删除快照 |
| `POST /api/undo/snapshot` | body `{reason}` 手动保存 |
| `POST /api/undo/pick-dir` | 弹出系统目录选择器,返回选中路径 |

## 设计要点

- **撤销语义**:自动快照在变更**之后**生成,所以"恢复最新存档"是空操作;真实撤销 = 回退到与当前状态**内容不同**的最新快照;全部相同则明确提示"没有可撤销的变化"。
- **撤销不会撤销掉自己**:恢复 `cordis.patch.yml` 后自动检查并重新写入 dsh-undo-savepoint 挂载条。
- **自动存档不误伤撤销**:watcher 记录恢复操作写入的内容哈希,恢复动作自己的文件变化不会被自动存档(否则会挡住 redo);真实变更照常存档。
- **格式互通**:Node 插件与 PowerShell 工具共用快照仓库与 manifest 格式;Windows PowerShell 5.1 与 PowerShell 7 均兼容。

## 开发

- 依赖解析:host 插件通过 `createRequire(<DSH安装根>/package.json)` 加载 `@deepseek-ai/dsh-tools`(环境变量 `DSH_ROOT` 可覆盖),无需在仓库内安装依赖。
- 测试(不需要 DSH 运行,在仓库目录执行):

```bat
node tools\smoke-test.mjs     :: 29 项逻辑测试(快照/撤销/重做/存储分流/无变化提示)
node tools\e2e-watch.mjs      :: 6 项真实时序回归(自动存档/撤销不误伤/重做)
```
