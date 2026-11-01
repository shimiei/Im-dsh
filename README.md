# IMDSH

**DeepSeek Harness 的原生 iOS 客户端**（iPhone + iPad，iOS 27+），全原生 UIKit 手写界面，
材质使用 Apple 的 **Liquid Glass（液态玻璃）**，用「地址 + 配对码」连接这台机器上的 DSH，
并把 dsh-webim 的远程能力（多机管理、一码一机、设备吊销、文件预览）原生做了一遍。

> 它不跑 WebView。会话列表、聊天流、Markdown 渲染、工具调用卡片、文件树与预览、设置面板，
> 全部是原生视图；协议层直接跟本机 Harness 的 RPC / WebSocket 对话。

---

## 0. 下载安装

安装包托管在 **Releases**：

```
https://github.com/shimiei/Im-dsh/releases/latest
```

下载 `IMDSH-unsigned.ipa`，用 **TrollStore** 直接装，或用 **ESign / Feather** 拿自己的证书重签
（详见 §5）。仓库里只有源码，`dist/` 与 `*.ipa` 不入库。

## 1. 组成

| 部分 | 位置 | 说明 |
| --- | --- | --- |
| iOS 客户端 | `ios/src/` | Objective-C + UIKit，无 Swift、无第三方库、无 xcodeproj，纯 `clang` 构建 |
| 构建工具链 | `tools/` | 交叉编译 + 未签名 ipa 打包（Windows/WSL 即可，不需要 Mac） |
| 服务端配对 | dsh-webim 插件（另一个仓库） | 配对码能力长在插件侧（一码一机、长效、可吊销），本仓库只含客户端 |
| 协议文档 | `docs/protocol.md` | DSH 客户端协议规范（RPC / 流 / 鉴权 / 数据模型），含实测摘录 |

## 2. 已经做到的事

| 域 | 能力 |
| --- | --- |
| 配对 | 地址 + 配对码首屏配对、令牌存 Keychain、失败有可读原因、错误码分级文案 |
| 多机 | 多台主机保存 / 一键切换 / 重命名 / 删除 / 重新配对 |
| 设备管理 | 主机侧已配对设备列表、吊销、生成配对码（有效期可选）、未使用码复制与作废 |
| 会话 | 列表（运行中置顶、相对时间、子会话弱化）、搜索、下拉刷新、光标分页 |
| 聊天 | follow 流 + 60ms 合帧打字机、推理折叠、工具调用卡（参数/结果可展开）、待办卡、断线重连横幅、上滑翻页保位 |
| 发送 | 文本 + 图片（相册/拍照，按服务端 `imageLimits` 压缩，多图）、发送失败可重试不清内容、中断生成 |
| 渲染 | 手写 Markdown（标题/粗斜删/行内码/围栏代码块/嵌套列表/引用/链接/表格），代码块复制与折叠 |
| 文件 | 会话作用域文件树、面包屑、文本分页预览、图片缩放与 GIF、QuickLook（PDF/Office/音视频）、分享与外部打开 |
| 材质 | Liquid Glass：卡片、输入胶囊、工具栏、悬浮按钮，相邻玻璃自动融合（`UIGlassContainerEffect`） |
| 适配 | iPhone 单列 / iPad 双列（会话、文件），Dynamic Type，深色模式，VoiceOver 标签 |

## 3. 为什么需要服务端改动

浏览器端的 dsh-webim 只认「带 token 的长链接」。原生 App 要的是：

- **长效凭据**：一台设备配一次，之后不用再扫链接；
- **一码一机**：配对码只能被一台设备兑换，防止链接被转发后无限扩散；
- **可管理**：主机上能看到「哪台设备在连」，并能单独吊销。

所以 dsh-webim 增加了一组端点（详见 `docs/pairing-api.md`）：

```
POST /__webim/pair/redeem    {code, deviceId, deviceName, platform} → {deviceToken, ...}
POST /__webim/pair/code      {days}                                 → {code, expiresAt, ...}
GET  /__webim/pair/devices                                          → {devices, pairingCodes}
POST /__webim/pair/revoke    {deviceId} | {code}
```

App 侧把 `deviceToken` 存进 **Keychain**，之后所有 HTTP / WebSocket 请求都以
`Cookie: webim_device=<token>` 携带；网关校验后自己铸造 `dsh-auth-*` Cookie 转发给 Harness，
**DSH 的真实凭据永远不出主机**。

## 4. 构建（Windows + WSL，无需 Mac / Xcode）

前置：WSL Ubuntu 里要有 `clang`、`ld64.lld-18`、`python3`、`zip`，以及一份 iOS 27 SDK。

### 4.1 取 SDK 并做兼容处理

```bash
# 用 xybp888/iOS-SDKs 里的 iPhoneOS27.2.sdk（约 407 MB，只 checkout 这一个目录）
mkdir -p ~/sdk-dl && cd ~/sdk-dl
git clone --filter=blob:none --no-checkout --depth 1 --branch iOS27.2-SDKs \
  https://github.com/xybp888/iOS-SDKs sdk
cd sdk && git sparse-checkout init --cone && git sparse-checkout set iPhoneOS27.2.sdk
git checkout && mv iPhoneOS27.2.sdk ~/theos/sdks/

# 生成一份 lld-18 可读的副本（新版 tbd 多了 arm64e.x1-ios 目标，LLVM 18 不认）
# 在仓库根目录下执行
bash tools/patch-sdk.sh
```

### 4.2 编译与打包

```bash
# 语法检查（秒级，开发时用）
bash tools/check-ios.sh

# 全量打包 → dist/IMDSH-unsigned.ipa
bash tools/release.sh
```

两个脚本都按自身位置定位仓库，不依赖任何绝对路径；在任意目录用绝对路径调用也可以。

产物自检会打印 Mach-O 架构、ipa 结构、`MinimumOSVersion`，任一不符即失败。

### 4.3 工具链要点（踩过的坑）

| 现象 | 原因与做法 |
| --- | --- |
| `unknown architecture ... arm64e.x1-ios` | iOS 27 SDK 的 tbd 新增目标，LLVM 18 的 lld 不认；`patch-sdk.sh` 生成去掉该目标的副本，原始 SDK 不动 |
| `module '_c_standard_library_obsolete' requires feature ...` | 新 SDK 的 modulemap 特性太新；编译统一用 `-fno-modules` |
| `'UIUtilities/UIDefines.h' file not found` | UIKit 头文件拆到了 `System/Library/SubFrameworks`，需要 `-F` 该目录 |
| `undefined symbol: _CGRectZero` | 必须显式 `-framework CoreGraphics`（UIKit 的 tbd 不 re-export） |

## 5. 安装

产物是**未签名 ipa**，用你自己的签名工具装（本仓库不提供证书，也不做假签名）：

- **TrollStore**：直接把 `IMDSH-unsigned.ipa` 丢进 TrollStore 安装；
- **ESign / Feather**：用自己的 p12 + mobileprovision 重签后再装；
- 有 Mac 的话也可以自己建 Xcode 工程引用 `ios/src` 编译（源码是纯 ObjC，不依赖任何私有 API）。

## 6. 使用

1. 电脑上打开 DSH → 设置 → **远程接入** → 打开总开关；
2. 在「设备配对」里点「生成配对码」，得到 `XXXX-XXXX-XXXX`（默认 30 天有效，可设永久）；
3. 手机上打开 IMDSH，填地址（例如 `192.168.1.20:3081`，或隧道域名 `xxx.trycloudflare.com`）和配对码；
4. 配对成功后直接进入会话列表。**同一个码不能给第二台设备用**；换设备请在电脑上重新生成。

多机：设置 → 主机管理里可以保存多台机器（家里一台、公司一台），随时切换当前主机。

## 7. 目录结构

```
.
├── ios/src/
│   ├── main.m, App/          应用生命周期、Scene、外壳（会话/文件/设置）
│   ├── Theme/                IMTheme（颜色/字体/度量）、IMGlass（液态玻璃组件）
│   ├── Core/                 Keychain、多机存储 IMServerStore、设备身份、崩溃日志
│   ├── Net/                  IMAPIClient（网关 HTTP）、IMDSHClient（RPC + WS）、IMPairingService
│   ├── UI/Chat/              会话列表 + 聊天流 + Markdown 渲染
│   ├── UI/Files/             工作区文件树 + 预览
│   ├── UI/Settings/          多机管理、设备配对码、设备名、关于
│   └── UI/Pairing/           首屏配对（地址 + 配对码）
├── tools/                    构建、检查、打包、图标生成、SDK 修补
├── docs/                     协议文档、配对 API、构建与设计说明
└── dist/                     打包产物（不入库，见 Releases）
```

## 8. 已知限制

- 只产出未签名 ipa，签名/装机由你自己完成；企业证书过期会导致 App 不可用。
- 局域网 HTTP 明文依赖 `NSAllowsArbitraryLoads`（网关在局域网内通常是 `http://`）；公网请用 Cloudflare 隧道走 https。
- 液态玻璃是 iOS 26+ 的原生材质，`MinimumOSVersion = 27.0`，低版本系统装不上。
- 文件上传（`fileUploads/upload`）、终端面板、agent team 面板、无限画布等桌面端高级面板尚未覆盖（见 `docs/roadmap.md`）。

## 9. 文档索引

| 文档 | 内容 |
| --- | --- |
| `docs/install.md` | **装机与首次连接**：三种自签方式、配对流程、排错表、安全说明 |
| `docs/protocol.md` | DSH 客户端协议规范：135 个端点、HTTP/WS 传输、鉴权、数据模型、必调清单（每条带源码行号与实测标记） |
| `docs/pairing-api.md` | 配对端点的硬契约：字段、错误码、Cookie/?device=、WS 握手、客户端检查单 |
| `docs/design.md` | 设计依据：Liquid Glass 用法、排版与度量、无障碍、与桌面端的一一对应 |
| `docs/roadmap.md` | 未覆盖功能与工程债 |
| `docs/verification.md` | **验证报告**：验证到什么程度、用什么方法、哪些没验证（真机排查清单） |