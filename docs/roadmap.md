# IMDSH 路线图 / 未覆盖清单

当前版本（1.0）覆盖了日常使用的主干：配对与多机、会话列表与聊天流、Markdown 与代码渲染、
工具调用与待办卡片、工作区文件树与原生预览、设置与设备管理。以下是明确**还没做**的部分，
按价值排序，方便后续迭代。

## 1. 高价值

| 项 | 说明 | 依赖 |
| --- | --- | --- |
| 发送附件 | 图片走内联 base64（`session/prompt` 的 content 块），文件走 `workspaceFiles` 上传拿收据 | `docs/protocol.md` §8.1/§8.2 |
| 权限与提问卡片 | DSH 的 `permissions` / `userQuestions` 投影（工具请求授权、agent 反问）目前只展示不交互 | `userQuestions/answer`、`permissions/*` |
| 会话搜索 | `session/list` 已在本地有全量标题，先做本地过滤；远程搜索要接 settings/搜索端点 | — |
| 终端面板 | `terminal/create` / `terminal/attach` 流，需要自制 ANSI 渲染 | §7 清单外 |
| 通知 | 会话跑完/报错时本地通知（App 在前台时可行；后台需 APNs，本仓库没有服务端推送） | — |

## 2. 中等

- **图片画布 / image-gen 面板**：DSH 桌面端有无限画布，原生重画成本高，暂缺。
- **团队（agent team）视图**：`team/member`、`subagent/*` 事件已在流里，但没有专门面板。
- **设置/插件面板**：`settings/describe|update` 已通，但 UI 只做了常用项；插件配置页未做。
- **代码高亮的语言覆盖**：目前是关键字着色，接完整语法高亮需要内置一份轻量词法表。
- **分屏与外接键盘**：iPad 分栏已支持，外接键盘快捷键（⌘↩ 发送、⌘K 搜索）未做。

## 3. 已知工程债

- `IMDSHClient` 的 multipart 解析是手写的，字段布局按实测样本；`session/attachment` 的 `data`
  编码（base64?）仍未实测确认，取回历史图片时可能需要在真机上修一次。
- 未做单元测试（ObjC 侧没有 XCTest 环境，因为不走 Xcode）。协议层的正确性靠
  `docs/protocol-notes/` 里的探测脚本保证，那些脚本可以随时复跑。
- 聊天流的增量合并策略（tool-call-delta 拼接、reasoning 折叠）只按 DSH 当前版本的事件形状实现，
  DSH 大版本变更时需要跟进。
