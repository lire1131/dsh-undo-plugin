# dsh-undo-savepoint Logo 生成提示词

> 用途目录：把下面的提示词（英文为主、中文为备选）粘贴到 image2.0（或任意文生图模型）生成 Logo。
> 产物建议 **1024×1024、透明背景 PNG**，然后：
> - Web 缩略图：主 favicon 用内置 `tools/webui/logo.svg`（最小）；如需用生成的 PNG，才放到 `tools/webui/logo.png`
> - 桌面快捷图标（Windows）：用 `node tools/make-ico.mjs <logo.png> tools/webui/logo.ico` 转成 `.ico` 放 `tools/webui/logo.ico`
>
> 插件已会自动识别：桌面快捷方式优先用 `tools/webui/logo.ico`，没有则回退 `logo.png`，再没有就用系统默认图标；Web 页面主 favicon 用内置 `tools/webui/logo.svg`（最小）；插件内置的 `tools/webui/logo.png`/`logo.ico` 是从该 SVG 栅格化的 64×64 小图标（约 3.4 KB），天然同风格。

---

## 一句话定位（给模型理解概念）

> 一个「配置快照 / 撤销 / 回滚 / 安全恢复」工具 —— 像给配置拍了张可回放的快照，一键回到过去，保护你免于把插件/配置改坏。

---

## 英文提示词（推荐，大多数图像模型理解最好）

```
A modern flat app icon / logo emblem for an undo & snapshot tool named "dsh-undo-savepoint".
Core concept: a subtle rewind / undo arrow (↶) formed from a layered stack of snapshot "cards"
or concentric clock rings, suggesting "time travel to a previous good state".
Design language: minimalist geometric vector mark, clean 2-color palette,
deep teal green (#2f8f83) as the safety/rollback color + a warm amber accent (#f5a623)
for the "snapshot moment", on a soft rounded-square background (radius ~22%).
The mark must read clearly at 16px favicon size: bold central symbol, high contrast,
no tiny details, no fine gradients.
Transparent background, centered single emblem, generous negative space,
no text, no letters, no words, no watermark, no photo-realism, no 3D render,
no drop shadow, no clutter, no extra objects around the mark.
Flat vector style, crisp edges, subtle inner glow optional. Output 1:1 square,
transparent PNG, suitable as both a favicon and a Windows .ico (256x256 master).
```

### 补充：如果模型需要短提示
```
flat minimal logo, undo rewind arrow over layered stack of snapshot cards, teal #2f8f83 + amber #f5a623, rounded square app icon, transparent bg, vector, no text
```

---

## 中文提示词（适合中文文生图模型）

```
现代扁平化「撤销 / 快照」工具 Logo 图标，名字 dsh-undo-savepoint。
核心概念：一个简洁的回退箭头（↶）由多层「快照卡片」堆叠或同心时钟圆环构成，
表达「回到上一个正常状态 / 时间旅行」。
设计语言：极简几何矢量徽标，2 色配色——深青绿 #2f8f83（安全 / 回滚）+ 暖琥珀 #f5a623（快照瞬间），
底部为圆角约为 22% 的圆角方形底色。
即使在 16px favicon 尺寸也要清晰：中央符号粗壮、对比强、无细小细节、无明显渐变。
透明背景，单个居中徽标，留白充足，不包含任何文字 / 字母 / 水印，
不要照片写实、不要 3D、不要投影、不要多余杂物。
扁平矢量风格，边缘锐利，可选轻微内发光。输出 1:1 正方形，透明 PNG，
既能当 favicon 也能转成 Windows .ico（建议 256×256 母版）。
```

### 中文短提示
```
扁平极简logo，回退箭头叠加多层快照卡片，青绿#2f8f83+琥珀#f5a623，圆角方形应用图标，透明背景，矢量，无文字
```

---

## 反向提示（Negative prompt，若有单独输入框）

```
photo, realistic, 3d, gradient overload, text, letters, word, watermark, signature,
clutter, extra objects, drop shadow, heavy outline, noise, grain, low contrast,
tiny detail, mesh, wireframe, blur, duplicate, cropped, off-center
```

---

## 建议参数

| 参数 | 值 | 原因 |
|---|---|---|
| 尺寸 | 1024×1024（或 2048×2048） | 母版一张，可缩放/转 ICO |
| 背景 | 透明（PNG / RGBA） | favicon 与 .ico 需要透明底 |
| 风格 | Flat / Geometric / Vector | 小尺寸仍清晰、与工具类 UI 契合 |
| 图面 | 单个居中符号 | 方形裁剪后仍是完整图标 |
| 颜色 | teal #2f8f83 + amber #f5a623 | 对应「安全回滚 + 快照时刻」语义 |

> 若模型不认颜色 hex，可直接写成「deep teal green and warm amber」。若想要「撤销」语义更强，可把箭头换成「↶」或「时钟回拨」；若想要「快照」语义更强，可强调「层叠卡片 / 分格胶片」。

---

## 生成后如何接入

1. 保存为 `tools/webui/logo.png`（透明底）。
2. 转桌面图标：`node tools/make-ico.mjs tools/webui/logo.png tools/webui/logo.ico`
3. Web 缩略图 PNG 已由 `index.html` 的 favicon 引用；桌面快捷方式会在**下次创建**时自动用 `logo.ico`。
   - 若桌面已有旧快捷方式（`.lnk`），删除它后重新载入插件即可用新图标；或手动删除 `dsh-undo-savepoint.lnk` 让插件重建。
4. `tools/webui/logo.svg` 是我内置的占位矢量图标，未生成 PNG 前 Web 用它兜底。可保留或删除。
