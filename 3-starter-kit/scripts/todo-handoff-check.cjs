#!/usr/bin/env node
// 인계 메모 카드 대조기 — `node scripts/todo-handoff-check.cjs [CLAUDE.local.md 경로]`(울타리 밖 · GitLab 리모트 repo 루트에서)
// 하는 일: CLAUDE.local.md 의 `## 🔴` 절(인계 절)에 적힌 카드 번호 #N 마다 GitLab 에서 지금 상태를 한 번씩 조회해 한 줄씩 낸다.
// 왜 있나: 인계문은 «쓴 시각의 사실»인데 클론에 세션이 여럿 붙어 금방 어긋난다. «조회가 이긴다»를 문장으로만 두었더니
//   /todo 가 메모를 믿고 이미 닫힌 카드를 사람에게 또 물었다(배포처 bnsone 11/02 #989 · 11/11 #1137 · 11/17 #1249 · 11/18 #1281·#1287·#754).
// 출력: `#N<TAB>열림<TAB>라벨,…<TAB>제목` · `#N<TAB>닫힘<TAB>닫힌 날<TAB>제목` · `#N<TAB>조회실패<TAB>사유`
//   마지막 줄 = `요약: 열림 a · 닫힘 b · 조회실패 c`
// 읽는 법(/todo): 닫힘 = 선택지에서 빼고 «메모와 다름: #N 닫힘» 한 줄 · 조회실패 = «확인 못 함», 그 카드를 권하지 마라 ·
//   열림이어도 라벨이 메모와 다르면 라벨이 이긴다.
// 종료 코드: 0 = 전부 조회됨(인계 절·번호가 없어도 0 — 그 사실을 한 줄로 낸다) · 2 = 하나라도 조회실패 또는 파일을 못 읽음(«닫힌 것 없음» 이 아니다)
// 시험용: TODO_HANDOFF_FAKE=<json 파일> 이면 glab 대신 {"N": {"state":"opened","labels":[..],"title":"..","closed_at":".."} | "fail"} 을 읽는다.
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');

const file = process.argv[2] || 'CLAUDE.local.md';
let text;
try { text = fs.readFileSync(file, 'utf8'); }
catch (e) { console.error(`⛔ ${file} 을 못 읽음 — 대조 불능(«인계 없음» 이 아니다): ${e.code || e.message}`); process.exit(2); }

// 인계 절 = `## ` 로 시작하고 🔴 가 든 머리부터 다음 `## ` 머리 앞까지
const lines = text.split('\n');
const start = lines.findIndex((l) => /^## /.test(l) && l.includes('🔴'));
if (start < 0) { console.log('인계 절(## 🔴) 없음 — 대조할 카드 없음'); process.exit(0); }
let end = lines.findIndex((l, i) => i > start && /^## /.test(l));
if (end < 0) end = lines.length;
const section = lines.slice(start, end).join('\n');

// #N — 앞이 글자·숫자·`&` 가 아닌 것만(HTML 엔티티·색상코드 제외). MR 은 `!N` 이라 안 걸린다.
const nums = [...new Set([...section.matchAll(/(?<![\w&#])#(\d{1,6})\b/g)].map((m) => m[1]))];
if (nums.length === 0) { console.log('인계 절에 카드 번호(#N) 없음'); process.exit(0); }

let fake = null;
if (process.env.TODO_HANDOFF_FAKE) fake = JSON.parse(fs.readFileSync(process.env.TODO_HANDOFF_FAKE, 'utf8'));

function fetchIssue(n) {
  if (fake) {
    const v = fake[n];
    if (v === undefined || v === 'fail') throw new Error('가짜 조회실패');
    return v;
  }
  const out = execFileSync('glab', ['api', `projects/:id/issues/${n}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 });
  return JSON.parse(out);
}

const count = { 열림: 0, 닫힘: 0, 조회실패: 0 };
for (const n of nums) {
  let it;
  try { it = fetchIssue(n); }
  catch (e) {
    count.조회실패++;
    const why = String((e.stderr && String(e.stderr)) || e.message).split('\n').find((s) => s.trim()) || '알 수 없음';
    console.log(`#${n}\t조회실패\t${why.slice(0, 120)}`);
    continue;
  }
  const title = String(it.title || '').slice(0, 60);
  if (it.state === 'closed') {
    count.닫힘++;
    console.log(`#${n}\t닫힘\t${String(it.closed_at || '').slice(0, 10) || '날짜 모름'}\t${title}`);
  } else if (it.state === 'opened') {
    count.열림++;
    console.log(`#${n}\t열림\t${(it.labels || []).join(',') || '라벨 없음'}\t${title}`);
  } else {
    count.조회실패++;
    console.log(`#${n}\t조회실패\tstate 값이 낯섦(${it.state})`);
  }
}
console.log(`요약: 열림 ${count.열림} · 닫힘 ${count.닫힘} · 조회실패 ${count.조회실패}`);
process.exit(count.조회실패 ? 2 : 0);
