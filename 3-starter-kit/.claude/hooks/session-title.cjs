#!/usr/bin/env node
// UserPromptSubmit 훅 — `/dev N`·`/fix N`·`/done N` 를 치면 세션 제목을 «dev N» 형태로 붙인다.
// 사람이 준 제목(`claude -n`·`/rename`)은 덮어쓰지 않는다. 번호 없는 명령은 건드리지 않는다.
// 같은 카드의 뒤 명령(dev 660 → done 660)은 처음 제목을 유지하고, 카드가 다르면 갱신한다.
// 출력 형식 = 공식 훅 문서 UserPromptSubmit `hookSpecificOutput.sessionTitle`.
'use strict';

const OURS = /^(dev|fix|done) (\d+)$/;
// 원문(`/dev 660`) 또는 스킬이 펼쳐진 형태(`<command-name>/dev</command-name><command-args>660</command-args>`)
const RAW = /^\s*\/(dev|fix|done)\s+#?(\d+)\b/;
const EXPANDED = /<command-name>\s*\/?(dev|fix|done)\s*<\/command-name>[\s\S]*?<command-args>\s*#?(\d+)\b/;

function decide(input) {
  const prompt = typeof input.prompt === 'string' ? input.prompt : '';
  const m = prompt.match(RAW) || prompt.match(EXPANDED);
  if (!m) return null;
  const title = `${m[1]} ${m[2]}`;
  const cur = typeof input.session_title === 'string' ? input.session_title.trim() : '';
  if (cur) {
    const mine = cur.match(OURS);
    if (!mine) return null;            // 사람이 준 제목 — 건드리지 않는다
    if (mine[2] === m[2]) return null; // 같은 카드 — 처음 제목 유지
  }
  return title;
}

let raw = '';
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch (e) { process.exit(0); } // 읽지 못하면 조용히 통과(제목은 편의 기능)
  const title = decide(input);
  if (title) {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: { hookEventName: 'UserPromptSubmit', sessionTitle: title },
    }) + '\n');
  }
  process.exit(0);
});
