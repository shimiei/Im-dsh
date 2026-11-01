// 临时探针：看 session/list 的字段结构，以及按 cwd 能分出多少「项目」。
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = execFileSync('node', [path.join(here, 'dsh-rpc.mjs'), 'session/list', '{"_request":{}}'], {
  maxBuffer: 1024 * 1024 * 256,
  encoding: 'utf8',
});
const json = JSON.parse(out);
const items = json.items ?? json.value?.items ?? [];
console.log('total items:', items.length);
console.log('item keys:', Object.keys(items[0] ?? {}).join(', '));
console.log('--- 第一条（截断）---');
console.log(JSON.stringify(items[0], null, 2).slice(0, 1800));

const groups = new Map();
for (const it of items) {
  const cwd = it.cwd || it.workspace || '(none)';
  groups.set(cwd, (groups.get(cwd) ?? 0) + 1);
}
console.log('--- 按 cwd 分组（' + groups.size + ' 组）---');
[...groups.entries()]
  .sort((a, b) => b[1] - a[1])
  .slice(0, 40)
  .forEach(([k, v]) => console.log(String(v).padStart(4), k));

// 顶层（非 subagent）单独统计
const top = items.filter((x) => !x.parentSessionId);
const topGroups = new Map();
for (const it of top) {
  const cwd = it.cwd || it.workspace || '(none)';
  topGroups.set(cwd, (topGroups.get(cwd) ?? 0) + 1);
}
console.log('--- 仅顶层会话按 cwd（' + top.length + ' 条 / ' + topGroups.size + ' 组）---');
[...topGroups.entries()]
  .sort((a, b) => b[1] - a[1])
  .forEach(([k, v]) => console.log(String(v).padStart(4), k));
