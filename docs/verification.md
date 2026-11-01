# 验证报告

这份文档记录 **IMDSH 到底验证到了什么程度、用什么方法验证、以及哪些没验证**。
写它的原因很简单：这个项目在**没有 Mac、没有 Xcode、没有模拟器、没有真机**的环境里完成，
"看起来能编译"和"真的能跑"之间隔着一条河。把证据和缺口都摊开，比一句"已完成"有用。

## 1. 已证实的事实（可复跑）

### 1.1 编译与链接

```bash
bash imdsh/tools/check-ios.sh    # 逐文件 -fsyntax-only
bash imdsh/tools/release.sh      # 全量编译 + 链接 + 打包 + 自检
```

| 项 | 结果 |
| --- | --- |
| 源文件 | 81 个 `.m`/`.h`（710 KB），41 个编译单元 |
| 语法检查 | **41 files, 0 diagnostics（0 error、0 warning）** |
| 链接 | `Mach-O 64-bit arm64 executable, flags:<NOUNDEFS\|DYLDLINK\|TWOLEVEL\|PIE>` |
| 符号 | `NOUNDEFS` —— 没有未解析符号（少一个 framework 都过不了这一关） |

`NOUNDEFS` 是这块最硬的证据：它证明 `UIGlassEffect`、`PHPickerViewController`、`QLPreviewController`、
`UIImageWriteToSavedPhotosAlbum` 这些类真的被链接器找到了，而不是"编译过了、跑起来找不到"。

### 1.2 产物结构

```
IMDSH-unsigned.ipa          744 KB / 19 files
└── Payload/IMDSH.app/
    ├── IMDSH                1.3 MB  arm64 Mach-O
    ├── Info.plist           3.4 KB
    ├── PkgInfo              APPL????
    └── Icons/               12 个尺寸的 png（20→1024）
```

`Info.plist` 关键键已逐项核对：
`CFBundleIdentifier=com.imdsh.app`、`CFBundleExecutable=IMDSH`（与二进制同名，否则装上去闪退）、
`MinimumOSVersion=27.0`、`UIDeviceFamily=[1,2]`、
`UIApplicationSceneManifest.UISceneDelegateClassName=IMSceneDelegate`（场景委托存在，否则白屏）、
`CFBundleIcons`/`CFBundleIcons~ipad` 的 `CFBundleIconFiles` 用的是**不带 `@2x` 的基名**
（写成 `AppIcon-60@2x` 系统会再拼一次后缀，结果是白图标——这条已经踩过并修正）。

### 1.3 静态审查（两轮）

| 轮次 | 方法 | 结果 |
| --- | --- | --- |
| 一 | 逐文件读 41 个文件，专查启动链路 | 启动链路干净：window/scene 正确建立、root 不可能为 nil、观察者有防重注册标志 |
| 二 | 对抗式审查（越界/空指针/主线程/重入/泄漏） | 19 个缺陷，P0×2 + P1×7 + P2×10，**全部修复并重新编译验证** |

两轮 P0 是真正会让 App 打不开或无声崩溃的：
1. `IMDSHClient` 的流订阅字典跨线程无锁读写（socket 回调队列 vs 主线程）；
2. `UIGlassEffect` 无 `@available` 保护，低版本系统上 dyld 找不到类直接秒退。

修完之后重跑全量语法检查仍是 0 error 0 warning，说明修复没有引入新问题。

### 1.4 服务端

```bash
node --test "tests/*.test.mjs"
# tests 111 / pass 111 / fail 0
```

其中 16 个是新增的配对用例（`tests/pairing.test.mjs`）：码格式与字符集、一码一机绑定、
重复兑换拒绝、异设备拒绝、过期、永久码、吊销、`pairing.json` 原子写与损坏降级、
HTTP 端到端（redeem / Cookie 与 `?device=` 双通道 / WS 握手 101 与 401 / 吊销即失效 / 限流）。
原有 95 个用例一个没坏。

## 2. 没有验证过的（真机必看）

**运行时一次都没跑过。** 以下几处是判断偏差最可能暴露的地方，按风险排序：

| # | 项 | 为什么没验 | 出问题会怎样 |
| --- | --- | --- | --- |
| 1 | `session/prompt` / `session/cancel` 真实行为 | 发真请求会驱动 Agent，探测阶段刻意只做只读 | 发消息失败；已在失败分支打 `args` 摘要日志（base64 截断）便于定位 |
| 2 | 图片发送的 content 形状 | 同上 | 若服务端拒收会返回 `gateway/arguments-invalid`，日志里能看到实际发了什么 |
| 3 | `session/attachment` 取历史图片 | 契约来自源码（`contracts.md:2820`），未实测 | 缩略图不出图，**会自动退回文字 chip，不会崩** |
| 4 | `workspaceFiles/readBytes` 的 multipart 字段 | 来源分片命名来自源码推断 | 图片/二进制预览失败，会显示可重试错误 |
| 5 | 相机拍照链路 | 无真机 | 点「拍摄照片」后在压缩或上传处失败 |
| 6 | 真机 HEIC 原图转码 | 无真机 | 选 HEIC 图后压缩异常 |
| 7 | 4 张图连发 ~2–3 MB body | 无网关实测 | 被反代/网关截断（`client_max_body_size` 之类） |
| 8 | iPad 旋转 + 分屏 + 键盘连续操作 | 无模拟器 | 布局错乱或重建时序异常 |
| 9 | 液态玻璃的实际观感 | 无真机 | 只能上机调间距/透明度，代码里所有材质参数都集中在 `IMTheme` |

## 3. 复跑全部验证

```bash
# 客户端
bash imdsh/tools/check-ios.sh            # 期待：41 files, 0 diagnostics
bash imdsh/tools/release.sh              # 期待：linked ... NOUNDEFS，ipa 744 KB

# 服务端
node --test "tests/*.test.mjs"           # 期待：111 pass / 0 fail

# 协议探测（只读，需要 DSH 正在运行）
node imdsh/docs/protocol-notes/tools/probe-rpc.mjs
```

## 4. 结论

**能交付的东西**：可侧载的未签名 ipa、完整可编译源码、协议规范、装机指南、设计依据。
**不能承诺的东西**：在没有真机跑过的情况下说"所有功能 1:1 还原"。协议层的事实是实测的，
UI 层是照着桌面端的信息结构重画的，但**第一次上机一定会有一批小问题**——这属于这类交付的常态，
不是遗漏。上面那张表就是排查清单。
