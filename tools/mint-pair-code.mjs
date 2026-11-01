#!/usr/bin/env node
// 在主机上生成一张 IMDSH 配对码，并把码打印出来。
//
// 为什么需要这个脚本：配对码本来可以在 DSH 设置页「设备配对」卡片里点出来，
// 但「装 App 时人就在电脑前」这个场景下，命令行更快，也方便脚本化。
//
// 用法：
//   node imdsh/tools/mint-pair-code.mjs            # 默认有效期（插件配置 pairDays，通常 30 天）
//   node imdsh/tools/mint-pair-code.mjs 0          # 永久有效
//   node imdsh/tools/mint-pair-code.mjs 7          # 7 天
//   WEBIM_URL=http://192.168.1.20:3081 node imdsh/tools/mint-pair-code.mjs
//
// 认证方式：读 $DSH_HOME/webim/token.json 里的长效进入令牌，用 `GET /?token=` 换一个
// dsh_webim 会话 Cookie（这就是设置页里那条链接做的事），再带着 Cookie 调配对端点。
// 网关默认把会话绑定到 User-Agent，所以整个脚本固定一个 UA。
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const BASE = process.env.WEBIM_URL ?? 'http://127.0.0.1:3081'
const DSH_HOME = process.env.DSH_HOME ?? join(homedir(), '.dsh')
const USER_AGENT = 'IMDSH-Pairing-CLI/1.0'

const arg = process.argv[2]
const days = arg === undefined ? undefined : Number(arg)
if (days !== undefined && (!Number.isInteger(days) || days < 0 || days > 3650)) {
  console.error('有效期必须是 0..3650 的整数（0 = 永久）')
  process.exit(2)
}

function entryToken() {
  const file = join(DSH_HOME, 'webim', 'token.json')
  let raw
  try {
    raw = JSON.parse(readFileSync(file, 'utf8'))
  } catch {
    console.error(`读不到 ${file}：DSH 至少启动过一次、且 dsh-webim 插件启用过吗？`)
    process.exit(2)
  }
  if (typeof raw?.token !== 'string' || raw.token === '') {
    console.error(`${file} 里没有 token`)
    process.exit(2)
  }
  return raw.token
}

/** 用长效令牌换会话 Cookie（和设置页里那条链接同一条路径）。 */
async function sessionCookie() {
  const response = await fetch(`${BASE}/?token=${encodeURIComponent(entryToken())}`, {
    redirect: 'manual',
    headers: { 'user-agent': USER_AGENT },
  })
  const setCookie = response.headers.getSetCookie?.() ?? []
  for (const item of setCookie) {
    const pair = item.split(';')[0]
    if (pair.startsWith('dsh_webim=')) return pair
  }
  console.error(`换会话失败（HTTP ${response.status}）：进入令牌可能已被轮换。`)
  console.error('到 DSH「设置 → 远程接入」重新复制一次进入链接，或直接在设置页「设备配对」里点生成。')
  process.exit(3)
}

let response
try {
  const cookie = await sessionCookie()
  response = await fetch(`${BASE}/__webim/pair/code`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', cookie, 'user-agent': USER_AGENT },
    body: JSON.stringify(days === undefined ? {} : { days }),
  })
} catch (error) {
  console.error(`连不上 ${BASE}：${error.message}`)
  console.error('确认 dsh-webim 网关在跑（DSH 设置 → 远程接入），必要时用 WEBIM_URL 指定地址。')
  process.exit(1)
}

const contentType = response.headers.get('content-type') ?? ''
const text = await response.text()

if (contentType.includes('text/html')) {
  console.error(`网关返回了登录页（HTTP ${response.status}）：这一版插件还没有配对能力。`)
  console.error('把仓库里的 lib/pairing.js、lib/gateway.js、lib/index.js、lib/config.js、client.js')
  console.error('复制到 ~/.dsh/profiles/desktop/plugins/dsh-webim/ 后重启 DSH（或用 pluginManager/setPluginEnabled 重载）。')
  process.exit(3)
}

let json
try {
  json = JSON.parse(text)
} catch {
  console.error(`响应不是 JSON（HTTP ${response.status}）：${text.slice(0, 200)}`)
  process.exit(1)
}

if (!json.ok) {
  console.error(`生成失败：${json.code ?? response.status} ${json.error ?? ''}`)
  process.exit(1)
}

const code = json.pairingCode?.code ?? json.code
const expiresAt = json.pairingCode?.expiresAt ?? 0
const permanent = json.pairingCode?.permanent ?? expiresAt === 0

console.log('')
console.log(`  配对码   ${code}`)
console.log(`  有效期   ${permanent ? '永久' : new Date(expiresAt).toLocaleString('zh-CN')}`)
console.log(`  主机     ${BASE}`)
console.log('')
console.log('  一码一机：这个码只能被一台设备兑换。手机打开 IMDSH，填上面的主机地址和配对码。')
console.log('')
