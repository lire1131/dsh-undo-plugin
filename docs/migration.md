# 跨机迁移说明

> 场景：在 A 电脑导出快照 ZIP → 拷到 B 电脑导入 → 在 B 上回滚到某个快照。
> English: [migration.en.md](migration.en.md)

---

## 一、会发生什么

### 1. 配置文件：正常恢复
快照里的 6 类配置文件（cordis.patch.yml / package.json / settings.yaml 等）会原样写回 B 的对应位置。

### 2. 插件代码文件：**不会**被塞进 B（v0.2 起）
快照包含插件代码树（blob 引用），但恢复时有一道**硬校验**（liveDirs 检查）：

- B 没装那个插件 → 整个插件条目跳过，**零写入**，恢复报告列出 "directory no longer present"；
- B 装了同名插件 → 插件代码会被覆盖成 A 快照时的版本（恢复 = 把 B 变成 A 当时的状态，请知悉）。

### 3. blob 残留：只占空间，不写文件
导出/导入会把 A 的插件代码 blob 一起带过去（为保证恢复可用而设计）。导入后只占磁盘空间，**不会被自动写回任何文件**。

### 4. 真正的坑：patch 引用了 B 没有的插件 → 启动报错
快照里的 `cordis.patch.yml` 会原样恢复。如果它挂载了 A 的插件而 B 没装 → DSH 启动时 loader 加载失败（MODULE_NOT_FOUND）。

**跨机恢复的本质 = 把 B 的配置变成 A 的样子，B 必须装齐 A 的插件才能正常启动。** 这不是插件代码树功能引入的新问题，恢复配置本来就会这样。

---

## 二、跨机一致性预检（v0.4 起，自动提示）

恢复时自动扫描目标快照引用的插件（patch 挂载条目 + package.json bundles），探测本机能否解析。缺失时恢复报告明确提示：

```
⚠️ Cross-machine preflight: referenced but NOT resolvable on this machine: dsh-xxx
DSH may fail to start after restore — install them first, or use undo_safe_mode action "on" ...
```

- 本地文件条目（`name: './xxx'`）不探测；
- 多锚点探测（用户 node_modules / profile 依赖树 / 插件位置链），任一可解析即视为已装，避免误报；
- 预检只提示不阻断（第 1 期）；跳过缺失挂载的自动恢复为后续版本规划。

## 三、最佳实践

| 步骤 | 操作 |
|---|---|
| 1 | A 上「导出」快照 ZIP |
| 2 | **B 上先装齐 A 的插件**（`dsh plugin --profile web add <插件>`），再导入 ZIP |
| 3 | B 上恢复，注意预检提示 |
| 4 | 启动失败？**安全模式兜底**：`undo_safe_mode on` → DSH 一定能启动 → 再决定装插件或回退 |
