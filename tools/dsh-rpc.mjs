#!/usr/bin/env node
// 用 owner 凭据直接调本机 DSH 的 unary RPC（不需要浏览器、不需要 token 链接）。
//
// 用法：
//   node imdsh/tools/dsh-rpc.mjs pluginManager/listPlugins
//   node imdsh/tools/dsh-rpc.mjs pluginManager/setPluginEnabled '{"id":"...","enabled":false}'
//   DSH_URL=http://127.0.0.1:59751 node imdsh/tools/dsh-rpc.mjs session/list '{"_request":{}}'
//
// 原理同 mint-pair-code.mjs：$DSH_HOME/.credentials.yaml 里的 browser-session secret
// 签一个 dsh-auth-<sha256(authority)> Cookie，网关/DSH 只认这个。
import { createHash, createHmac } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const BASE = process.env.DSH_URL ?? 'http://127.0.0.1:59751'
const HOSTPORT = new URL(BASE).host
const DSH_HOME = process.env.DSH_HOME ?? join(homedir(), '.dsh')

const [method, rawArgs] = process.argv.slice(2)
if (!method) {
  console.error('用法: node dsh-rpc.mjs <endpoint> [json-args]')
  process.exit(2)
}

const b64url = (buf) =>
  Buffer.from(buf).toString('base64').replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '')

const text = readFileSync(join(DSH_HOME, '.credentials.yaml'), 'utf8')
const match = /^ {2}client-connection\/browser-session:\s*\n(?:.*\n)*?\s+secret:\s*["']?([A-Za-z0-9_-]+)["']?/mu.exec(text)
if (!match) {
  console.error('凭据文件里没有 client-connection/browser-session 的 secret')
  process.exit(2)
}
const secret = Buffer.from(match[1].replaceAll('-', '+').replaceAll('_', '/'), 'base64')

const name = `dsh-auth-${b64url(createHash('sha256').update(HOSTPORT).digest())}`
const now = Date.now()
const payload = b64url(JSON.stringify({ version: 1, authority: HOSTPORT, issuedAt: now, expiresAt: now + 3_600_000 }))
const mac = b64url(createHmac('sha256', secret).update(payload).digest())

let args = {}
if (rawArgs) {
  try {
    args = JSON.parse(rawArgs)
  } catch (error) {
    console.error(`args 不是合法 JSON：${error.message}`)
    process.exit(2)
  }
}

const rpcId = `cli-${Math.random().toString(16).slice(2)}`
const response = await fetch(`${BASE}/api/${method}`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', cookie: `${name}=v1.${payload}.${mac}` },
  body: JSON.stringify({ type: 'client-request', rpcId, method, payload: { args } }),
})

const contentType = response.headers.get('content-type') ?? ''
const body = await response.text()
if (contentType.includes('text/html')) {
  console.error(`HTTP ${response.status}：返回了登录页，说明凭据没被接受（DSH 重启后 secret 会变，重跑即可）`)
  process.exit(1)
}
let json
try {
  json = JSON.parse(body)
} catch {
  console.error(`HTTP ${response.status}，非 JSON：${body.slice(0, 300)}`)
  process.exit(1)
}
const result = json.result
if (!result?.ok) {
  console.error(`调用失败：${JSON.stringify(result?.error ?? json).slice(0, 400)}`)
  process.exit(1)
}
console.log(JSON.stringify(result.value, null, 2))
