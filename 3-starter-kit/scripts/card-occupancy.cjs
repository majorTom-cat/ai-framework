#!/usr/bin/env node
// 카드 점유 대조기 — «이 카드를 이미 다른 세션·작업 폴더가 하고 있나»를 착수·권유 전에 기계로 본다.
// 쓰임: node scripts/card-occupancy.cjs <카드번호>   (울타리 밖 — ls-remote 가 망을 쓴다)
// 보는 것: ①git worktree list 의 경로(issue-N)·브랜치(…/N-…) ②원격 브랜치(…/N-…)
// 못 보는 것: 열린 세션 이름(AI 가 ListAgents 로 따로 대조) · 다른 PC 의 로컬 작업
// 종료: 0 = 신호 없음 · 1 = 점유 신호 있음 · 2 = 조회 실패(판정 불능 — «없음»으로 읽지 마라)
// 시험 훅: CARD_OCC_FAKE='{"worktree":"<porcelain>"|"fail","remote":"<ls-remote 출력>"|"fail"}'
'use strict';
const { execFileSync } = require('child_process');

const n = process.argv[2];
if (!/^\d{1,6}$/.test(n || '')) {
  console.error('쓰임: node scripts/card-occupancy.cjs <카드번호>');
  process.exit(2);
}

const fake = process.env.CARD_OCC_FAKE ? JSON.parse(process.env.CARD_OCC_FAKE) : null;
function run(key, args) {
  if (fake) {
    if (fake[key] === 'fail') throw new Error('가짜 실패');
    return fake[key] || '';
  }
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 });
}

// 브랜치 마지막 마디가 «N» 또는 «N-…» 인가 (12 가 112·1234 에 걸리지 않게)
const branchRe = new RegExp(`(?:^|/)${n}(?:-|$)`);
const pathRe = new RegExp(`issue-${n}(?![0-9])`);

const hits = [];
let failed = 0;

try {
  const out = run('worktree', ['worktree', 'list', '--porcelain']);
  for (const block of out.split(/\n\s*\n/)) {
    const wt = (block.match(/^worktree (.+)$/m) || [])[1];
    if (!wt) continue;
    const br = ((block.match(/^branch (.+)$/m) || [])[1] || '').replace(/^refs\/heads\//, '');
    if (pathRe.test(wt) || (br && branchRe.test(br))) hits.push(`워크트리\t${wt}\t${br || '(분리 HEAD)'}`);
  }
} catch (e) {
  failed++;
  console.log(`조회실패\t워크트리\t${(e.message || '').split('\n')[0]}`);
}

try {
  const out = run('remote', ['ls-remote', '--heads', 'origin']);
  for (const line of out.split('\n')) {
    const ref = (line.split('\t')[1] || '').trim().replace(/^refs\/heads\//, '');
    if (ref && branchRe.test(ref)) hits.push(`원격 브랜치\t${ref}`);
  }
} catch (e) {
  failed++;
  console.log(`조회실패\t원격 브랜치\t${(e.message || '').split('\n')[0]}`);
}

for (const h of hits) console.log(h);
console.log(`요약: #${n} 점유 신호 ${hits.length}건 · 조회실패 ${failed}건 — 세션 이름은 ListAgents 로 따로 대조 · 다른 PC 는 못 본다`);
process.exit(failed ? 2 : hits.length ? 1 : 0);
