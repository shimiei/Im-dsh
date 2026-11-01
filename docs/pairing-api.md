# 设备配对 API（iOS 客户端契约）

> 面向 IMDSH（原生 iOS 客户端）开发者。
> 适用范围：dsh-webim 1.6.2 及以后的版本 · 契约稳定性：**字段名与错误码视为硬契约，只会新增，不会改名或删除**。

本文件描述 dsh-webim 网关的「设备配对码」能力：用户在 DSH 设置页生成一串 `XXXX-XXXX-XXXX` 的短码，
App 输入一次即换到一份**长效 device token**，之后所有 HTTP 与 WebSocket 请求都用这份 token 认证，
不需要用户在手机上输口令，也不需要扫浏览器二维码。

---

## 1. 角色与凭据

| 名词 | 说明 |
| --- | --- |
| **配对码（pairing code）** | 12 位、形如 `K7RM-2QXP-9HDA`。由用户在设置页生成，**一码只能兑换给一台设备**。默认 30 天有效（可配成 0 = 永久）。字符集为 `23456789ACDEFHJKMNPQRTVWXY`，刻意去掉了 `0/O`、`1/I/L`、`U`、`B/G/S/Z`（易与 `8/6/5/2` 混淆）。 |
| **deviceId** | App 自己生成并**持久保存**的设备标识，`[A-Za-z0-9._:@-]{1,128}`，建议 16–32 位随机串或 `IDFV`+随机后缀。它不是秘密，但必须稳定：重装/恢复后能拿回同一个值，才能拿回同一个 token。 |
| **device token** | 兑换成功后由服务端下发的凭据：**32 字节随机数的 base64url，43 个字符**（`[A-Za-z0-9_-]{43}`）。长效，不过期，只有被吊销才失效。 |

配对码负责「把新设备领进门」，device token 负责之后的一切请求。

所有时间字段都是 **epoch 毫秒**（JSON number）。Swift 里换 `Date` 需要 `/1000`：

```swift
let created = Date(timeIntervalSince1970: Double(device.createdAt) / 1000)
```

---

## 2. 端点总览

网关地址 `<GW>` 就是用户在设置页看到的入口，例如 `http://192.168.1.20:3081` 或 `https://xxx.trycloudflare.com`。
所有端点都在 `/__webim/pair/` 命名空间下。

| 方法 | 路径 | 需要凭据 | 用途 |
| --- | --- | --- | --- |
| `POST` | `/__webim/pair/redeem` | **不需要**（限流） | App 用配对码换 device token，**这是 iOS 唯一必接的端点** |
| `POST` | `/__webim/pair/code` | 需要（会话或 device token） | 生成配对码（设置页用） |
| `GET` | `/__webim/pair/devices` | 需要 | 列出已配对设备与配对码（设置页用） |
| `POST` | `/__webim/pair/revoke` | 需要 | 吊销一台设备或一张未兑换的码（设置页用） |

「需要凭据」= 下面两种任一即可：

- `Cookie: webim_device=<deviceToken>`（推荐）
- `Cookie: dsh_webim=<浏览器会话>`（浏览器里登录后自动带）
- 查询参数 `?device=<deviceToken>` 也接受，仅建议用于 WebSocket 握手（见 §5）

每个响应都带 `cache-control: no-store`、`x-content-type-options: nosniff`、`x-dsh-webim: dsh-webim`。

---

## 3. `POST /__webim/pair/redeem` — 兑换配对码（唯一匿名端点）

**请求**

```http
POST /__webim/pair/redeem HTTP/1.1
Host: <GW>
Content-Type: application/json
Accept: application/json

{
  "code": "K7RM-2QXP-9HDA",
  "deviceId": "IMDSH-7C1E4F02A9B3",
  "name": "iPhone 15 Pro",
  "platform": "ios"
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `code` | string | ✅ | 用户输入的配对码。**大小写不敏感**，可带或不带连字符/空格：`k7rm 2qxp 9hda` 与 `K7RM-2QXP-9HDA` 等价。 |
| `deviceId` | string | ✅ | `[A-Za-z0-9._:@-]{1,128}`（`NSUUID.UUIDString` 正好合法）。不符合此形状按 `400 bad-request` 拒绝。 |
| `name` | string | ❌ | 显示名，最长 64 字符，控制字符会被剔除。默认空串。 |
| `deviceName` | string | ❌ | `name` 的同义字段（IMDSH 现在发的是这个名字）。两个都给时 `name` 优先。 |
| `platform` | string | ❌ | 平台标识，最长 32 字符。约定用 `ios`。 |

请求体上限 8 KiB；`Content-Type` 不做强制校验，但请求体必须是一个 JSON 对象。

**成功响应 `200`**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Cache-Control: no-store
Set-Cookie: webim_device=<deviceToken>; Path=/; HttpOnly; SameSite=Lax; Max-Age=31536000; Expires=...
```

```json
{
  "ok": true,
  "deviceId": "IMDSH-7C1E4F02A9B3",
  "deviceToken": "3Jk9xQ0aZ1m7Vb4Lp2Rs8Tu6Wy5Nc0Fd3Gh1Ij4Kl7M",
  "reused": false,
  "device": {
    "deviceId": "IMDSH-7C1E4F02A9B3",
    "deviceIdPrefix": "IMDSH-7C",
    "name": "iPhone 15 Pro",
    "platform": "ios",
    "createdAt": 1761951600000,
    "lastSeenAt": 1761951600000,
    "revoked": false,
    "revokedAt": 0
  }
}
```

- `deviceToken` 只在这里出现一次，之后任何端点都不会再返回它。**必须立刻存进 Keychain**。
- `reused: true` 表示这台设备之前就配对过（重装、从备份恢复），这次返回的是**同一个** token；
  `reused: false` 表示刚刚完成一次新的绑定。
- `Set-Cookie` 是给「同一台机器上的浏览器」顺带用的，原生 App 请自己管理 `Cookie` 请求头，
  不要依赖 `URLSession` 的 cookie 存储（它会在 App 重启后清掉）。

**失败响应**

统一形状：

```json
{ "ok": false, "code": "code-already-bound", "error": "this pairing code is already bound to another device" }
```

`code` 是稳定的机器可读值，`error` 是英文短句，**只用于日志/调试，不要拿它做判断**。

> 注意形状：`error` 是**字符串**，`code` 与它平级；不是 `{"error": {"code": …, "message": …}}`。
> 读 `dict["error"]["code"]` 会拿到 nil —— 请读 `dict["code"]`。（IMDSH 的 `IMAPIClient` 已兼容两种形状。）

| HTTP | `code` | 含义与处理 |
| --- | --- | --- |
| `400` | `bad-request` | `deviceId` 缺失或形状非法；或请求体不是 JSON 对象。属于 App bug，直接报错。 |
| `401` | `code-invalid` | 配对码不存在、已被吊销、或格式不合法。提示用户重新输入/重新生成。 |
| `410` | `code-expired` | 配对码过期。提示重新生成（设置页里能看到剩余有效期）。 |
| `409` | `code-already-bound` | 这张码已经绑定到**另一台设备**。提示用户「这张码已被别的设备使用，请重新生成」。**不要**换 deviceId 重试。 |
| `403` | `device-revoked` | 这个 `deviceId` 已被用户吊销，而且这张码就是它当初配对用的那张。请让用户在设置页**生成一张新码**再配对（新码可以重新配对同一台设备，但会下发一个全新的 token，旧 token 依旧无效）。 |
| `429` | `rate-limited` | 失败次数过多，整个 IP 被临时封禁。带 `retryAfterSeconds` 与 `Retry-After` 头。 |
| `405` | `method-not-allowed` | 用了非 `POST`。 |
| `413` | `bad-request` | 请求体过大。 |

**限流规则**（复用网关口令门的失败计数）：

- 只有「可能是穷举」的失败才计数：`code-invalid`、`code-expired`。
- `code-already-bound`、`device-revoked`、`bad-request` **不计数**，所以 App 逻辑错误不会把用户自己的 IP 锁死。
- 计入的失败累计到阈值（默认同一 IP 10 分钟内 8 次）后封禁 15 分钟，期间连正确的码也不能兑换。
  这些都是插件配置项（`maxFailures` / `failureWindowMinutes` / `blockMinutes`），不要把它们写死在客户端。
- 因此：**失败一次就停下来问用户，不要自动重试或轮询**。

---

## 4. 管理端点（设置页使用，App 一般不需要）

### `POST /__webim/pair/code` — 生成配对码

```http
POST /__webim/pair/code
Cookie: webim_device=<deviceToken>   （或浏览器会话）
Content-Type: application/json

{ "days": 30 }
```

`days` 可省略（用配置的默认值，默认 30）：`0` = 永久有效，`1..3650` = 天数。越界 → `400 bad-request`。

```json
{
  "ok": true,
  "pairDays": 30,
  "pairingCode": {
    "code": "K7RM-2QXP-9HDA",
    "createdAt": 1761951600000,
    "expiresAt": 1764543600000,
    "expiresInDays": 30,
    "permanent": false,
    "expired": false,
    "redeemed": false,
    "deviceIdPrefix": "",
    "revoked": false,
    "revokedAt": 0
  }
}
```

### `GET /__webim/pair/devices` — 设备与码清单

```json
{
  "ok": true,
  "pairDays": 30,
  "devices": [ { "deviceId": "...", "deviceIdPrefix": "...", "name": "...", "platform": "...",
                 "createdAt": 0, "lastSeenAt": 0, "revoked": false, "revokedAt": 0 } ],
  "pairingCodes": [ { "code": "K7RM-2QXP-9HDA", "createdAt": 0, "expiresAt": 0, "expiresInDays": 0,
                      "permanent": false, "expired": false, "redeemed": false,
                      "deviceIdPrefix": "", "revoked": false, "revokedAt": 0 } ]
}
```

- `expiresAt: 0` 且 `permanent: true` 表示永久有效；`expiresInDays` 只在会过期的码上有意义（永久码为 `0`）。
- `redeemed: true` 表示这张码已经兑换过，`deviceIdPrefix` 是占用它的设备前缀。
- 列表按创建时间倒序（最新在前）。**任何响应都不会包含 device token。**

### `POST /__webim/pair/revoke` — 吊销

```json
{ "deviceId": "IMDSH-7C1E4F02A9B3" }
```

或

```json
{ "code": "K7RM-2QXP-9HDA" }
```

只能二选一（同时给或都不给 → `400 bad-request`）。

```json
{ "ok": true, "device": { "deviceId": "...", "revoked": true, "revokedAt": 1761955200000, "...": "..." }, "pairingCode": null }
```

- 吊销设备：该 device token **下一个请求立刻 401**，用于该设备的 Cookie/查询参数全部作废；服务端同时把 token 从磁盘文件里抹掉。
- 吊销配对码：只影响「还没兑换」的码，用这张码配对成功的设备继续有效（要停掉那台设备请按 `deviceId` 吊销）。
- 吊销一台设备后，这台设备**不能**靠「重新兑换当初那张码」复活（会得到 `403 device-revoked`）：
  旧码是它当初的绑定凭据，能复活就等于没吊销。要重新配对它，请在设置页生成一张**新码**——
  新码会把它当成一次全新配对，下发**全新** token（旧 token 永不恢复）。
- 错误：`404 unknown-device` / `404 unknown-code`。

### 管理端点的认证失败

未带任何有效凭据时，这 4 个端点里除 `redeem` 外都返回：

```json
{ "ok": false, "error": "login required" }
```

状态码 `401`，**注意这种响应没有 `code` 字段**（与网关其它 API 一致），请用 HTTP 状态码判断。

针对浏览器表单的 CSRF 防护：带 `Origin`/`Referer` 且与 `Host` 不同源的 `POST` 会被 `403 cross-origin` 拒绝。
原生 App 不发这两个头，不受影响。

---

## 5. 拿 device token 之后怎么用

### 5.1 HTTP

把 token 放进 `Cookie` 头（首选）或 `?device=` 查询参数：

```http
GET /api/sessions HTTP/1.1
Host: <GW>
Cookie: webim_device=<deviceToken>
```

通过网关鉴权门之后，请求会照常反向代理到本机 DSH，网关自己负责给上游补 `dsh-auth-*` Cookie，
**你的 token 不会转发给上游**，App 也不需要理解 DSH 的登录态。

等价写法：`GET /api/sessions?device=<deviceToken>`。网关会先把这个参数从 URL 上摘掉，
再转发给本机 Harness —— **token 不会出现在上游的请求日志里**。

不要用 `?device=` 代替 Cookie：URL 会进浏览器历史、代理日志和 Referer。它是为「无法设置请求头」的
握手场景准备的。

### 5.2 WebSocket

浏览器的 WebSocket 不能自定义请求头，所以查询参数是为握手准备的；原生 `URLSessionWebSocketTask`
可以直接设 Cookie 头，两种都行：

```text
wss://<GW>/api/remote.mux?device=<deviceToken>
```

```http
GET /api/remote.mux HTTP/1.1
Host: <GW>
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Version: 13
Sec-WebSocket-Key: <随机>
Cookie: webim_device=<deviceToken>
```

握手被拒时服务器直接回 `HTTP/1.1 401 Unauthorized` 并关闭连接（没有响应体）。
`URLSessionWebSocketTask` 会以「HTTP 升级失败」的形式暴露这个 401。

### 5.3 什么会失效、什么不会

| 事件 | device token |
| --- | --- |
| 网关/插件重启、DSH 重启 | **继续有效**（持久化在 `$DSH_HOME/webim/pairing.json`） |
| 设置页「刷新令牌」（轮换浏览器入口 token） | **继续有效**（两者互相独立） |
| 换 Wi-Fi / 换 IP / 换 UA | **继续有效**（device token 不绑 UA，也不绑 IP；浏览器会话才绑 UA） |
| 在设置页吊销这台设备 | 立刻失效 |
| `pairing.json` 被删除或损坏 | 全部失效（文件损坏时网关降级为空表并记日志，需要重新配对） |

token 本身没有有效期，续期没有意义；「有效期」只存在于配对码上。

---

## 6. 客户端实现检查单

1. 首次启动生成 `deviceId` 并存进 Keychain（`kSecAttrAccessibleAfterFirstUnlock`），随备份恢复；
   每次启动都读它，**不要每次重装都换一个新的**——换了就等于换了一台设备，`code-already-bound` 会一直挡着你。
2. 用户输入配对码 → `POST /__webim/pair/redeem` → 成功立刻把 `deviceToken` 存进 Keychain。
3. 之后所有请求带 `Cookie: webim_device=<token>`；WebSocket 用 `?device=` 或 Cookie。
4. 任何请求收到 `401`：清掉本地 token 并回到「输入配对码」界面（除了 `redeem` 自己的 401，那只是码不对）。
5. 遇到 `409/403/410/429` 不要自动重试：把 `code` 映射成一句人话提示用户（§3 的表）。
6. 输入框可以宽松：允许用户粘贴 `k7rm 2qxp 9hda`，也可以自己格式化成 `XXXX-XXXX-XXXX` 显示。
7. 别把 token 写进日志、URL 分享、崩溃报告；`?device=` 只用于握手，能用 Cookie 的时候不要用查询参数。
8. 网关是明文 HTTP 时（局域网直连），token 会以明文过网络：生产场景建议走 Cloudflare 隧道等 https 入口，
   此时 `Set-Cookie` 会带 `Secure`。

### Swift 片段（无第三方依赖）

```swift
struct RedeemRequest: Encodable { let code: String; let deviceId: String; let name: String; let platform: String }
struct RedeemResponse: Decodable {
    let ok: Bool
    let deviceId: String?
    let deviceToken: String?
    let reused: Bool?
    struct Failure: Decodable { let code: String?; let error: String? }
}

func redeem(base: URL, code: String, deviceId: String) async throws -> String {
    var request = URLRequest(url: base.appending(path: "/__webim/pair/redeem"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
        RedeemRequest(code: code, deviceId: deviceId, name: UIDevice.current.name, platform: "ios"))

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as! HTTPURLResponse).statusCode
    guard status == 200 else {
        let failure = try? JSONDecoder().decode(RedeemResponse.Failure.self, from: data)
        throw PairingError(status: status, code: failure?.code ?? "unknown")
    }
    guard let token = (try JSONDecoder().decode(RedeemResponse.self, from: data)).deviceToken else {
        throw PairingError(status: status, code: "missing-token")
    }
    return token
}
```

---

## 7. 服务端存储与运维（给排障的人看）

- 状态文件：`$DSH_HOME/webim/pairing.json`，权限 0600（Windows 上 mode 只是建议值），
  写入方式是「先写 `pairing.json.tmp` 再 rename」的原子替换，与 `token.json` 一致。
- 文件形状：

```json
{
  "version": 1,
  "codes":   [ { "code": "K7RM-2QXP-9HDA", "createdAt": 0, "expiresAt": 0, "deviceId": "", "redeemedAt": 0, "revokedAt": 0 } ],
  "devices": [ { "deviceId": "IMDSH-7C1E4F02A9B3", "name": "iPhone 15 Pro", "platform": "ios",
                 "token": "<43 chars>", "createdAt": 0, "lastSeenAt": 0, "revokedAt": 0 } ]
}
```

- 文件损坏/版本不符：**降级为空表**并在 `$DSH_HOME/webim/plugin.log` 里写一行
  `pairing.json unreadable, starting with an empty pairing table: …`，网关照常启动，所有设备重新配对即可。
- 想一键踢掉所有设备：设置页逐个吊销，或停掉插件后删掉 `pairing.json`。
- 配对码默认有效期由插件配置 `pairDays` 决定（默认 30，`0` = 永久），设置页生成时也可以用 `days` 覆盖。
