# IMDSH 设计说明（对齐 Apple HIG + Liquid Glass）

本文记录界面决策的**依据**，方便后来者不改坏。所有取舍都以 Apple 官方材料为准：
Human Interface Guidelines（Materials / Layout / Navigation / Accessibility）与
iOS 26 引入的 Liquid Glass 设计语言。

## 1. 材质：玻璃只用在「浮在内容之上」的层

Liquid Glass 在苹果的定义里是**控制层**的材质，不是内容背景。因此：

| 层 | 材质 | 理由 |
| --- | --- | --- |
| 窗口背景 | 纯色 `backgroundBase`（浅 `#F2F3F5` / 深 `#111214`） | 内容需要稳定的对比度；玻璃叠玻璃会糊 |
| 导航栏 / 标签栏 | 系统自带玻璃（不自定义背景） | 系统会自动处理滚动边缘、键盘、滚动到底的收放；自己画必然做不对 |
| 卡片（主机摘要、设置分区） | `UIGlassEffect` regular + `showsStroke` | 需要"浮起"的层次感，又要透出下层 |
| 输入框 / 工具栏 / 悬浮按钮 | `UIGlassEffect`（按钮用 `UIButtonConfiguration` 的 glass 系列） | 系统提供按压的高光与变形动画，手感与原生一致 |
| 多个玻璃控件相邻 | `UIGlassContainerEffect`（`IMGlassGroupView`） | 靠近时像液体一样融合，这是 iOS 26 的标志性行为 |
| 消息正文 / 代码块 | **不用玻璃**，用 `backgroundLayer1` 与 `codeBackgroundColor` | 长文本需要最高可读性 |

规则：**一屏最多两层玻璃**（浮层 + 卡片），第三层一定退化。

## 2. 形状与度量

- 圆角用 `kCACornerCurveContinuous`（连续曲率），这是 iOS 的"squircle"，与系统卡片一致。
- 尺度：小控件 8 / 行内元素 12 / 大卡 18 / 卡片 22 / 胶囊 999。任何新控件都必须从 `IMTheme` 取。
- 间距只用 4 的倍数：4 / 8 / 12 / 16 / 24。
- 分割线用 `1/displayScale`（真 1px），颜色 `separatorColor`（深色 9% 白 / 浅色 8% 黑）。

## 3. 排版

| 用途 | 字号 / 字重 | 对应 IMTheme |
| --- | --- | --- |
| 页面大标题 | 28 Bold | `+fontLargeTitle` |
| 区块标题 | 20 Semibold | `+fontTitle` |
| 卡片标题 | 16 Semibold | `+fontHeadline` |
| 正文 | 15 Regular，行高 ×1.45 | `+fontBody` / `+bodyLineHeightMultiple` |
| 次要信息 | 12 Regular | `+fontFootnote` |
| 代码 | 13 等宽 | `+fontMonoBody` |

正文行高 1.45 是把 DSH 桌面端 `line-height: 22px / font-size: 14px ≈ 1.57` 往触屏收一点的结果：
手机上过大的行距会让一屏信息量太少，过小则读起来累。

**Dynamic Type**：所有自定义字体都基于 `systemFontOfSize:weight:`，跟随系统字号缩放；
`IMTheme` 的度量不随字号变化，避免大字号下布局崩坏。

## 4. 导航与布局

- **iPhone**：`UITabBarController`（会话 / 文件 / 设置），列表→详情的 push 用系统导航。
- **iPad**：沿用 iPadOS 26 顶部浮动标签栏；会话与文件域内部用 `UISplitViewController` 双列，
  设置域按 iOS 惯例保持单列并向中间收窄（`-maxContentWidthForSize:` 返回 720/860pt）。
- 内容最大宽度：手机全宽，iPad 720–860pt，避免超长行。
- 大标题左对齐（DSH 桌面端也是左对齐），滚动时随系统行为收缩。

## 5. 动效

- 只做三种：**层级转场**（crossfade 0.2s）、**状态反馈**（haptic + 轻微缩放）、**流式追加**（不跳动）。
- 聊天流式输出时：贴底则跟随，用户上滑立刻锁定位置并显示「回到底部」玻璃按钮——
  绝不因新内容把正在读的内容顶走。
- 不做弹跳、不做无意义的循环动画。`UIViewPropertyAnimator` 的 spring 只用于卡片出现。

## 6. 无障碍

- 可点区域 ≥ 44×44pt（玻璃圆按钮统一 36–44，命中区域用 `hitTest` 扩边）。
- 每个自定义行都设 `accessibilityLabel` / `accessibilityTraits`；工具调用卡片朗读为
  「工具调用，write，进行中」这样的整句，而不是把图标和文字分开念。
- 支持粗体文本、降低透明度、增强对比度：玻璃在「降低透明度」开启时自动退化为不透明底
  （系统材质自己处理，因此**不要给玻璃视图写死 alpha**）。
- 支持 VoiceOver 的「朗读顺序」：摘要卡 → 操作行 → 脚注。

## 7. 深浅色

所有颜色都是 `UIColor colorWithDynamicProvider:`，无一处硬编码 RGB（`IMTheme` 除外）。
玻璃描边在深色下是 12% 白、浅色下 55% 白——因为浅色背景下玻璃边界会消失。

## 8. 与 DSH 桌面端的一致性

| DSH 桌面端 | IMDSH |
| --- | --- |
| 左对齐大标题、分区卡片 | 同 |
| 会话列表：标题 + 相对时间 + 运行态 | 同（子代理会话缩进弱化） |
| 消息流：助手正文无气泡、用户右对齐淡底 | 同 |
| 推理内容折叠 | 同（默认折叠为一行） |
| 工具调用：一行摘要 + 可展开参数/结果 | 同 |
| 代码块：语言标签 + 复制 | 同（横向滚动，不折行） |
| Markdown：标题/列表/引用/表格/行内代码 | 同（自制渲染器，见 `IMMarkdownRenderer`） |

差异是**针对性优化**：触屏上把 hover 才出现的操作改成常驻/长按；把桌面端的多栏压成
「列表→详情」；把键盘快捷键换成手势与玻璃按钮。
