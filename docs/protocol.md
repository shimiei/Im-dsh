# DSH 浏览器客户端通信协议规范

> **用途**：IMDSH（全原生 iOS 客户端）直接对接本机 DeepSeek Harness 网关的实现蓝本。
> **范围**：DSH Harness Web 载体上的全部线上协议事实——HTTP unary RPC、WebSocket 多路复用流、鉴权、数据模型、端点契约。
> **不覆盖**：渲染、Markdown、UI 状态机等展示层内容。

---

## 0. 阅读指南

### 0.1 证据分级

本文每条结论都标注了出处，并按强度分三级。**实现时请把 ⚠️ 当成"设计上要有兜底"的信号。**

| 标记 | 含义 | 依据 |
|---|---|---|
| ✅ **实测** | 已对本机运行中的 Harness（`http://127.0.0.1:27004`）发出真实请求并观察到响应 | `protocol-notes/probe-*.out.txt` |
| 📖 **源码** | 从 `reference/asar/` 解包源码读出的确定事实 | 标注 `文件:行号` |
| ⚠️ **未确认** | 推断、约定俗成或无法在线验证 | 见 §10，附实测方法 |

源码路径一律相对 `C:\Users\you\Desktop\dsh-webim\reference\asar\`。
线上协议的全部生成式契约（135 个端点、请求/响应 JSON Schema）已脚本化提取到
`imdsh/docs/protocol-notes/endpoints.raw.json`，可读版在 `endpoints.index.txt`、
`endpoints.contracts.md`、以及按主题分组的 `*.compact.txt`。

### 0.2 三十秒结论

- 只有两种线上载体：**HTTP POST unary RPC**（`/api/<namespace>/<method>`）和 **一条 WebSocket**（`/api/remote.mux`，多路复用所有流）。
- 两条载体**共享同一套鉴权与错误码词汇，但信封不同**：HTTP 用 `client-request` / `server-response`；WS 用 `open` / `item` / `end` / `cancel`（上行）与 `item` / `end` / `error`（下行）。别把两者混用。
- 鉴权只有一种：**Host 头 + 一个签名 Cookie**，名字是 `dsh-auth-<base64url(sha256(authority))>`，值为 `v{1|2}.<base64url(json)>.<base64url(hmac)>`。没有 Authorization 头、没有 query token（`/connect` 与 `GET /` 除外）。
- 会话历史 = **`session/follow` 开流拿 snapshot（含 cursor）→ `session/page` 用 `throughSeq=cursor` 向前翻页**。
- 实时三条流：`session/follow`（一个会话的日志增量）、`session/control`（**全机所有会话**的投影增量）、`$events`（Host 侧 Cordis 事件广播，用于审批/提问/插件安装等跨域通知）。
- 端点总数 **135**（26 个 package），IMDSH 真正需要的大约 **30 个**（§7）。

### 0.3 与任务书的差异（重要）

任务书假设「`reference/asar/dsh-web-frontend/dist/assets/index-BXV-oxvX.js` 里有真实调用点可 grep」。**这个前提不成立**，已核实：

```
index-BXV-oxvX.js :  "client-request" 0 次,  "rpcId" 0 次,  "remote." 0 次,  "typert" 0 次,  "WebSocket" 0 次
vendor-DcuzkuQH.js:  同上，全为 0
```

该 bundle 里唯一的 `/api` 出现在 `dsh-app://app/api/file?`（自定义 scheme 判定），`__DSH_TRANSPORT__` 的 2 次命中也在无关分支里。它只是**桌面壳的 Markdown/代码渲染层**（KaTeX + Shiki langs 懒加载），不含 RPC 客户端。真正的调用点在各功能包自己的 `lib/client.js` 模块 bundle 里（形如 `window.__ModuleLoader__.load({ id: "@deepseek-ai/dsh-api-remotes", ... })`）。

因此端点契约的交叉验证改用两条更强的证据链：
1. **生成式描述符**：`dsh-api-remotes/lib/client.js`（1.09 MB）内含 26 个 `createTypertRemoteInfo({package, methods})` 字面量 + 完整 Zod schema，是编译器产物，等价于 IDL。
2. **实机探测**：直接对 27004 端口跑 `protocol-notes/tools/probe-*.mjs`。

---

## 1. 架构总览

```
┌─────────────────────────── DSH Host 进程 ───────────────────────────┐
│                                                                     │
│  webServer   ── 静态资源(dist/) / GET / (index 授权) / GET /connect   │
│  connection  ── 载体无关的 RPC 路由表 + /api 前缀路由 + Host/Origin 栅栏 │
│      │                                                              │
│      ├── rpc.intercept("/api", claims, handler)  ← typertGateway     │
│      │        └── 未认领的 endpoint → 404                             │
│      └── webServer.registerUpgrade("/api/remote.mux") ← RemoteStreamMuxServer │
│                                                                     │
│  typertGateway ── Remote 方法分派（135 个端点）+ 逻辑流多路复用          │
│  api-* 包     ── 各领域 Remote 方法实现（session / workspace / files …）│
└─────────────────────────────────────────────────────────────────────┘
        ▲                                   ▲
        │ HTTP POST /api/<ns>/<method>      │ WS /api/remote.mux
        │ (JSON 或 multipart 回包)           │ (JSON 文本帧)
   ┌────┴───────────────────────────────────┴────┐
   │  浏览器 / IMDSH（同一个 Cookie 通吃两条路）    │
   └────────────────────────────────────────────┘
```

关键源码位置：

| 组件 | 文件 |
|---|---|
| `/api` 前缀常量、`/connect` | `dsh-client-connection/lib/index.js:14`、`:19` |
| HTTP↔fetch 桥 | `dsh-client-connection/lib/index.js:40`（`bridge`） |
| RPC 路由 + 信封校验 + multipart 编码 | `dsh-client-connection/lib/index.js:888`（`rpcFetchHandler`）、`:938`（`fullResponse`） |
| Host/Origin 栅栏 | `dsh-client-connection/lib/index.js:240`（`isTrustedApiRequest`） |
| Cookie 铸造/校验 | `dsh-client-connection/lib/index.js:277`（`COOKIE_PREFIX`）、`:335`、`:354`、`:559` |
| 浏览器侧 unary 调用 | `dsh-client-connection/lib/client.browser.js:1212` |
| 浏览器侧 WS 打开 | `dsh-client-connection/lib/client.browser.js:1348` |
| WS mux 路径常量 | `dsh-api-gateway/lib/types/stream-protocol.js:4` |
| WS 服务端 | `dsh-api-gateway/lib/types/stream-server.js:8` |
| WS 客户端多路复用 | `dsh-api-gateway/lib/types/client/stream-client.js:23` |
| 端点认领与分派 | `dsh-api-gateway/lib/index.js:773`、`:876`（`claimsEndpoint`） |

---

## 2. 传输一：HTTP unary RPC

### 2.1 URL 规则

```
POST http://<host>:<port><channel>/<endpoint>
                   └── /api ──┘└── namespace/method ──┘
```

- **channel**：唯一由 Connection 自身持有的是 `"/api"`（`API_PATH`，`dsh-client-connection/lib/index.js:14`）。其余 channel 由插件通过 `connection.rpc.handle(channel, fn)` 注册（`dsh-client-connection/lib/index.js:855` 的 `register`），`assertChannel` 明确**禁止**插件占用 `/api`（`:971`）。本仓库里唯一存在的第二 channel 例子是 dsh-webim 自己的 `/webim`（`lib/index.js:21`）。
  - 📖 channel 与 endpoint 的正则：`CHANNEL_PATTERN = /^\/[A-Za-z0-9._~-]+$/`（`client.browser.js:1201`）。
- **endpoint**：`namespace/method` 两段。段字符集 `ENDPOINT_SEGMENT_PATTERN = /^[A-Za-z0-9_$.-]+$/`（`client.browser.js:1202`），且禁止空段、`.`、`..`（`client.browser.js:1317` 的 `assertTarget` / `dsh-client-connection/lib/index.js:926` 的 `endpointFromPath`）。
- **网关只认两段**：`claimsEndpoint` 要求 `endpoint.split("/").length === 2`，否则直接不认领 → 404（`dsh-api-gateway/lib/index.js:876-883`）。唯一例外是网关内部的 `$events/result`。
- 浏览器侧实际发出的 URL 是**相对路径**：`` `${channel}/${endpoint}`.slice(1) ``（`client.browser.js:1221`），即 `api/session/list`，靠 `document.baseURI` 解析。对 IMDSH 就是绝对地址 `http://127.0.0.1:27004/api/session/list`。

✅ 实测：`POST http://127.0.0.1:27004/api/session/list` 返回 `200 application/json`。

### 2.2 请求

```http
POST /api/session/list HTTP/1.1
Host: 127.0.0.1:27004
Content-Type: application/json
Cookie: dsh-auth-XXXX=v1.YYYY.ZZZZ

{"type":"client-request","rpcId":"<uuid v4>","method":"session/list","payload":{"args":{"_request":{}}}}
```

- **必须** `Content-Type: application/json`，否则 `415 content type must be application/json`（`dsh-client-connection/lib/index.js:894`）。
- **必须** `POST`，否则 `404 not found`（`:893`）。
- **不需要**任何 `x-dsh-*` 头。任务书里猜的这类头**不存在**：全仓库 `x-dsh` 零命中。唯一的强制额外头是 `Host`（栅栏判定用，见 §4.3）。`Origin` 可选但一旦出现必须同 authority，`Sec-Fetch-Site: cross-site` 会被直接 403（`dsh-client-connection/lib/index.js:246-249`）。
  - 浏览器侧只发 `content-type` 一个自定义头（`client.browser.js:1223`），Cookie 由 UA 自动附带（`fetch` 默认 `credentials: same-origin`）。
- **信封**（`clientRequestSchema`）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | `"client-request"` | 字面量 |
| `rpcId` | `string` | 客户端随机 UUIDv4，用于回包关联；缺失/非串时服务端用占位 id |
| `method` | `string` | **必须与 URL 里的 endpoint 完全一致**，否则回 `gateway/bad-request`（`dsh-client-connection/lib/index.js:904`） |
| `payload` | `object` | 本层恒为 `{ "args": { ... } }`；`args` 的键名必须与描述符的 `wire` 名**精确匹配**（多一个、少一个都报错） |

> ⚠️ 注意 `payload` 只有 `args` 一个键这一事实：`remoteRequest()` 会把 `args` 展平后按描述符的 `wire` 名逐个取参。**`args` 校验是"字段集合精确相等"**，不是"至少包含"。
>
> ✅ 实测反例（很重要）：
> `session/list` 的描述符里那个"空请求"参数 `_request` 是**必须出现**的字段。
> 不传 → `{"code":"gateway/arguments-invalid","message":"typert gateway: session/list: args fields do not match the descriptor: missing \"_request\""}`
> 同理 `session/follow` 不允许多传顶层 `assistantStream`（它属于 `request` 内部）。

### 2.3 响应信封

```json
{"type":"server-response","rpcId":"<回显>","result":{"ok":true,"value":{...}}}
```

```json
{"type":"server-response","rpcId":"<回显>","result":{"ok":false,
  "error":{"code":"gateway/arguments-invalid","message":"...","details":{"endpoint":"session/list"}}}}
```

- `result.error.details` **必然是对象**（不能是 null / 数组），客户端解析器会强制校验（`client.browser.js:1301`）。
- 业务失败也是 **HTTP 200**。HTTP 层只表示"载体通了"。客户端必须依据 `result.ok` 判断。
- `rpcId` 必须与请求一致，否则浏览器侧抛 `rpcId mismatch`（`client.browser.js:1230`）。

### 2.4 `multipart/form-data` 二进制回包

当结果里有 `Uint8Array` 时（例如 `workspaceFiles/readBytes`、`officeToPdf/render`），Host 改回 multipart。这是唯一一处**形态变化**的回包。

编码端（`dsh-client-connection/lib/index.js:938-969`，`fullResponse`）：

```
parts["metadata"] = JSON 字符串 {
    "type":"server-response",
    "rpcId":"...",
    "result":{"ok":true,"value": <占位符 null 在树里的原始 JSON> },
    "attachments":[ {"path":[...], "codec":"bytes", "part":"bytes-0"}, ... ]
}
parts["bytes-0"] = <二进制 Blob>
parts["bytes-1"] = ...
```

解码规则（`dsh-client-connection/lib/client.browser.js:1240-1287`，`parseBinaryResponse`）：

1. 响应头 `content-type` 的 media type（分号前）等于 `multipart/form-data` → 走二进制分支。
2. 解析所有 part；同名 part 出现两次 → 协议错误。
3. 取出 `metadata`（必须是**文本 part**）→ `JSON.parse` → 按普通信封校验（`type/rpcId/result`）。
4. `attachments` 必须非空，每项 `{codec:"bytes", part, path}`。
5. `path` 从根 `{value: result.value}` 开始按段下钻（数组段必须是安全整数下标，对象段必须是字符串键，且**该键必须已存在**）。
6. 下钻终点的值**必须是 `null`**（占位符），然后把对应 `bytes-N` part 的字节原位替换进去。
7. 最终 `fields` 必须全部消费干净，否则报协议错误。

> 对 Objective-C：`NSURLSession` 不自动解 multipart，需要自己按 `boundary` 拆分；也可以用 `NSJSONSerialization` 处理 `metadata`。**建议 IMDSH 第一版只实现文本路径，二进制端点先用 `workspaceFiles/read`（文本）替代**，`readBytes` 真需要时再补。

⚠️ `attachment.path` 的具体下标布局只能在运行时观察。实测未取到二进制回包（本机没有触发该路径的调用）。验证方法见 §10。

### 2.5 非信封错误（HTTP 层）

这些响应**不是** `server-response`，客户端必须按 status 分支，不能当 JSON 解：

| Status | Body | 触发 | 出处 |
|---|---|---|---|
| `401` | `unauthorized` | `/api` 前缀路由的准入失败（无 cookie / cookie 过期 / API peer 已释放） | `dsh-client-connection/lib/index.js:862-866`（✅ 实测 body 就是 `unauthorized`） |
| `401` | `dsh web authentication required; reopen the URL printed by dsh web.\n` | 走 `writeUnauthorized` 的路径（index 路由、`/connect`） | `:571` |
| `403` | `forbidden` | Host 栅栏拒绝（Host 非 loopback/非受信、`Sec-Fetch-Site: cross-site`、Origin 不同 authority）；或非 owner peer 访问 exact Fetch route | `:863`、`:830` |
| `404` | `not found` | endpoint 未被认领（含非法段、非两段、方法不存在） | `dsh-client-connection/lib/index.js:835`、`:893`（✅ 实测：未知端点返回 `404 text/plain` body=`not found`） |
| `413` | 空 | 请求体超过 `maxRequestBodyBytes`（默认 **300 MiB**，`DEFAULT_MAX_REQUEST_BODY_BYTES`，`:30`） | `:56-61` |
| `415` | `content type must be application/json` | Content-Type 不对 | `:894` |
| `400` | `body is not JSON` | body 解析失败 | `:899` |
| `500` | `handler failure: ...` | handler 同步抛出未捕获异常 | `:913` |

### 2.6 限制与实现建议

- 请求体上限默认 300 MiB —— 这个数字是**为 base64 图片留的空间**（`:28-30` 注释：默认聚合图片上限 200 MiB，base64 膨胀后 ~267.7 MiB）。所以**图片是 base64 塞在 JSON 里传的**（§8）。
- 整个 body 会被**全量读进内存**（`bridge`，`:64-74`）。IMDSH 上传大图时要有进度与取消（取消靠断 HTTP 连接：`res.on('close')` → abort，`:42-44`）。
- 无 gzip/压缩协商要求；无 keep-alive 特殊要求（Node 默认）。
- 每个 unary 调用是**独立的 HTTP 请求**，与 WS 完全解耦：WS 断开不影响 unary，unary 也不等待 WS（`dsh-api-gateway/lib/types/client/index.js:41-44` 注释明确"HTTP dispatch never waits for this independent connection attempt"）。

---

## 3. 传输二：WebSocket `/api/remote.mux`

### 3.1 一整条 socket 承载所有逻辑流

- **路径**：`/api/remote.mux`，常量 `REMOTE_STREAM_MUX_PATH`（`dsh-api-gateway/lib/types/stream-protocol.js:4`）。
- 浏览器侧把 `http(s)` 换成 `ws(s)`，路径按 `document.baseURI` 或 `__DSH_TRANSPORT__.streamBaseUrl` 解析（`dsh-client-connection/lib/client.browser.js:1348-1354`；`dsh-api-gateway/lib/types/client/stream-client.js:477-485`）。
  对 IMDSH：`ws://127.0.0.1:27004/api/remote.mux`。
- 注册的是 **`registerUpgrade`**（raw socket upgrade route），不是普通 http 路由（`dsh-api-gateway/lib/index.js:784-820`）。

✅ 实测握手（唯一必需的自定义头就是 Cookie）：

```http
GET /api/remote.mux HTTP/1.1
Host: 127.0.0.1:27004
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: <base64 16B>
Sec-WebSocket-Version: 13
Cookie: dsh-auth-XXXX=v1.YYYY.ZZZZ
```

→ `HTTP/1.1 101 Switching Protocols`

升级被拒时服务端**手写**HTTP 响应然后关连接（`dsh-api-gateway/lib/types/stream-server.js:402-413`，`rejectRemoteStreamUpgrade`）：

| Status | Body |
|---|---|
| 401 `Unauthorized` | `unauthorized` |
| 403 `Forbidden` | `forbidden` |
| 409 `Conflict` | `conflict` |

> 409 的含义：该 **API peer 已有一条 socket**（`admitConnection` 里 `record.ownsSocket` 已置位，`dsh-client-connection/lib/index.js:764`）。浏览器 Cookie（v1）不受此限，因为它是共享的 `browserPeer`（`:746`、`:760-763`）。详见 §4.4。

### 3.2 帧格式

全部是**文本帧**（JSON）。**发二进制帧会被 `close(1003, "text messages required")`**（`stream-server.js:126-129`）。

#### 客户端 → 服务端（仅 4 种，键集合精确匹配）

校验器见 `dsh-api-gateway/lib/index.js:236-252`（`parseRemoteStreamClientMessage`）。

```jsonc
// 1) 开一条逻辑流
{"type":"open","streamId":"<string>","endpoint":"<namespace/method>","payload":{"args":{...}}}
//   —— 键集合必须恰好是 type/streamId/endpoint/payload，endpoint 非空
//   —— $events 的 payload 必须是 {"args":{}}（空对象，多余键即 error，见 index.js:994）

// 2) 上行数据项（给带 uplink 的流，例如 terminal/attach 的输入）
{"type":"item","streamId":"<string>","value":<any JSON>}
//   —— value 可省略

// 3) 上行结束
{"type":"end","streamId":"<string>"}

// 4) 取消这条流（服务端 abort 该流，收到的是取消语义而非错误）
{"type":"cancel","streamId":"<string>"}
```

规则：
- `streamId` **在同一 socket 内必须唯一**。重复 `open` 同一个 id 是**唯一会直接关掉整条 socket** 的协议违规（`close(1008, 'invalid Remote stream request')`，`stream-server.js:133-135`、`:177-179`）。
- 对已结束/未知 streamId 的 `item`/`end`/`cancel` 会被**静默丢弃**（`stream-server.js:157-168`），便于客户端乱序收尾。
- 每流上行缓冲上限 `streamInboxBytes`，默认 **262 144 B**（`dsh-api-gateway/lib/index.js:18`）。溢出 → 该流以 `gateway/uplink-overflow` 失败（`stream-server.js:287` 的 `UplinkInbox`）。IMDSH 若用 `terminal/attach` 要留意。

#### 服务端 → 客户端（3 种 JSON 帧 + WS 控制帧）

```jsonc
{"type":"item","streamId":"<string>","value":<该端点 result 类型的一个元素>}
{"type":"end","streamId":"<string>"}                            // 这条流正常结束
{"type":"error","streamId":"<string>","error":{"code":"...","message":"...","details":{...}}}
                                                                // 这条流以 Remote 错误终止
// 另有 WS 控制帧：Ping（服务端 ~2s 一次，客户端必须回 Pong）
// 另有一种"帧"只出现在特定端点内部（是 item 的 value，不是顶层帧）：
//   {"type":"ready"|"baseline"|"snapshot"|"projection"|"event"|...} —— 见 §3.4
```

服务端发送逻辑见 `stream-server.js:199-248`（`pump`）：正常迭代完 → `end`；抛 RemoteError → `error`；客户端 `cancel`（abort 原因不是 RemoteError）→ **不发任何终止帧，直接静默作废**。

### 3.3 心跳、关闭码、重连语义

| 项目 | 事实 | 出处 |
|---|---|---|
| 服务端 Ping 间隔 | 默认 **2000 ms**（可配 `websocketHeartbeatIntervalMs`） | `dsh-api-gateway/lib/index.js:17`、`:56` |
| 判定死亡 | 连续错过 **2 次** 心跳 → `terminate()` | `stream-server.js:6`（`MAX_MISSED_HEARTBEATS = 2`）、`:77-95` |
| 什么算"活着" | 收到 Pong、收到任意帧、以及一次**曾在发送缓冲区排队的**下行写完成 | `stream-server.js:112-118` |
| 客户端义务 | **必须应答 WS Ping**（回 Pong）。`URLSessionWebSocketTask` 自动处理；自写 RFC6455 栈要自己回 | ✅ 实测服务端 ~2s 一次 PING |

关闭码（全部实测/源码可查，出处列在右）：

| 方向 | Code | Reason | 触发 |
|---|---|---|---|
| 服务端 | `1003` | `text messages required` | 客户端发了二进制帧（`stream-server.js:127`） |
| 服务端 | `1008` | `invalid Remote stream request` | 帧 JSON 非法 / 键不符 / **重复 streamId**（`:134`） |
| 服务端 | `1011` | `Remote stream failure could not be delivered` | 终止帧本身写不出去（`:246`） |
| 服务端 | `1001` | `peer left` | 该 socket 绑定的 Peer 被销毁（`:383`、`:386`） |
| 客户端 | `1000` | `disposed` | 客户端主动销毁 mux（`client/stream-client.js:209`） |
| 客户端 | `4000` | `reconnect requested` | 客户端要求重连（`:70`） |
| 客户端 | `4002` | `invalid Remote stream frame` | 客户端解析到非法帧（`:321`） |

> IMDSH 侧看到 `1001 peer left` 意味着**凭据失效**（API peer 被释放/过期），不要无脑重连——先重新取 Cookie。

重连语义（**协议层面很宽松，客户端自己决定**）：
- 服务端**不做**流的续传：socket 一断，所有逻辑流终止（`stream-server.js:139-142` → `stream.stop(...)`）。
- 断线后必须：重开 socket → 对每条流重新 `open` → 用自己的游标做增量对齐。`session/follow` 用 `maxMessages` + snapshot 重新对齐；`workspaceFiles/changes` 用 `kind:'ready'` 重新对齐。
- 参考实现的重试参数（`recovery-config`，`dsh-client-connection/lib/index.js:983-987`）：`backoffBaseMs=500`、`backoffFactor=2`、`backoffMaxMs=10000`、`generationReadyWarnMs=3000`；并且浏览器侧会监听 `online/offline`（`client.browser.js:1359`）。
  ⚠️ 这些是**客户端侧默认值**，不是服务端强制。IMDSH 照抄这套退避即可。

### 3.4 逻辑流的分类（journal / remote / snapshot 三个词到底是什么）

任务书提到的 `journal-stream` / `remote-stream` / `snapshot-stream` **不是三种线上流**，而是 `dsh-api-gateway` **客户端库**的三个抽象层，全部跑在同一条 mux socket 上：

| 客户端类 | 文件 | 职责 | 对应线上行为 |
|---|---|---|---|
| `RemoteStreamMuxClient` | `lib/types/client/stream-client.js:23` | 管理**一条物理 socket**，把多个逻辑流多路复用上去 | 唯一的 socket |
| `RemoteStream` | `lib/types/client/remote-stream.js:12` | 一条**可跨 carrier 代际重连**的逻辑流生命周期（generation / restart / dispose） | 一套 `open`/`item`/`end`/`error` |
| `RemoteJournalStream` | `lib/types/client/journal-stream.js:15` | 在 `RemoteStream` 之上做**游标代数**：snapshot 起手、有序实时投递、向前翻页、gap 修复 | `session/follow` 的 snapshot→event 序列 |
| `RemoteSnapshotStream` | `lib/types/client/snapshot-stream.js` | 整值快照类流（首帧全量，后续整值替换） | `workspace/follow`、`job/list`、`workspaceFiles/changes` |

所以：**IMDSH 不需要实现这三个抽象，只需要实现"一条 socket + N 条 streamId + 4 种首帧语义"**。首帧语义分四类，客户端必须能区分：

| 首帧 value.type | 语义 | 例子 |
|---|---|---|
| `"ready"` | 已就绪，后面是通知流 | `$events`（带 `clientId`、`host`） |
| `"snapshot"` | 一次性基线（含 `cursor`/`hasMore`/`records`），后面是 `event` 增量 | `session/follow` |
| `"baseline"` | 全量基线，后面是**整值替换** | `workspace/follow`（`replace`）、`session/control`（`projection`） |
| 无首帧标记 | 直接是业务帧流 | `workspaceFiles/changes`（`{kind:'ready'}` 后跟 `{kind:'change'}`）、`job/list`（`{type:'rows'}`） |

### 3.5 `$events`：Host 侧 Cordis 事件广播

- 端点名 `$events`（`REMOTE_EVENT_STREAM_ENDPOINT`，`dsh-api-gateway/lib/types/stream-protocol.js:6`），`payload` **必须** `{"args":{}}`（`dsh-api-gateway/lib/index.js:994`）。
- 需要 `peer.interactions === 'answer'`（`requireInteractions`，`:984`），否则 `gateway/interactions-forbidden`。
- 只允许 `principal.kind === 'owner'` 的 peer 作答（`:965`）。

首帧（✅ 实测）：

```json
{"type":"item","streamId":"probe-events","value":{
  "type":"ready",
  "clientId":"0ad29b69-650d-49b1-977a-5198b56d131e",
  "host":{"home":"C:\\Users\\you"}
}}
```

后续帧有三种（`dsh-api-gateway/lib/index.js:1040`、`:1090`、`:1151` + ✅ 实测 waterfall）：

```jsonc
// 单向通知
{"type":"emit","event":"api-session/activity","args":[ ... ]}

// 需要客户端作答的 waterfall（实测样例，注意 agentId 与 eventId）
{"type":"waterfall","event":"user-questions/request",
 "eventId":"6d7b2fe8-e8f6-4684-bdcf-b3f564927357",
 "agentId":"session-6a59b86e-b2fe-4913-a2b5-2cbfae5acccf",
 "request":{"questions":[{"id":"target_dir","question":"...","header":"...","options":[{"label":"...","description":"..."}]}]}}

// waterfall 被撤回（例如超时/Host 侧已放弃）
{"type":"cancel","eventId":"6d7b2fe8-..."}
```

> `emit` 帧**不带** `resources` 字段（`resources` 只在 Host 内部做访问控制用，不上线）。

作答走**另一条 HTTP unary**：`POST /api/$events/result`，payload 必须是 `{args:{clientId, eventId, outcome}}`：

```jsonc
{"args":{"clientId":"0ad29b69-...","eventId":"6d7b2fe8-...","outcome":{"kind":"next"}}}
{"args":{"clientId":"...","eventId":"...","outcome":{"kind":"result","value":<json>}}}
{"args":{"clientId":"...","eventId":"...","outcome":{"kind":"rejected","error":{"name":"...","message":"...","code":"...","details":{}}}}}
```

校验：`parseRemoteEventResult`，`dsh-api-gateway/lib/types/stream-protocol.js:18-54`。**`outcome` 的键集合也是精确匹配**。

`$events` 的事件白名单只有 28 条（`dsh-api-remotes/lib/types/remote-events.js:16-45`），其中的 waterfall 只有两条：`approval/request`、`user-questions/request`。完整列表见 `protocol-notes/typert-declarations.txt` 与 §5.4。

> **IMDSH 取舍建议**：如果只做「会话聊天 + 工作区文件」，`$events` **不是必需**——`session/follow` + `session/control` 已经覆盖了「消息增量 + 会话状态/标题/待办/用量」。但**审批（`approval/request`）与提问（`user-questions/request`）只能从 `$events` 拿到**，且不答会让 Host 侧工具调用挂住。要做完整客户端就必须实现。

### 3.6 `session/control`：全机所有会话的投影增量流（**重要，任务书没提**）

✅ 实测：`session/control` 的**描述符参数为空**（`dsh-api-remotes/lib/client.js:15335-15354`，`parameters: []`），`args` 必须是 `{}`。它不是"一个会话的控制流"，而是**全机所有会话的投影总线**：

```jsonc
// 首帧：全量基线，value.projections 是 sessionId → 投影块 的字典
{"type":"item","streamId":"c-empty","value":{
  "type":"baseline",
  "value":{"projections":{
     "session-964f4202-...":{"asOfSeq":257,"values":{"title":"...","goal":null,
        "tokenUsage":{...},"contextPressure":{...},"inbox":{"next-turn":[],"next-step":[]},
        "sessionStats":{...},"turnOutline":[...],"agentPreset":"standard", ... }},
     "...":{...}
  }}
}}

// 增量：每个 (sessionId, key) 一次整值替换
{"type":"item","streamId":"c-empty","value":{
  "type":"projection","sessionId":"a1fb7255-...","key":"tokenUsage",
  "value":{"uncachedInputTokens":26762,...},"seq":104}}
```

- 帧内的 `seq` 是该投影块的水位；`key` 取值来自投影键集合（§5.4）。
- 生成式结果的 union 有三臂（`dsh-api-remotes/lib/client.js:13602`）：`{type:'baseline', value:{projections}}`、`{type:'projection', sessionId, key, value, seq}`、`{type:'assistant-stream', …}`。**实测 6 秒窗口内只观察到前两种**。
  ⚠️ 第三臂（`assistant-stream`）的触发条件与开关未知：`session/control` 没有 `assistantStream` 参数。猜测它只在某会话正在流式输出时才出现。想做打字机效果，**用 `session/follow` 的 `request.assistantStream:true`，不要赌 `session/control`**。

> 这条流是**会话列表实时刷新的最优解**：一次 `open` 就拿到全部会话的 `title`/`running` 相关投影/`tokenUsage`/`goal`/`todos`，不用轮询 `session/list`（实测 `session/list` 一次返回 **415 个会话**、约 1.4 MB，别轮询）。

### 3.7 其余流端点速查

| Endpoint | 首帧 | 后续 | 用途 |
|---|---|---|---|
| `session/follow` | `{type:'snapshot', header, cursor, records[], hasMore, projections}` | `{type:'event', event:{type,seq,time,data,...}}`、`{type:'assistant-stream', frame}` | 单会话历史 + 实时日志 |
| `session/control` | `{type:'baseline', value:{projections:{sid:block}}}` | `{type:'projection', sessionId, key, value, seq}` | 全机会话状态总线 |
| `workspace/follow` | `{type:'baseline', value:{items[], archivedSessionIds[], pinnedSessionIds[]}}` | `{type:'replace', value:{...同上}}` | 工作区列表 |
| `workspaceFiles/changes` | `{kind:'ready'}` | `{kind:'change', change:{absolutePath, version}\|{absolutePath, absent:true}}` | 单文件变更监听 |
| `job/list` | `{type:'rows', jobs:[...]}` | 同型整值帧 | 任务列表 |
| `job/follow` | 视 `request` 而定 | — | 单个任务输出流 |
| `terminal/attach` | — | — | 终端输出（uplink 输入） |
| `terminal/retain` | — | — | 终端保留输出 |
| `userQuestions/attachWait` | — | — | 等待某次提问被作答 |
| `account/watch` | `AccountView` | 整值 | 账号状态 |
| `account/watchExpiry` | — | — | 登录过期 |
| `productAnalytics/watchPolicy` | — | — | 埋点开关 |

---

## 4. 鉴权

### 4.1 Cookie 名字与值（唯一）

📖 `dsh-client-connection/lib/index.js:277`、`:335`、`:354-357`：

```
name  = "dsh-auth-" + base64url(sha256(authority))
value = "v" + version + "." + base64url(JSON payload) + "." + base64url(HMAC_SHA256(secret, base64url(JSON payload)))
```

- `authority`：HTTP 监听器是 **`host:port`（不带 scheme）**；HTTPS 监听器是 **`url.origin`（带 `https:` 前缀）**。见 `requestAudience`，`:307-316`。
  → 对 `http://127.0.0.1:27004`，authority 就是字符串 `127.0.0.1:27004`。
- `secret`：32 字节，来自 Harness Home 的凭据记录 `client-connection/browser-session`（`AUTH_RECORD_KEY`，`:273`；持久化在 `$DSH_HOME/.credentials.yaml`，形如 `kind: grant` / `payload: {version: 1, secret: <base64url 32B>}`）。由 `BrowserAuth.create` 在 Connection 激活时**加载或首次生成**（`:391-408`、`:432`）。
- payload 有两个版本（`decodeCookie`，`:358-390`）：

| version | 字段 | 含义 |
|---|---|---|
| `1` | `{version:1, authority, issuedAt, expiresAt}` | **浏览器会话 cookie**。持有者被当成共享的 `browserPeer`（owner、`interactions:'answer'`） |
| `2` | `{version:2, authority, issuedAt, expiresAt, id}` | **API peer cookie**。`id` 指向 `peers` 表里的一条记录，socket 关闭后该 id 失效 |

- 有效期：`cookieMaxAgeDays` 默认 **30 天**（schema 默认在 `:1017`，取值在 `:1030`）。校验还要求 `issuedAt <= now < expiresAt`、`expiresAt > issuedAt`、且 `expiresAt - issuedAt <= maxAge`，并且 payload 里的 `authority` 必须与本次请求算出的 authority **完全相等**（`:568`）。
- Cookie 属性（`:347-350`）：`Path=/; HttpOnly; SameSite=Strict`，HTTPS 监听器额外 `Secure`。**host-only**（不设 Domain）。

✅ 实测：用 `.credentials.yaml` 里的 secret 自铸 v1 cookie，`POST /api/session/list` 立刻返回 200；同一条 cookie 拿去 WS 升级也直接 101。

### 4.2 三种获取凭据的路径

| 路径 | 谁用 | 说明 | 出处 |
|---|---|---|---|
| **A. `GET /?token=<launchToken>`** | 浏览器 | 进程启动时生成的一次性 launch token；命中后 `303 → ./` 并 `Set-Cookie` 写入 **v1** cookie | `:458-492` |
| **B. `GET /connect?token=<launchToken>&interactions=answer\|none`** | 纯 API 客户端 | `302 → ./api/remote.mux` + `Set-Cookie` 写入 **v2** cookie（同时同步创建 API peer）。`interactions` 省略即 `none`；重复声明或非法值 → 400 | `:505-539` |
| **C. 脱离进程自铸** | 反向代理 / 原生客户端 | 直接读 `$DSH_HOME/.credentials.yaml` 的 secret，按 §4.1 自己算 v1 cookie | dsh-webim `lib/credentials.js:57-65` 就是这么干的 |

关键约束：
- **launch token 每进程随机**（`processLaunchToken`，`:294-300`，存在 WeakMap 里，不落盘），只能从 Host 打印的 URL 或 `/connect` 拿到。所以路径 C 是**唯一**不依赖 token 的方式。
- **HTTP 载体只接受 query token，不接受 `Authorization` 头**（README.zh.md:41："HTTP 载体只在根路径交换与 `/connect` 接受 query token，不接受 Authorization header token"）。
- `/` 的 token 交换**只允许 `GET`、只允许 pathname 恰为 `/`、只允许恰好一个 token 参数**（`:464`）。

> **IMDSH 该选哪条？**
> - 走 dsh-webim 中转（推荐，与现有产品一致）：dsh-webim 已经会用路径 C 铸 v1 cookie 再转发，IMDSH 只需要认 dsh-webim 自己的 `dsh_webim` cookie（`lib/config.js:15`）或配对码。
> - 直连本机 Harness：用路径 B（需要 launch token）或路径 C（需要读 `.credentials.yaml`，iOS 上不可行，除非通过 dsh-webim 代铸）。
>
> ⚠️ 注意 v1 与 v2 的**能力差异**（实测+源码双确认）：v1 → `interactions:'answer'`，可用 `$events`；v2 若 `interactions=none` → `$events` 直接报 `gateway/interactions-forbidden`，且该 peer 只能有一条 socket（第二条 409）。**IMDSH 应优先拿 v1 cookie。**

### 4.3 Host 栅栏（loopback 判定）

`isTrustedApiRequest`，`dsh-client-connection/lib/index.js:240-250`：

1. 必须有 `Host` 头，且能解析出 hostname。
2. 必须满足**三者之一**：
   - hostname 是 loopback —— 判定极窄，只有三种：`localhost`、`[::1]`、以及 `127.a.b.c`（四段且首段为 `"127"`）。见 `isLoopbackHostname`，`dsh-client-connection/lib/index.js:127-131`。**`0.0.0.0`、`[::]`、`::ffff:127.0.0.1`、`*.localhost` 都不算**（除非另外命中后两条）；
   - host:port 命中部署配置的 `trustedHosts`（保留字：条目是不带 scheme 的 `host` 或 `host:port`；不带端口则匹配任意端口），`isTrustedAuthority`，`:196-215`；
   - host 是 **webServer 自身 bind 地址**（`isBindAddressAuthority`，`:143` 附近）。
3. `Sec-Fetch-Site: cross-site` → 直接拒绝。
4. 若带 `Origin`，必须与 `Host` **同 authority**（scheme 按 origin 的 http/https 归一化，`isSameAuthorityOrigin`，`:258-269`）。没有 `Origin` 视为通过。

→ **对 IMDSH 的含义**：
- 直连 `127.0.0.1:27004`：天然过栅栏，但要记得请求里必须带 `Host`（URLSession 自动带）。
- 经 dsh-webim 反代：dsh-webim 会把 Host 改写成 loopback authority（`lib/index.js:165-166` 注释："The cookie the gateway presents to the local Harness. Always for the loopback authority, never the remote browser's own cookies"）。**IMDSH 侧看到的 Host 是 dsh-webim 的，Cookie 也是 dsh-webim 的**——两层各自一套。
- 栅栏失败是 **403**，鉴权失败是 **401**。这两个不要混。

### 4.4 Peer 语义（决定"能不能并发开多条 socket"）

`Peer` 的 `interactions` 默认 `'answer'`（`dsh-client-connection/lib/index.js:671`）。

| 凭据 | Peer | 可并发 socket | `$events` |
|---|---|---|---|
| v1 cookie | 共享 `browserPeer`（`principal:{kind:'owner'}`，`:714`） | ✅ 可以（不在 `peers` 表里，release 是 no-op，`:760-763`） | ✅ |
| v2 cookie，`interactions=answer` | 独立 API peer | ❌ 第二条 409（`:764`） | ✅ |
| v2 cookie，`interactions=none` | 独立 API peer | ❌ 第二条 409 | ❌（`gateway/interactions-forbidden`） |

✅ 实测：用 v1 cookie 在同一进程连开 4+ 条 socket，全部 101，无 409。

---

## 5. 数据模型

生成式类型的**原文**（TypeScript 声明）已提取到
`imdsh/docs/protocol-notes/typert-declarations.txt`（来自各包的 `lib/typert.host.js` 内嵌的
`"declaration"` 字符串）。以下为 IMDSH 需要的核心子集。

### 5.1 会话摘要（`session/list` 的 item）

📖 生成式 JSON Schema（`SessionListValue`）+ ✅ 实测字段：

```jsonc
{
  "sessionId": "session-2daf9cab-...",   // string，必填
  "updatedAt": 1793477997507,            // number，epoch ms，必填
  "agentAvailable": true,                 // bool，必填：当前是否持有活 Agent
  "running": true,                        // bool，必填：是否正在跑 turn
  "blank": false,                         // bool，必填：折叠前缀里没有 turn
  "formatStatus": "current",              // "current"|"migration-required"，可选
  "parentSessionId": "session-2daf9...",  // 可选：subagent 才有
  "origin": "subagent",                   // 可选：仅当是子代理会话时出现（字面量 "subagent"）
  "cwd": "C:\\Users\\you\\Desktop\\dsh-webim", // 可选
  "projections": {                        // 可选（列表页的轻量投影）
    "kind": "sequenced",                  // "sequenced" | "cached"
    "asOfSeq": 257,
    "values": { /* 见 §5.4 投影键 */ }
  }
}
```

> ⚠️ `projections.kind` 的语义差异很重要（生成式描述原文）：`sequenced` = 活注册表产出，`asOfSeq` 与同一连接内的 baseline/frame 可比；`cached` = 只读持久化投影缓存，`asOfSeq` **不可**跨空间比较。IMDSH 只做展示时无所谓，要做增量合并就必须判 `kind`。
>
> 实测规模警告：415 个会话时一次 `session/list` ≈ 1.4 MB。**列表页请优先 `session/control` 的 baseline。**

### 5.2 会话日志事件（`session/follow` / `session/page` 的 record）

信封（`SessionEvent`）：

```jsonc
{
  "type": "event",
  "event": {
    "type": "assistant/message",   // string，事件类型，见下表
    "seq": 551,                    // number，单调递增的会话内序号（游标）
    "time": 1793478285183,         // number，epoch ms
    "data": { ... },               // 该事件类型的载荷（any）
    "ignorable": true,             // 可选：未知类型可安全忽略
    "sourceEventSeqs": [ ... ],    // 可选：surface 事件的来源 seq
    "surfaceOp": { ... }           // 可选：在"当前表面对话"里的规范位置
  }
}
```

`SessionEventMap` 的**完整类型表**（📖 `dsh-client-file-upload/lib/typert.host.js:606`）：

| 事件 | data 形状 |
|---|---|
| `turn/start` | `{turn:number}` |
| `turn/end` | `{turn:number, reason:TurnEndReason}` |
| `step/start` / `step/end` | `{turn, step}` |
| `user/message` | `UserMessage` |
| `developer/message` | `{turn, step, message:DeveloperMessage, headerSeq?}` |
| `system/message` | `{turn, step, message:SystemMessage}` |
| `assistant/message` | `{turn, step, message:AssistantMessage, stream:AssistantStreamRecord[], usage?:TokenUsage, interrupted?:true}` |
| `assistant/attempt` | `{turn, step, stream:AssistantStreamRecord[]}` |
| `tool/call` | `{turn, step, callId, name, arguments:string}` |
| `tool/result` | `{turn, step, message:ToolResultMessage, error?:{name,code,reason?}, meta?}` |
| `request/header` / `request/context` | 请求信封（模型入参快照） |
| `session/end-seed` | fork 继承标记 |
| `agent/inbox/spliced` | 待发队列变更 |
| `working-directory/change` | `{cwd}` |
| `sandbox/mode` / `approval/policy` / `permission/preset` | 三个整值开关 |
| `approval/asked` / `approval/decided` | 审批 |
| `tool/ptc-dispatch*` | PTC 分发 |
| `agent-preset/selected` | `{agentPreset}` |
| `job/registered` / `job/settled` | 后台任务 |
| `command/run` / `command/done` | 斜杠命令 |
| `image/offload` | 图片外置 |
| `session/title` | `{title, messageSeqs, source}` |
| `todo/write` | `{todos:TodoItem[]}`（**整值替换**，last-wins） |
| `model/selection` | `ModelSelection` |
| `subagent/descriptor` / `subagent/catalog` / `subagent/model-selection-policy` | 子代理 |
| `compaction/start` / `summary` / `end` / `prune` | 上下文压缩 |
| `llm/retry` / `llm/retry-started` | 重试 |
| `team/member` / `team/task` / `team/message/queued` / `team/message/delivered` | 团队 |
| `goal/change` | 目标变更 |
| `feedback/record` / `feedback/message-put` / `feedback/message-delete` | 消息反馈 |
| `plan/mode` | `{active:boolean}` |
| `schedule/change` | 定时任务 |
| `workspace/changes` | `{turn}` |

**"当前表面对话"白名单**（`SurfaceEventType`，📖 `dsh-client-file-upload/lib/typert.host.js:682`）：
`system/message` · `developer/message` · `user/message` · `assistant/message` · `tool/result`
—— 只有这 5 类进"聊天记录"视图；其余都是旁路事件。IMDSH 的聊天列表应当**只渲染这 5 类**，其余进"详情/调试"或直接忽略（注意 `ignorable` 标记：新版本加的事件类型会带 `ignorable:true`，老客户端可安全跳过）。

### 5.3 消息与内容块

```ts
interface MessageBase { id: MessageId; content: readonly ContentBlock[]; source: MessageSource }
interface UserMessage      extends MessageBase { role: 'user' }
interface AssistantMessage extends MessageBase { role: 'assistant'; source: ModelMessageSource }
interface ToolResultMessage extends MessageBase { role: 'tool'; toolCallId: ToolCallId; isError?: boolean; source: ToolMessageSource }
```

内容块（`ContentBlockMap`，📖 `dsh-client-file-upload/lib/typert.host.js:339`）：

```ts
type ContentBlock =
  | { type: 'text';            text: string }
  | { type: 'reasoning';       text: string }
  | { type: 'image';           attachment: ImageAttachmentRef; offloaded?: true }
  | { type: 'file';            attachment: FileAttachmentRef }
  | { type: 'tool-call';       id: ToolCallId; name: string; arguments: string }  // arguments 是 JSON 字符串
  | { type: 'tool-addition';   toolName: string }
  | { type: 'tool-removal';    toolName: string };

interface ImageAttachmentRef { attachmentId; mediaType: 'image/png'|'image/jpeg'|'image/webp'|'image/gif';
                               bytes: number; width: number; height: number; name?: string;
                               originalDimensions?: {width,height} }
interface FileAttachmentRef  { attachmentId; name: string; bytes: number }
```

`MessageSource`（决定气泡归属/样式）：

```ts
{kind:'user'} | {kind:'model', provider, model, replayState?} | {kind:'tool', callId}
| {kind:'system-prompt'} | {kind:'model-selection'} & ContextFormed
| {kind:'runtime-context'} & ContextFormed | {kind:'working-directory'}
| {kind:'user-approval'} & ContextFormed | {kind:'ptc-mode'} | {kind:'tool-registry'}
| {kind:'user', rpcId, clientTimeZone?, principal?}     // ← 人类通过 RPC 提交的 prompt 是这一支
| {kind:'agent-message', form:'relay', senderSessionId}
```

**流式增量**（`AssistantStreamRecord` / `StreamChunk`，📖 `dsh-client-file-upload/lib/typert.host.js:206`、`:478` 附近）：

```ts
type AssistantStreamRecord =
  | { type:'text-chunks';      time0; index; dt: number[]; texts: string[] }     // dt=相对时间，批量化
  | { type:'reasoning-chunks'; time0; index; dt: number[]; texts: string[] }
  | { type:'tool-call-chunks'; time0; index; dt: number[]; id; name?; args: string[] }
  | { type:'chunk';            time; chunk: StreamChunk }

type StreamChunk =
  | { type:'block-start'; index; blockType: ContentBlockType }
  | { type:'text-delta'; index; text }
  | { type:'reasoning-delta'; index; text }
  | { type:'tool-call-delta'; index; id; name?; argumentsDelta }
  | { type:'block-end'; index; block: ContentBlock }
  | { type:'usage'; usage: TokenUsage }
  | { type:'finish'; reason: FinishReason; replayState? }
```

> 语义要点：`assistant/message` 是**提交后**的完整消息（终态）；流式过程要么来自 `session/control` 的 `assistant-stream` 帧（本流的第三臂），要么来自 `session/follow` 且 `request.assistantStream:true` 时的 `{type:'assistant-stream', frame}` item。IMDSH 做打字机效果走后者；只做"整条消息到达即渲染"则完全不需要。

`TokenUsage`：`{inputTokens, outputTokens, totalTokens?, cacheReadTokens?, cacheWriteTokens?, reasoningTokens?}`。

`TurnEndReason`：`{kind:'completed'}` | `{kind:'aborted', reason:AgentCancelCause}` | `{kind:'blocked'}` | `{kind:'error', error:LlmFailure}` | `{kind:'max-tokens'}` | `{kind:'interrupted'}` | `{kind:'forked'}`。

### 5.4 投影键（`projections.values` / `session/control` 的 `key`）

✅ 实测 `session/control` baseline 里出现过的 keys（26 项中的常用子集）：

```
title · goal · tokenUsage · contextPressure · contextBreakdown · inbox · sessionStats
turnOutline · agentPreset · userQuestions · permissions · workingDirectory · subagentCatalog
subagentTiming · subagent · agentTeam · costUsage · todos · plan · modelSelection
sessionListMetadata · imageLimits · contextTimeline · contextHeaders · contextActivity
```

IMDSH 会话列表页需要的：`title`、`sessionListMetadata.{blank,lastPromptAt}`、`todos`、`permissions.currentValue`、`modelSelection`、`tokenUsage`、`goal`。

### 5.5 工作区 / 文件

```ts
interface Workspace { workspaceId; path; title; sessionIds: string[];
                      createdAt: ISO8601; updatedAt: ISO8601 }   // createdAt/updatedAt 是字符串！
```

工作区文件（`@deepseek-ai/dsh-api-workspace-files`）：

```ts
interface WorkspaceDirectoryListing { path: string;   // 相对工作区根；根本身为 ""
                                     entries: { name; type:'file'|'directory'|'other'; size?: number }[];
                                     truncated: boolean }
interface WorkspaceFileStat  { absolutePath; version; bytes? } // version 是不透明新鲜度令牌
interface WorkspaceFileText  extends WorkspaceFileStat {
    offset: number; text: string; lines: number; eof: boolean; bytes?: number }
interface WorkspaceFileBytes extends WorkspaceFileStat { data: Uint8Array }  // ← 走 multipart
interface WorkspaceFileRange { offset?: number /*默认1*/; limit?: number /*默认=maxLines*/ }
interface WorkspaceByteRange { offset?: number /*默认0*/; length?: number }
type WorkspaceFileWatchFrame = {kind:'ready'} | {kind:'change', change:WorkspaceFileChange}
type WorkspaceFileChange = {absolutePath, version} | {absolutePath, absent:true}
```

✅ 实测 `workspaceFiles/list` 返回：

```json
{"path":"","entries":[{"name":".git","type":"directory"},{"name":".gitattributes","type":"file","size":133}, ...],
 "truncated":false}
```

⚠️ 所有 `workspaceFiles/*` 的**第一个参数不是普通 JSON**，而是 `workspaceFileScopeId`（`source: "lookup"`，wire 名 `workspaceFileScopeId`，类型 `SessionId`）。含义是"以该会话为上下文解析工作区根"，描述原文：*header-derived workspace root for the Session identity on the wire*。踩坑点：`path` 字段**必须显式出现**，不能省略（✅ 实测省略报 `{"code":"gateway/bad-request","message":"path is required"}`）；想列根目录就传 `""` 或 `"."`（实测 `"."` → 返回 `path:""` 的根列表）。

### 5.6 设置

`settings/describe` 返回：

```jsonc
{"writable": true, "hasDocument": true, "namespaces": [
  {"ns": "agent-default-model", "autoGenerate": false,
   "schema": {"uid": 243549, "refs": {"243546": {"type":"string","meta":{"required":true}}, ...}},
   "value": {"provider":"tianxing","model":"deepseek-v4.1-flash","reasoningEffort":"high"},
   "base":  {"provider":"deepseek-official","model":"deepseek-flash"},
   "user":  {"provider":"tianxing", ...},          // 出现即"用户覆盖"
   "applies": "live",
   "secrets": [{"path":["apiKey"],"set":true}],    // 只报存在性，永不回传值
   "revision": 0}
]}
```

- `schema` 是 schemastery 的 `schema.toJSON()` 信封（`{uid, refs:{...}, dict?, meta?}`），**要自己重建表单**。IMDSH 若不做通用设置编辑器，可以只认少数几个 namespace 硬编码表单。
- 写入时把读到的 `revision` 作为 `expectedRevision` 回传，否则并发编辑会被拒绝（生成式描述原文）。传 `undefined` = 无条件写。
- 三个写方法：`settings/update`（merge patch）、`settings/replace`（整段替换 user section）、`settings/mutate`（路径操作 `set`/`unset`）。全部返回 `SettingsNamespaceView`（即上面那个 namespace 对象的新状态）。
- ✅ 实测 26 个 namespace、`writable: true`。

---

## 6. 会话历史与实时协议（IMDSH 的核心）

### 6.1 打开一个会话：`session/follow` 的 snapshot

✅ 实测（`protocol-notes/probe-history.out.txt`）：

```json
{"type":"item","streamId":"follow-1","value":{
  "type":"snapshot",
  "header":{"version":4,"id":"session-2daf9cab-fdaa-420d-99d8-67ddf8b1616e",
            "createdAt":1792849988283,"cwd":"C:\\Users\\you\\Desktop\\dsh-webim",
            "isSeeded":false,"delegationDepth":0,"agentPreset":"standard"},
  "cursor":574,
  "hasMore":true,
  "records":[{"type":"event","event":{"type":"assistant/message","seq":551,...}}, ... 共 24 条],
  "projections":{"asOfSeq":562,"values":{ /* §5.4 全部键 */ }}
}}
```

- `header.version` 当前是 **4**（会话持久化格式版本）。
- `cursor` = 已投递到的最大 `seq`。**这个数就是后续翻页的 `throughSeq`。**
- `hasMore` = 还有更老的历史。
- `maxMessages` 控制首屏深度（实测传 2/4 都拿到"按消息对齐"的一批，实际条数会多于该值，因为要对齐到 turn 边界）。

`SessionFollowRequest`：

```jsonc
{"request": {
  "address": {"kind":"session","sessionId":"..."},
  // 或 {"kind":"subagent","parentSessionId":"...","childSessionId":"...","mode":"one-shot"|"continuable"|"unknown"}
  "assistantStream": true,      // 可选：带流式增量帧（仅 Web 客户端需要）
  "maxMessages": 4,             // 可选
  "turnWindow": {"minMessages":n,"minTurns":m}  // 可选：按 turn 边界收敛深度
}}
```

> **子会话坑**：`address.kind:"subagent"` 的会话（`session/list` 里 `origin:"subagent"`）**不能**用 `kind:'session'` 打开。✅ 实测错误：
> `{"code":"session/agent-busy","message":"subagent Sessions require their durable parent address","details":{"reason":"use subagent delivery for this child session"}}`
> IMDSH 打开会话前必须先判 `origin`/`parentSessionId`，选择正确的 address 分支。

### 6.2 向前翻页：`session/page`

✅ 实测：先用 follow 的 `cursor` 作 `throughSeq`，`session/page` 返回**截止到该游标且包含该游标**的一页，seq 连续升序：

```
throughSeq=574, maxMessages=3 → 19 条 records
  seq = [556,557,558,...,573,574]   hasMore=true   max(seq) <= 574 ✔ 且末条恰为 574
throughSeq=556, maxMessages=3 → 11 条 records
  seq = [546,547,...,555,556]       hasMore=true   max(seq) <= 556 ✔ 且末条恰为 556
```

→ **翻页算法**：`throughSeq` 取"已持有最老 seq − 1"，页内首条即新的最老 seq。注意 `maxMessages=3` 实际给了 19 条（按消息/turn 边界对齐，不是按事件条数），所以**不要用返回条数判断是否到底，只信 `hasMore`**。

```jsonc
// 请求 args
{"request":{
  "address":{"kind":"session","sessionId":"..."},
  "throughSeq":574,        // 必填！来自 follow 的 snapshot.cursor（或"已持有最老 seq - 1"）
  "beforeSeq":556,         // 可选：这一页的下界（不含）
  "maxMessages":3,         // 可选
  "turnWindow":{"minMessages":n,"minTurns":m}  // 可选
}}
// 返回
{"records":[{"type":"event","event":{...}}, ...], "hasMore":true}
```

- **`throughSeq` 是必填字段**（`required:["address","throughSeq"]`）。缺了会 `gateway/input-invalid`（✅ 实测：`"wire field \"request\" failed boundary validation"`）。
- `SessionPage.records` 与 `session/follow` 的 `records` **同构**（都是 `{type:'event', event:{...}}`）。
- 翻页方向是"向更老"，游标用返回页里最小 `seq` 继续往前（或直接给 `beforeSeq`）。
- 设计意图（生成式描述原文）：*Read one cold-safe, message-aligned Session history page* —— 不需要唤醒 Agent 就能读历史。

### 6.3 实时增量

follow 流保持打开后，新事件以 `{"type":"item",...,"value":{"type":"event","event":{...}}}` 到达。游标 = `event.seq` 单调递增。

**gap 修复**：若发现 `seq` 跳号（例如 socket 抖动后重连），浏览器侧的做法是重开流并用 snapshot 重新对齐（`journal-stream.js:8-14` 注释："A replacement is published only after the opening page reaches the generation's cursor"）。IMDSH 照做即可。

### 6.4 发送一条消息：`session/prompt`

📖 契约（`SessionPromptRequest`）：

```jsonc
{
  "requestId": "<客户端铸造的唯一 id，会持久化到那条 user message 上>",   // 必填
  "sessionId": "...",                                                   // 必填
  "mode": "queue" | "steer",                                            // 必填
  "content": [ ... ],                                                   // 必填，至少一个非空白 text 或附件
  "clientTimeZone": "Asia/Hong_Kong"                                    // 可选
}
// content 元素（三选一，additionalProperties:false）
{"type":"text","text":"..."}
{"type":"image","mediaType":"image/png","data":"<base64>","name":"..."}   // data 是 base64
{"type":"file","receiptId":"<fileUploads/upload 返回的 receiptId>"}
```

返回：`{"accepted": true}`。

- `mode`：`queue` = 排到下一个 turn；`steer` = 抢占最近一个 step（相当于"打断并插入"）。
- `requestId` 必须客户端自己生成并**去重**——它是幂等键（持久化在消息上，便于重试后对账）。
- ⚠️ 未实测（发消息会真的驱动 Agent，属于副作用操作，本次只做只读探测）。契约本身来自编译器产物，可信度高。

### 6.5 中断生成：`session/cancel`

```jsonc
// args
{"request": {"sessionId": "..."}}
// 返回
{"accepted": true}
```

✅ 契约确认（`session_cancel_*$schema`，`dsh-api-remotes/lib/client.js:13595-13598`）。
⚠️ 未实测（同上，有副作用）。

### 6.6 会话生命周期其它方法

| Endpoint | args | 返回 | 备注 |
|---|---|---|---|
| `session/create` | `{request:{workspaceId?,cwd?,sessionId?,agentPreset?}}` | `{sessionId, agentPreset?}` | `workspaceId` 与 `cwd` 互斥；可复用空白会话 |
| `session/rename` | `{request:{sessionId,title}}` | `{title,seq}` | 内部是发一条 `session/title` 事件 |
| `session/fork` | `{request:{sessionId,atSeq?,allowMigration?}}` | `{sessionId}` | 从某条 seq 分叉 |
| `session/projections` | `{request:{sessionId}}` | `null` \| `{asOfSeq,values}` | 冷读投影（不唤醒 Agent） |
| `session/updateQueue` | `{request:{sessionId,itemId,action}}` | `{accepted:true}` | `action` = `{kind:'edit',content:[…text]}` \| `{kind:'remove'}` \| `{kind:'steer'}` |
| `session/search` | `{query}` | `{items:[{sessionId,snippet}],hasMore}` | 全文搜索 |
| `session/modelCatalog` | `{}` | `ModelCatalog` | ✅ 实测：`default`/`groups[]`/`routableProviders[]`/`failures[]` |
| `session/selectModel` | `{request:{sessionId,provider,model,reasoningEffort?}}` | `{selected}` | |
| `session/attachment` | `{request:{sessionId,attachmentId}}` | `{attachment:{…ref}, data:string}` | 取回图片 base64（⚠️ `data` 编码未在描述里写明，推断为 base64，见 §10） |

---

## 7. IMDSH 必调 RPC 清单

> **总端点 135 个 / 26 个 package**。全表见 `protocol-notes/endpoints.index.txt`。
> 下表是 IMDSH 实现「会话列表 + 聊天 + 文件 + 设置」所需的最小闭包，共 **30 个**。
> 所有请求都发往 `POST http://<host>/api/<endpoint>`，body 统一为
> `{"type":"client-request","rpcId":"<uuid>","method":"<endpoint>","payload":{"args":{…}}}`。
> 下表「args」列就是 `payload.args` 的内容。

### 7.1 会话（11）

| # | endpoint | args 示例 | 返回（要点） |
|---|---|---|---|
| 1 | `session/list` | `{"_request":{}}` | `{items:[SessionSummary]}`（⚠️ `_request` 必填） |
| 2 | `session/create` | `{"request":{"cwd":"C:\\proj","agentPreset":"standard"}}` | `{sessionId, agentPreset?}` |
| 3 | `session/follow` ★流 | `{"request":{"address":{"kind":"session","sessionId":"S"},"maxMessages":20,"assistantStream":true}}` | 先 `snapshot`，后 `event`/`assistant-stream` |
| 4 | `session/page` | `{"request":{"address":{"kind":"session","sessionId":"S"},"throughSeq":574,"beforeSeq":556,"maxMessages":20}}` | `{records:[{type:"event",event}], hasMore}` |
| 5 | `session/projections` | `{"request":{"sessionId":"S"}}` | `null` 或 `{asOfSeq, values}` |
| 6 | `session/prompt` | `{"request":{"requestId":"<uuid>","sessionId":"S","mode":"queue","content":[{"type":"text","text":"hi"}],"clientTimeZone":"Asia/Hong_Kong"}}` | `{accepted:true}` |
| 7 | `session/cancel` | `{"request":{"sessionId":"S"}}` | `{accepted:true}` |
| 8 | `session/rename` | `{"request":{"sessionId":"S","title":"新标题"}}` | `{title, seq}` |
| 9 | `session/selectModel` | `{"request":{"sessionId":"S","provider":"deepseek-account","model":"deepseek-flash","reasoningEffort":"high"}}` | `{selected:{provider,model,reasoningEffort?}}` |
| 10 | `session/modelCatalog` | `{}` | `{default, routableProviders[], groups[{id,name,models[{id,name,description?,reasoning?}]}], failures[]}` |
| 11 | `session/control` ★流 | `{}`（必须是空对象！） | 先 `baseline{projections:{sid:block}}`，后 `projection{sessionId,key,value,seq}` |

### 7.2 工作区与文件（7）

| # | endpoint | args 示例 | 返回 |
|---|---|---|---|
| 12 | `workspace/follow` ★流 | `{}` | `baseline{items,archivedSessionIds,pinnedSessionIds}` / `replace{…}` |
| 13 | `workspace/create` | `{"request":{"path":"C:\\proj"}}` | `{workspace, created}` |
| 14 | `workspace/rename` | `{"request":{"workspaceId":"W","title":"改名"}}` | 同 workspace 结构 |
| 15 | `workspaceFiles/list` | `{"workspaceFileScopeId":"S","path":""}` | `{path, entries[{name,type,size?}], truncated}` |
| 16 | `workspaceFiles/read` | `{"workspaceFileScopeId":"S","path":"src/main.m","range":{"offset":1,"limit":2000}}` | `{offset,text,lines,eof,absolutePath,version,bytes?}` |
| 17 | `workspaceFiles/stat` | `{"workspaceFileScopeId":"S","path":"a.txt"}` | `{absolutePath,version,bytes?}` |
| 18 | `workspaceFiles/changes` ★流 | `{"workspaceFileScopeId":"S","path":"a.txt"}` | `{kind:'ready'}` 后跟 `{kind:'change',change}` |

### 7.3 设置与插件（6）

| # | endpoint | args 示例 | 返回 |
|---|---|---|---|
| 19 | `settings/describe` | `{}` | `{writable,hasDocument,namespaces[SettingsNamespaceView]}` |
| 20 | `settings/update` | `{"ns":"agent-default-model","patch":{"provider":"tianxing"},"expectedRevision":0}` | `SettingsNamespaceView` |
| 21 | `settings/replace` | `{"ns":"…","section":{…},"expectedRevision":n}` | `SettingsNamespaceView` |
| 22 | `pluginManager/listPlugins` | `{}` | **数组**，元素为两臂 union：`{entryId, moduleName, meta?:{title?,description?,icon?,error?}, enabled, fiberPhase:null|"failed"|"pending"|"active"|"loading"|"unloading", patchId, readOnlyReason?:never}` 或 `{…同上但 patchId?:never, readOnlyReason:"management-required"\|"unaddressable"}`（⚠️ 该结果无 JSON-Schema 投影，形状来自 `dsh-api-remotes/lib/client.js:10115-10155` 的 Zod） |
| 23 | `pluginManager/setPluginEnabled` | `{"id":"<PluginEntryId>","enabled":true}` | `ChangeResult` |
| 24 | `pluginInventory/list` | `{}` | `PluginInventorySnapshot` |

### 7.4 附件、反馈与通知（6）

| # | endpoint | args 示例 | 返回 |
|---|---|---|---|
| 25 | `fileUploads/upload` | `{"agentId":"S","request":{"data":"<base64>","name":"报告.pdf"}}` | `{receiptId, file:{attachmentId,name,bytes}}` |
| 26 | `session/attachment` | `{"request":{"sessionId":"S","attachmentId":"A"}}` | `{attachment:{attachmentId,mediaType,bytes,width,height,name?}, data}` |
| 27 | `$events` ★流 | `{}`（必须是空对象） | `ready{clientId,host}`，后跟 `emit`/`waterfall` |
| 28 | `$events/result` | `{"clientId":"C","eventId":"E","outcome":{"kind":"next"}}` | `void` |
| 29 | `messageFeedback/put` | `{"request":{"sessionId":"S","messageId":"M","rating":"positive","note":"…","category":"task-result","ifVersion":"<上次返回的版本或 null>"}}` | `{ok:true, value:{messageId,rating,note?,category?,version}}`；`rating` = `"positive"`\|`"negative"`；`category` ∈ `other,task-result,instruction-following,product-interaction,service-stability,resource-cost,security-privacy-permission` |
| 30 | `permissionPresets/catalog` | `{}` | `PermissionCatalog` |

> ★流 = 必须走 WS `/api/remote.mux`（`open` 帧），其余走 HTTP。
>
> **`$events/result` 的 args 形状特殊**：它是网关内部端点，没有命名参数，`payload` 仍然带 `args` 外壳（校验器 `parseRemoteEventResultPayload` 要求 `payload` 的键集合恰好只有 `args`），而 `args` 本身是 `{clientId, eventId, outcome}` 三个键、缺一不可、不许多（`parseRemoteEventResult`，`dsh-api-gateway/lib/types/stream-protocol.js:18-24`）。
> 即：`{"type":"client-request","rpcId":"…","method":"$events/result","payload":{"args":{"clientId":"…","eventId":"…","outcome":{"kind":"next"}}}}`

### 7.5 调用顺序建议（冷启动）

```
1. GET / 或 /connect 拿 Cookie                （§4.2）
2. WS connect /api/remote.mux                 （§3.1）
   ├─ open "$events"        → 等 ready
   ├─ open "session/control"→ 等 baseline       ← 会话列表在这里就有数据了
   └─ open "workspace/follow"→ 等 baseline      ← 工作区选择器
3. 用户点开某会话：
   ├─ open "session/follow" {request:{address,…}} → snapshot 渲染首屏
   └─ 之后 event 增量追加
4. 上滑加载更早：HTTP session/page {throughSeq:<snapshot.cursor>, beforeSeq:<最老 seq>}
5. 打开文件面板：HTTP workspaceFiles/list / read；要实时：open "workspaceFiles/changes"
6. 发消息：HTTP session/prompt（图片先内联 base64；文件先 fileUploads/upload 拿 receiptId）
7. 停止：HTTP session/cancel
```

---

## 8. 附件、图片与二进制

### 8.1 图片：内联 base64（没有独立上传步骤）

`session/prompt` 的 `content` 支持 `{"type":"image","mediaType":…,"data":"<base64>"}`，`dsh-api-remotes/lib/client.js:13602` 附近的 Zod 与 `SessionPromptRequest` 的 JSON Schema 均确认 `data` 是字符串（描述原文："Declared media type, verified against the decoded bytes during admission" —— 服务端会**解码后校验**真实格式）。

限制来自投影里的 `imageLimits`（✅ 实测字段）：

```json
{"maxImageBytes":…, "maxImagesPerMessage":…, "maxMessageImageBytes":…, "maxImagePixels":…,
 "maxImageDimension":…, "mediaTypes":["image/png","image/jpeg","image/webp","image/gif"]}
```

IMDSH 应该在打开会话时从 `projections.values.imageLimits` 读这些数并做前置校验（别硬编码）。

### 8.2 文件：先上传拿收据

`fileUploads/upload`（📖 `EncodedFileUploadRequest`）：

```jsonc
{"agentId":"<SessionId>","request":{"data":"<完整文件字节的规范 base64>","name":"报告.pdf"}}
→ {"receiptId":"…","file":{"attachmentId":"…","name":"报告.pdf","bytes":12345}}
```

- `agentId` 是 **lookup 参数**（`source:"lookup"`，wire 名 `agentId`），即目标会话 id。
- `receiptId` **只在接收方 Agent 作用域内有效**（"Per-upload authority accepted only inside the receiving Agent scope"）。所以上传和 prompt 必须针对同一会话。
- prompt 里用 `{"type":"file","receiptId":"…"}` 引用。
- 上限同样受 300 MiB body 与 base64 膨胀约束。

### 8.3 二进制读取

`workspaceFiles/readBytes` 的返回含 `Uint8Array` → **multipart 回包**（§2.4）。args：

```jsonc
{"workspaceFileScopeId":"S","path":"img.png","options":{"range":{"offset":0,"length":65536},"baseFile":"src/a.m"}}
```

`baseFile` 的作用：让相对 `path` 从 `baseFile` 所在目录解析（生成式描述原文）。省略则相对工作区根。

---

## 9. 错误码表

信封内错误码（`result.error.code`）无一例外出现在 HTTP **200** 响应里。

### 9.1 网关层 `gateway/*`

| code | 含义 / 触发 | 出处 |
|---|---|---|
| `gateway/bad-request` | 信封非法；`method` 与 URL endpoint 不一致；某些端点自报的字段缺失（如 `workspaceFiles/list` 的 `"path is required"`） | `:904`；✅ 实测 |
| `gateway/arguments-invalid` | `args` 的字段集合与描述符不匹配（缺字段/多字段） | `dsh-api-gateway/lib/index.js:994`；✅ 实测 |
| `gateway/input-invalid` | 字段存在但**值**过不了 codec 校验（`details.field` 指出是哪个） | ✅ 实测 |
| `gateway/result-invalid` | Host 返回值过不了 result codec | 源码 |
| `gateway/internal` | 未分类内部错误（也用于流协议违规） | `journal-stream.js:6` |
| `gateway/cancelled` | 调用被取消 | 源码 |
| `gateway/service-unavailable` | `$events` 的 Host 事件源未注册 | `index.js:996` |
| `gateway/invocation-unavailable` | 该方法在当前 Peer 下不可调用 | `index.js:965` |
| `gateway/interactions-forbidden` | Peer 的 `interactions` 不满足要求（如 `$events` 遇到 `none`） | `index.js:969` |
| `gateway/method-unavailable` / `gateway/definition-unavailable` | 方法/描述符不可用 | 源码 |
| `gateway/lookup-unavailable` / `lookup-failed` / `lookup-not-found` | lookup 参数解析失败 | 源码 |
| `gateway/context-unavailable` / `context-not-found` / `context-failed` | Context 调用解析失败 | 源码 |
| `gateway/binding-invalid` / `gateway/provider-mismatch` / `gateway/ambiguous-endpoint` | 注册期/描述符绑定问题 | 源码 |
| `gateway/signature-invalid` | 描述符签名不匹配（启动期） | 源码 |
| `gateway/peer-disposed` | Peer 已销毁 | 源码 |
| `gateway/uplink-overflow` | WS 上行缓冲超限（默认 256 KiB/流） | `stream-server.js` |
| `gateway/protocol` | 流协议违规 | 源码 |
| `remote-access/denied` | 非 owner Peer 被访问控制拒绝 | `access.js` |

### 9.2 领域层（示例）

| code | 出处 |
|---|---|
| `session/agent-busy` | ✅ 实测：subagent 会话需要父地址 |
| 其余领域码由各 `api-*` 包自定，无集中清单 | ⚠️ 建议 IMDSH 对未知 code 一律当"展示 message + 上报 details"处理，不要按 code 分支做关键逻辑 |

> 判断策略：**只对 `gateway/arguments-invalid` / `gateway/input-invalid` / `gateway/bad-request` 做程序化处理（说明我方构造错了），其余原样展示 `message`。**

---

## 10. 未确认清单与实测方法

| # | 未确认项 | 置信度 | 如何实测 |
|---|---|---|---|
| 1 | `session/attachment` 返回的 `data` 是否为 base64（描述里未写） | 高（同族 `EncodedFileUploadRequest.data` 明确是 base64；`attachmentId` "never a bearer URL"） | 找一条带图片的会话 → 从 `user/message` 的 `content[].attachment.attachmentId` 调一次，看 `data` 前 4 字符是否是 PNG/JPEG 的 base64 头（`iVBOR…` / `/9j/`） |
| 2 | multipart 回包里 `attachment.path` 的实际下标布局 | 中（解码规则确定，但实际 path 值未观测） | 调 `workspaceFiles/readBytes` 读一个小文件，抓原始响应体看 `metadata` 里的 `attachments[0].path` |
| 3 | `session/control` 是否会发 `assistant-stream` 帧 | 中 | 让某个会话真正在流式输出时开 `session/control`，观察 value.type 是否出现 `assistant-stream` |
| 4 | `session/prompt` / `session/cancel` 的端到端行为 | 高（契约来自编译器产物） | 用一个专用测试会话发一条无害 prompt（例如 "回复 ok 即可"），观察 follow 流里的 `user/message`、`turn/start`、`assistant/message`、`turn/end` |
| 5 | `queue` vs `steer` 在 UI 上的可观察差异 | 中 | 在 Agent 正在跑时分别用两种 mode 发消息，看 `agent/inbox/spliced` 与 `turn/start` 的时序 |
| 6 | ~~`session/page` 返回页的 `seq` 边界~~ | ✅ **已实测确认**：`max(seq) == throughSeq`，页内连续升序 | `tools/probe-page-seqs.mjs` |
| 7 | `workspaceFiles/read` 的 `maxLines` 配置值 | 低（部署相关） | 故意传 `limit` 超大 → 看是否被裁剪，或读 `stat.bytes` 推断 |
| 8 | 常见 `emit` 帧的 `args` 精确形状（例如 `api-session/status`、`settings/document-updated`） | 中（帧骨架 `{type:'emit', event, args}` 已由源码确认） | 挂 30s 以上，触发 `api-session/activity`（发一条 prompt）与 `settings/document-updated`（改一次设置），记录 `args` |
| 9 | 关闭码 `4002` | 无需实测：它是**浏览器参考实现自己**发出的码（`client/stream-client.js:321`），服务端从不发。IMDSH 可以照用，也可以不用 | — |
| 10 | HTTPS 监听器下 Cookie authority 带 `https:` 前缀的实际字符串 | 高（源码明写 `url.origin`） | 启用 TLS 监听，抓 `Set-Cookie` 的 name 段与 payload.authority |
| 11 | 前端 bundle 的真实 RPC 调用点 | 已定论：`dsh-web-frontend/dist/assets/*` 不含 RPC（§0.3） | 若要，可解包各 `dsh-client-*` 包的 `lib/client.js`（`window.__ModuleLoader__.load` 形态） |
| 12 | **29 个端点的结果没有 JSON-Schema 投影**（Zod 里有，但 `toJSONSchema` 无法表达：`Uint8Array`、`never`/union、`z.any()` 字典等）。清单：`productAnalytics/report`、`commands/execute`、`credentials/*`(3)、`officeToPdf/render`、`goals/get`、`schedule/history|update`、`pluginManager/*`(10)、`pluginMarket/*`(3)、`pluginInventory/list`、`session/control`、`session/initializeDefaultModel`、`workspace/initializeDefault`、`terminal/close|rename`、`workspaceFiles/changes|readBytes` | 高（形状仍可在 Zod 源码里逐字读到） | 需要时读 `dsh-api-remotes/lib/client.js` 里对应 `_…_result$schema` 的 `zod.z.*` 定义（本文已就 `pluginManager/listPlugins`、`session/control` 两条做过） |

### 10.1 本次使用的探测脚本（可复跑）

全部在 `imdsh/docs/protocol-notes/tools/`，**只读**，不改任何状态：

| 脚本 | 作用 |
|---|---|
| `probe-live.mjs` | 铸 cookie → HTTP unary → WS 握手 → 开 `$events` / `workspace/follow` / `session/follow`，打印所有帧 |
| `probe-rpc.mjs` | 枚举 `session/list`、`session/page`、`session/projections`、`workspaceFiles/list`、`settings/describe`、`session/modelCatalog`，并观察错误路径 |
| `probe-history.mjs` | `session/follow` snapshot → 用 `cursor` 做 `throughSeq` 翻页；观测记录类型序列 |
| `probe-control.mjs` | `session/control` 空 args 的 baseline 与 `projection` 增量帧 |
| `probe-page-seqs.mjs` | 校验 `session/page` 的 `throughSeq` 边界语义（`max(seq)==throughSeq`） |

运行：`node imdsh\docs\protocol-notes\tools\probe-history.mjs`（读 `$DSH_HOME/.credentials.yaml`、`$DSH_WEB_URL`）。
原始输出已存档：`probe-history.out.txt`、`probe-control.out.txt`。

---

## 11. 附录

### 11.1 端点全表（135 个）

见 `imdsh/docs/protocol-notes/endpoints.index.txt`（每行：`endpoint | unary/stream | invocation | 参数(名字→wire:类型) | 返回类型`）。
逐端点的完整 JSON Schema 见 `endpoints.raw.json`；渲染版见 `endpoints.contracts.md`、`endpoints.compact.txt`、`files.compact.txt`、`settings.compact.txt`、`misc.compact.txt`。

> ⚠️ **135 个端点里有 29 个的 `result` 没有 JSON-Schema 投影**（`__schemaUnavailable`），因为 Zod 里有 `Uint8Array`、`never`、只读 `z.any()` 字典等无法投影的类型。这些端点的 `.raw.json` 条目里 `result.schema` 只是个占位对象，**真实形状必须读 `dsh-api-remotes/lib/client.js` 里对应的 `zod.z.*` 定义**。完整清单见 §10 第 12 项。

按 package 分布：

| package | 端点数 | 领域 |
|---|---|---|
| `@deepseek-ai/dsh-api-session-controller` | 21 | 会话（核心） |
| `@deepseek-ai/dsh-api-workspace-controller` | 14 | 工作区 |
| `@deepseek-ai/dsh-cordis-host-runner` | 12 | 动态插件运行 |
| `@deepseek-ai/dsh-plugin-manager` | 12 | 插件安装/启停 |
| `@deepseek-ai/dsh-api-account-controller` | 11 | DeepSeek 账号 |
| `@deepseek-ai/dsh-api-settings-controller` | 8 | 设置 |
| `@deepseek-ai/dsh-api-terminal-controller` | 8 | 终端 |
| `@deepseek-ai/dsh-goal` | 7 | 目标（goal 模式） |
| `@deepseek-ai/dsh-schedule` | 5 | 定时任务 |
| `@deepseek-ai/dsh-api-workspace-files` | 5 | 工作区文件 |
| `@deepseek-ai/dsh-llm` | 3 | 模型发现 |
| `@deepseek-ai/dsh-api-job-controller` | 3 | 后台任务 |
| `@deepseek-ai/dsh-message-feedback` | 3 | 消息反馈 |
| `@deepseek-ai/dsh-plugin-market` | 3 | 插件市场 |
| `@deepseek-ai/dsh-client-product-analytics` | 3 | 埋点 |
| `@deepseek-ai/dsh-agent-preset-registry` | 3 | Agent 预设 |
| `@deepseek-ai/dsh-user-questions` | 2 | AskUserQuestion 作答 |
| `@deepseek-ai/dsh-commands` | 2 | 斜杠命令 |
| `@deepseek-ai/dsh-office-to-pdf` | 2 | Office → PDF |
| `@deepseek-ai/dsh-subagent` | 2 | 子代理提示/中断 |
| `@deepseek-ai/dsh-client-ui-plugin-manager` | 1 | UI 插件 |
| `@deepseek-ai/dsh-host-plugin-inventory` | 1 | 插件清单 |
| `@deepseek-ai/dsh-permission-presets` | 1 | 权限预设 |
| `@deepseek-ai/dsh-command-feedback` | 1 | 命令反馈 |
| `@deepseek-ai/dsh-client-file-upload` | 1 | 文件上传 |
| `@deepseek-ai/dsh-session-reference` | 1 | 会话引用 |
| **合计** | **135** | **26 个 package** |

（数字由 `endpoints.raw.json` 统计得出，与 `tools/extract-endpoints.mjs` 的 `package.methodCount` 一致。）

### 11.2 `$events` 转发事件白名单（28 条，完整）

📖 `dsh-api-remotes/lib/types/remote-events.js:16-45`（`API_REMOTE_FORWARDED_EVENTS`）。
`mode:'waterfall'` 的条目会收到 `waterfall` 帧且**必须作答**；`mode:'emit'` 只是通知。
`resources` 表示该事件携带哪些资源 id，用于非 owner Peer 的访问控制（owner 全通）。

| event | mode | 携带的资源 | IMDSH 是否需要 |
|---|---|---|---|
| `agent-preset/selected` | emit | — | 低 |
| **`approval/request`** | **waterfall** | — | **必需**（工具审批） |
| `api-session/activity` | emit | `session` | 中（会话活跃度） |
| `api-session/added` | emit | `session` | 中（新会话出现） |
| `api-session/error` | emit | `session` | 高（会话出错提示） |
| `api-session/removed` | emit | `session` | 高（会话被删） |
| `api-session/status` | emit | `session` | 高（running/idle 状态） |
| `commands/change` | emit | — | 中（斜杠命令表变化） |
| `deepseek-account/session-expired` | emit | — | 高 |
| `deepseek-account/model-sign-in-required` | emit | — | 中 |
| `credentials/record-updated` | emit | — | 中 |
| `credentials/reference-updated` | emit | — | 低 |
| `goal/activation-changed` | emit | — | 低 |
| `cordis/request-run` | emit | — | 低（动态插件） |
| `cordis/request-run-resolved` | emit | — | 低 |
| `cordis/dynamic-package` | emit | — | 低 |
| `cordis/dynamic-retract` | emit | — | 低 |
| `cordis/inspect-query` | emit | — | 低 |
| `cordis/inspect-query-resolved` | emit | — | 低 |
| `llm/adapters-updated` | emit | — | 中（模型/供应商变化） |
| `permission-presets/catalog-changed` | emit | — | 中 |
| `plugin-manager/changed` | emit | — | 中 |
| `plugin-manager/install-log` | emit | — | 低 |
| `plugin-manager/install-state` | emit | — | 低 |
| `plugin-market/changed` | emit | — | 低 |
| `settings/document-updated` | emit | — | 高（设置有外部改动） |
| `schedule/changed` | emit | — | 中 |
| **`user-questions/request`** | **waterfall** | — | **必需**（AskUserQuestion） |

> 只有 `approval/request` 与 `user-questions/request` 是 waterfall；其余都是 emit。
> 两条 waterfall 的 `request` 形状不同：`approval/request` 的 `request` 描述一次待批的工具调用（工具名、参数、审批策略），`user-questions/request` 的 `request.questions[]` 是 `{id, question, header?, options?:[{label, description}]}`。⚠️ `approval/request` 的精确字段本次未抓包（本机 30s 内没有审批发生），见 §10 第 8 项。

### 11.3 术语对照

| 协议里的词 | IMDSH 里的概念 |
|---|---|
| channel `/api` | 网关的 RPC 前缀（本机只有这一个 + 插件的 `/webim`） |
| endpoint `ns/method` | 一条 RPC 方法 |
| `rpcId` | 请求关联 id（UUIDv4，回包必须一致） |
| `streamId` | 一条 WS 逻辑流的 id（本 socket 内唯一） |
| `seq` | 会话日志的单调序号（游标） |
| `cursor` | snapshot 已投递到的最大 `seq`，即下一段 `throughSeq` |
| `projections` | 会话的派生状态（标题、用量、待办、权限…），不是消息 |
| `surface` | "当前表面对话"——用户真正看到的 5 类消息事件 |
| `Peer` | 一个已鉴权的调用者（cookie 决定它的能力） |
| `interactions` | Peer 能否作答 Host 的 waterfall（决定 `$events` 可用性） |

### 11.4 关键常量速查

| 常量 | 值 | 出处 |
|---|---|---|
| API 前缀 | `/api` | `dsh-client-connection/lib/index.js:14` |
| API 连接路由 | `/connect` | `:19` |
| WS mux 路径 | `/api/remote.mux` | `dsh-api-gateway/lib/types/stream-protocol.js:4` |
| Cookie 前缀 | `dsh-auth-` | `dsh-client-connection/lib/index.js:277` |
| Cookie 版本（浏览器 / API） | `1` / `2` | `:278`、`:526` |
| Cookie 默认寿命 | 30 天（`cookieMaxAgeDays`） | `:1017`、`:1030` |
| 请求体上限 | 300 MiB | `:30` |
| WS Ping 间隔 | 2000 ms | `dsh-api-gateway/lib/index.js:17` |
| 心跳容忍 | 2 次 | `dsh-api-gateway/lib/types/stream-server.js:6` |
| 单流上行缓冲 | 262 144 B | `dsh-api-gateway/lib/index.js:18` |
| 重连退避 | 500 ms → ×2 → 上限 10 000 ms | `dsh-client-connection/lib/index.js:984-986` |
| 会话持久化 header.version | `4` | ✅ 实测 |
