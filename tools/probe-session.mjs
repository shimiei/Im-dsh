// 用真实数据探一遍客户端会收到的帧，定位解析层与 args 层的问题。
//
// 用法:
//   node imdsh/tools/probe-session.mjs follow <sessionId> [argsJson]
//   node imdsh/tools/probe-session.mjs raw    <endpoint>  [argsJson]
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const BASE = 'http://127.0.0.1:3081'
const UA = 'IMDSH-Pairing-CLI/1.0'
const [mode, a, b] = process.argv.slice(2)
if (!mode) {
  console.error('用法: node probe-session.mjs follow <sessionId> [argsJson] | raw <endpoint> [argsJson]')
  process.exit(2)
}
const endpoint = mode === 'follow' ? 'session/follow' : mode === 'raw' ? a : `session/${mode}`
const args = mode === 'follow' ? JSON.parse(b ?? JSON.stringify({ request: { sessionId: a } })) : JSON.parse(b ?? '{}')

const token = JSON.parse(readFileSync(join(homedir(), '.dsh/webim/token.json'), 'utf8')).token
const r1 = await fetch(`${BASE}/?token=${encodeURIComponent(token)}`, { redirect: 'manual', headers: { 'user-agent': UA } })
const cookie = (r1.headers.getSetCookie() || []).map((c) => c.split(';')[0]).find((c) => c.startsWith('dsh_webim='))

const ws = new WebSocket('ws://127.0.0.1:3081/api/remote.mux', { headers: { cookie, 'user-agent': UA } })

const seen = new Map()
let frameCount = 0

ws.addEventListener('open', () => {
  console.log('ws open →', endpoint, JSON.stringify(args))
  ws.send(JSON.stringify({ type: 'open', streamId: 'p1', endpoint, payload: { args } }))
})

ws.addEventListener('message', (event) => {
  frameCount += 1
  let frame
  try {
    frame = JSON.parse(event.data)
  } catch {
    console.log('non-json frame', String(event.data).slice(0, 200))
    return
  }
  const key = frame.type ?? '?'
  seen.set(key, (seen.get(key) ?? 0) + 1)
  if (frameCount <= 5) {
    console.log(`--- frame#${frameCount} type=${key} ---`)
    console.log(JSON.stringify(frame).slice(0, 2400))
  }
})

ws.addEventListener('error', (e) => console.log('ws error', e.message ?? ''))

await new Promise((r) => setTimeout(r, 4000))
ws.close()
console.log('--- summary ---')
for (const [k, v] of seen) console.log(`  ${k}: ${v}`)
console.log(`frames total: ${frameCount}`)
