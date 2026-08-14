# dsh-undo — DSH 撤销/回退系统

为 DeepSeek Harness (DSH) 打造的撤销/回退系统:**装插件、换皮肤、改设置,自动保存即存档;手动保存随时存档;一键撤销/恢复/回退到任意版本**,DSH 启动不了时还有局外工具(GUI 窗口 + 命令行)兜底。

## 功能一览

| 入口 | 能力 |
|---|---|
| **WebUI 头部按钮** | 「撤销」(红)「恢复」(绿)「快照」三个按钮,所有会话可见 |
| **快照管理面板** | 「快照」按钮打开:可视化列表(时间/类型/原因/文件数/所在库)、**回退到任意快照版本**、**删除快照**、手动保存、刷新 |
| **键盘快捷键** | 默认 **Ctrl+Alt+Z**(撤销)/ **Ctrl+Alt+Y**(恢复),设置 → 通用 可自定义 |
| **双模式保存** | **手动保存**(主动存档,永不被自动清理)+ **自动保存**(配置变化 1.5 秒防抖自动存档,保留最近 20 份);**两种模式存储位置不同** |
| **可配置参数** | 设置 → 通用 →「快照设置」:自动保存开关、防抖毫秒、自动档保留数量、手动快照目录、自动快照目录,保存即生效 |
| **对话指令** | 说"撤销上一步 / 回退 / 恢复 / 保存快照 / 查看快照",AI 自动调用工具完成 |
| **撤销/重做栈** | 连续多步撤销;撤销后可重做;有新变更则阻止重做;每次撤销前先存"后悔档" |
| **局外工具** | `dsh-undo.ps1`(CLI:snapshot/undo/redo/restore/remove/list/diff/prune/status)+ **`dsh-undo-gui.ps1` 程序窗口**(桌面「DSH 撤销管理器」快捷方式)+ `dsh-plugin.ps1`(安全装插件) |

## 存储位置(手动/自动分开)

| 库 | 默认路径 | 内容 |
|---|---|---|
| 手动库 | `D:\dsh\undo-snapshots\manual\` | 手动保存的快照(永不自动清理) |
| 自动库 | `D:\dsh\undo-snapshots\auto\` | 自动快照、启动基线、撤销后悔档(自动档保留最近 20 份) |
| 旧库(兼容) | `D:\dsh\undo-snapshots\` 根 | 旧版扁平布局,读取兼容,启动时自动迁移到新库 |

⚠️ 快照含 `.env` 等配置副本,可能含密钥——不要外传/推 GitHub(已加入 .gitignore 之外,注意整个目录别打包分享)。

## 快照内容(6 个配置文件)

`cordis.patch.yml`、`package.json`、`cordis.yml`、`pnpm-workspace.yaml`(profile 下)+ `settings.yaml`、`.env`(~/.dsh 下)。

## 安装 / 挂载

1. 建立 junction(让 DSH 模块解析器找到本地包):

```bat
mklink /J "C:\Users\yzf\node_modules\dsh-undo" "D:\dsh\插件\dsh-undo"
```

2. 在 `C:\Users\yzf\.dsh\profiles\web\cordis.patch.yml` 追加:

```yaml
- insert:
    - id: dsh-undo
      name: dsh-undo
```

3. 保存即热加载(host);刷新页面出现按钮;重启后一切进入稳态。

## 使用

- **撤销**:头部「撤销」按钮 / `Ctrl+Alt+Z` / 对话说"撤销上一步"。
- **恢复**:「恢复」按钮 / `Ctrl+Alt+Y`(仅当撤销后没有新操作)。
- **手动保存**:面板里「手动保存」/ 对话说"保存快照" / CLI `snapshot`。
- **回退到指定版本**:面板里点快照行「回退到此版本」;或对话"回退到 <id>";或 CLI `restore -Id <id>`。
- **删除快照**:面板里点「删除」;或 CLI `remove -Id <id>`。
- **自定义快捷键**:设置 → 通用 → 撤销/恢复快捷键(点击输入框后按组合键,Backspace 清除)。
- **保存参数**:设置 → 通用 → 快照设置(自动保存开关、防抖、保留数、两个目录)。

### 局外工具(DSH 挂了也能用)

```powershell
# 程序窗口(推荐):双击桌面「DSH 撤销管理器」,或:
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo-gui.ps1"

# 命令行
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" list
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" snapshot -Label "原因"
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" undo
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" redo
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" restore -Id <id> -Force
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" remove -Id <id>
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" prune -KeepAuto 20

# 安全装插件(自动前后存档,失败自动回退)
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-plugin.ps1" add <包名>
```

常见事故场景:**启动报 `duplicate loader entry id` 之类错误** → 打开「DSH 撤销管理器」选中出问题前的快照 → 回退 → 重启 DSH。不用重装、不丢会话。

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

## 设计要点

- **撤销语义**:自动快照在变更**之后**生成,所以"恢复最新存档"是空操作;真实撤销 = 回退到与当前状态**内容不同**的最新快照;全部相同则明确提示"没有可撤销的变化"。
- **撤销不会撤销掉自己**:恢复 `cordis.patch.yml` 后自动检查并重新写入 dsh-undo 挂载条。
- **自动存档不误伤撤销**:watcher 记录恢复操作写入的内容哈希,恢复动作自己的文件变化不会被自动存档(否则会挡住 redo);真实变更照常存档。
- **格式互通**:Node 插件与 PS 工具共用快照仓库与 manifest 格式;PS 5.1 与 PowerShell 7 均兼容(ps1 无中文、GUI 带 BOM)。

## 开发

- 依赖解析:host 插件通过 `createRequire('C:/Users/yzf/package.json')` 加载 `@deepseek-ai/dsh-tools`(环境变量 `DSH_ROOT` 可覆盖)。
- 测试(不需要 DSH 运行):

```bat
node D:\dsh\插件\dsh-undo\tools\smoke-test.mjs     :: 29 项逻辑测试
node D:\dsh\插件\dsh-undo\tools\e2e-watch.mjs      :: 6 项真实时序回归(自动存档/撤销/重做)
```

## 投 GitHub

1. 本机 Git 已装(2.55);仓库已 `git init` + 初始提交。
2. 发布前把 `git config user.name/email` 改成自己的。
3. 仓库加 `#dsh-plugin`、`#dsh` GitHub topic。
