# dsh-undo — DSH 撤销/回退系统

为 DeepSeek Harness (DSH) 打造的撤销/回退系统:**装插件、换皮肤、改设置,保存即自动存档,随时一键撤销/重做**,DSH 启动不了时还有局外脚本兜底,再也不用"卸载重装"。

## 功能一览

| 入口 | 能力 |
|---|---|
| **WebUI 按钮** | 会话头部(对话框上方)「撤销」「恢复」两个按钮,所有会话可见 |
| **键盘快捷键** | 全局快捷键:默认 **Ctrl+Alt+Z**(撤销)/ **Ctrl+Alt+Y**(恢复);可在 **设置 → 通用** 里自定义(点击输入框后按组合键,Backspace 清除) |
| **对话指令** | 对 AI 说"撤销上一步 / 回退 / 恢复",自动调用工具完成 |
| **自动存档** | 配置文件一旦变化(1.5 秒防抖)自动快照;每次启动存基线;自动档保留最近 20 份,手动档永不清理 |
| **手动存档** | `undo_snapshot` 工具 / API,可写原因 |
| **撤销/重做栈** | 支持连续多步撤销;撤销后若无新变更可重做;有新变更则阻止重做(避免覆盖新状态);每次撤销前先把当前状态存为"后悔档" |
| **局外脚本** | `tools\dsh-undo.ps1`:DSH 起不来时也能快照/回退;`tools\dsh-plugin.ps1`:装插件前自动存档、失败自动回退 |

## 快照内容(6 个配置文件)

`cordis.patch.yml`、`package.json`、`cordis.yml`、`pnpm-workspace.yaml`(profile 下)+ `settings.yaml`、`.env`(~/.dsh 下)。

快照仓库:`D:\dsh\undo-snapshots\<id>\`(manifest.json + 文件副本)。**特意放在 ~/.dsh 之外——重装 DSH 不丢**。⚠️ 快照含 `.env` 等配置副本,可能含密钥,不要外传/不要推 GitHub。

## 安装 / 挂载

1. 建立 junction(让 DSH 模块解析器找到本地包;目标目录含中文没问题,junction 名称是 ASCII):

```bat
mklink /J "C:\Users\yzf\node_modules\dsh-undo" "D:\dsh\插件\dsh-undo"
```

2. 在 `C:\Users\yzf\.dsh\profiles\web\cordis.patch.yml` 追加(insert 补丁):

```yaml
- insert:
    - id: dsh-undo
      name: dsh-undo
```

3. 保存即热加载(host 部分);**浏览器刷新页面**后输入框上方出现撤销/恢复按钮(client 部分)。若没生效,重启 DSH(双击 `D:\dsh\日常对话\start-dsh.bat`)。

## 使用

- **撤销上一步**:点会话头部「撤销」按钮,按 `Ctrl+Alt+Z`,或对话里说"撤销上一步"。多点几次可连续回退。
- **恢复**:点「恢复」按钮或按 `Ctrl+Alt+Y`(仅当撤销后没有新操作时可用)。
- **自定义快捷键**:设置 → 通用 → 「撤销快捷键 / 恢复快捷键」,点击输入框后按下组合键;Backspace 清除(设为无快捷键)。保存即时生效。
- **精确回退**:对话里说"列出撤销存档"→ AI 调用 `undo_list` → 说"回退到 <id>"。
- **手动存档**:说"存一个配置存档",或 `dsh-undo.ps1 snapshot -Label "原因"`。
- **差异预览**:说"对比存档 <id> 和现在的区别"。

### 局外工具(DSH 挂了也能用)

```powershell
# 列出所有存档
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" list
# 回退到某存档
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-undo.ps1" restore -Id <id> -Force
# 安全装插件(自动前后存档,失败自动回退)
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dsh\插件\dsh-undo\tools\dsh-plugin.ps1" add <包名>
```

常见事故场景:**启动报 `duplicate loader entry id` 之类错误** → 用局外工具 `list` 找到出问题前的存档 → `restore -Id <id>` → 重启 DSH。不用重装、不丢会话。

## REST API(WebUI 按钮的后端)

| 端点 | 说明 |
|---|---|
| `GET /api/undo/status` | `{canUndo, canRedo, total}` |
| `GET /api/undo/list` | 快照列表 |
| `POST /api/undo/undo` | 撤销上一步 |
| `POST /api/undo/redo` | 恢复 |
| `POST /api/undo/restore` | body `{id}` 精确回退 |
| `POST /api/undo/snapshot` | body `{reason}` 手动存档 |

## 设计要点

- **撤销语义**:自动快照在变更**之后**生成,所以"恢复最新存档"是空操作;真实撤销 = 回退到与当前状态不同的最新存档(即"变更前状态")。实现为:当前状态 == 最新存档时,回退到次新存档。
- **撤销不会撤销掉自己**:恢复 `cordis.patch.yml` 后自动检查并重新写入 dsh-undo 挂载条(insert 形式)。
- **格式互通**:Node 插件与 PS 脚本共用同一快照仓库与 manifest 格式(ps1 写 UTF-8 无 BOM,node 端容错 BOM)。

## 开发

- 依赖解析:host 插件通过 `createRequire('C:/Users/yzf/package.json')` 加载 `@deepseek-ai/dsh-tools`(可用环境变量 `DSH_ROOT` 覆盖),无需 junction 依赖。
- 冒烟测试(不需要 DSH 运行):

```bat
node D:\dsh\插件\dsh-undo\tools\smoke-test.mjs
```

## 投 GitHub

1. 安装 Git:`winget install Git.Git`
2. 在 `D:\dsh\插件\dsh-undo` 内 `git init`,提交(已配 `.gitignore` 排除 node_modules/快照)
3. 仓库加 `#dsh` GitHub topic;README 可保留本文件
