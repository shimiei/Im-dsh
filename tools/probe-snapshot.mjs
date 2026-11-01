// 把 session/follow 的首帧 snapshot 完整 dump 出来（含 records 全文），
// 用来核对客户端解析假设与真实事件结构是否一致。
import { readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const BASE = 'http://127.0.0.1:3081'
const UA = 'IMDSH-Pairing-CLI/1.0'
const sessionId = process.argv[2] ?? 'session-2daf9cab-fdaa-420d-99d8-67ddf8b1616e'

const token = JSON.parse(readFileSync(join(homedir(), '.dsh/webim/token.json'), 'utf8')).token
const r1 = await fetch(`${BASE}/?token=${encodeURIComponent(token)}`, { redirect: 'manual', headers: { 'user-agent': UA } })
const cookie = (r1.headers.getSetCookie() || []).map((c) => c.split(';')[0]).find((c) => c.startsWith('dsh_webim='))

const ws = new WebSocket('ws://127.0.0.1:3081/api/remote.mux', { headers: { cookie, 'user-agent': UA } })

ws.addEventListener('open', () => {
  ws.send(JSON.stringify({
    type: 'open',
    streamId: 'p-dump',
    endpoint: 'session/follow',
    payload: { args: { request: { address: { kind: 'session', sessionId }, maxMessages: 6, assistantStream: true } } },
  }))
})

let done = false
ws.addEventListener('message', (event) => {
  if (done) return
  const frame = JSON.parse(event.data)
  if (frame.type === 'error') {
    console.log('error:', JSON.stringify(frame.error))
    done = true
    ws.close()
    return
  }
  if (frame.type === 'item' && frame.value?.type === 'snapshot') {
    done = true
    const snap = frame.value
    writeFileSync('imdsh/docs/protocol-notes/probe-snapshot-dump.json', JSON.stringify(snap, null, 2))
    console.log('records:', snap.records.length, 'cursor:', snap.cursor, 'hasMore:', snap.hasMore)
    console.log('--- record[0] ---')
    console.log(JSON.stringify(snap.records[0], null, 2).slice(0, 1500))
    console.log('--- record[1] ---')
    console.log(JSON.stringify(snap.records[1], null, 2).slice(0, 1500))
    const types = {}
    for (const r of snap.records) {
      const t = r?.event?.type ?? r?.type ?? '?'
      types[t] = (types[t] ?? 0) + 1
    }
    console.log('--- event types ---', JSON.stringify(types))
    console.log('--- projection keys ---', Object.keys(snap.projections?.values ?? {}).join(','))
    console.log('--- subagent projection ---', JSON.stringify(snap.projections?.values?.subagent).slice(0, 500))
    console.log('--- sessionListMetadata ---', JSON.stringify(snap.projections?.values?.sessionListMetadata).slice(0, 500))
    ws.close()
    process.exit(0)
  }
})

setTimeout(() => { console.log('timeout, no snapshot'); process.exit(1) }, 8000)
