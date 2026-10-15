#!/usr/bin/env node
// 이슈 워크트리 정리 후보 점검기 — `node scripts/worktree-sweep.cjs [--repo <본 클론 경로>]`
// 하는 일: 본 클론이 아닌 워크트리마다 «지워도 되나»를 판정해 한 줄씩 낸다. **아무것도 지우지 않는다**(보고만).
// 왜 있나: 정리가 /done 8단계 «merged 를 눈으로 본 뒤»에만 돌아서, 킷동기(/done 을 안 거침)·auto-merge 대기 중 세션 종료·
//   닫힌 MR 의 커밋이 브랜치 끝에 남은 경우는 아무도 안 지운다(배포처 bnsone 2026-10-16: 킷동기 워크트리 4개 방치).
// 판정 = 넷 다: ①깨끗함(status 비어 있음) ②다른 세션이 안 씀(.claude/.session-lock 의 살아 있는 pid 없음)
//   ③내용이 main 에 있음 — 아래 셋 중 하나:
//     A 브랜치 끝이 origin/main 의 조상 · B 그 브랜치의 머지된 MR 의 sha 가 브랜치 끝과 같음(glab) ·
//     C 브랜치가 main 과 갈라진 뒤 바꾼 파일이 전부 origin/main 에서 같은 내용(닫힌 MR 뒤 다른 브랜치로 들어간 경우)
//   ※커밋 포함 여부(A)만 보면 C 를 놓친다. 내용이 main 에 없으면(= 푸시 안 된 일이 있다) 반드시 «보류».
// 먼저 `git fetch origin` 을 해 둬라(안 하면 origin/main 이 낡아 «main 에 없음» 으로 오판한다).
// 종료 코드: 0 = 점검 끝(정리 가능 0개여도) · 2 = 점검 불능(git 이 안 돈다 등)
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const ri = args.indexOf('--repo');
const REPO = path.resolve(ri >= 0 ? args[ri + 1] : process.cwd());
const NO_GLAB = process.env.WORKTREE_SWEEP_NO_GLAB === '1';

function git(cwd, ...a) {
  return execFileSync('git', ['-C', cwd, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}
function gitOk(cwd, ...a) {
  try { execFileSync('git', ['-C', cwd, ...a], { stdio: 'ignore' }); return true; } catch (e) { return false; }
}

let list;
try { list = git(REPO, 'worktree', 'list', '--porcelain'); }
catch (e) { console.error('⛔ git worktree list 실패 — 점검 불능(정리할 게 없다는 뜻이 아니다):', String(e.message).split('\n')[0]); process.exit(2); }

const trees = [];
let cur = null;
for (const line of list.split('\n')) {
  if (line.startsWith('worktree ')) { cur = { path: line.slice(9) }; trees.push(cur); }
  else if (cur && line.startsWith('branch ')) cur.branch = line.slice(7).replace(/^refs\/heads\//, '');
  else if (cur && line === 'detached') cur.detached = true;
  else if (cur && line === 'bare') cur.bare = true;
}
const main = trees.shift(); // 첫 항목 = 본 클론

function inUse(wt) {
  const lock = path.join(wt, '.claude', '.session-lock');
  if (!fs.existsSync(lock)) return false;
  for (const l of fs.readFileSync(lock, 'utf8').split('\n')) {
    const pid = parseInt(l.split('\t')[0], 10);
    if (!pid) continue;
    try { process.kill(pid, 0); return true; } catch (e) { if (e.code === 'EPERM') return true; }
  }
  return false;
}

function contentInMain(wt, tip) {
  // C: 갈라진 지점 이후 바꾼 파일이 전부 origin/main 에서 같은 내용인가
  let base;
  try { base = git(wt, 'merge-base', 'origin/main', tip).trim(); } catch (e) { return null; }
  const files = git(wt, 'diff', '--name-only', base, tip).split('\n').filter(Boolean);
  if (files.length === 0) return true;
  const blob = (ref, f) => { try { return git(wt, 'rev-parse', '--verify', '-q', `${ref}:${f}`).trim(); } catch (e) { return 'ABSENT'; } };
  for (const f of files) if (blob(tip, f) !== blob('origin/main', f)) return false;
  return true;
}

function mergedMrSha(branch) {
  if (NO_GLAB) return { unknown: true };
  try {
    const out = execFileSync('glab', ['api', `projects/:id/merge_requests?source_branch=${encodeURIComponent(branch)}&state=merged&per_page=20`],
      { cwd: REPO, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return { shas: JSON.parse(out).map((m) => m.sha) };
  } catch (e) { return { unknown: true }; }
}

const rows = [];
for (const t of trees) {
  const where = `${t.path}${t.branch ? '  ' + t.branch : ''}`;
  if (t.bare || t.detached || !t.branch) { rows.push(['보류', where, '브랜치가 없다(분리된 HEAD) — 사람이 본다']); continue; }
  let dirty;
  try { dirty = git(t.path, 'status', '--short').trim(); } catch (e) { rows.push(['보류', where, '폴더를 못 읽는다(이미 지워졌나) — `git worktree prune` 후보']); continue; }
  if (dirty) { rows.push(['보류', where, `저장 안 된 변경 ${dirty.split('\n').length}건`]); continue; }
  if (inUse(t.path)) { rows.push(['보류', where, '다른 세션이 쓰는 중']); continue; }
  const tip = git(t.path, 'rev-parse', 'HEAD').trim();
  if (gitOk(t.path, 'merge-base', '--is-ancestor', tip, 'origin/main')) { rows.push(['정리 가능', where, 'A 브랜치 끝이 main 에 들어 있다']); continue; }
  const c = contentInMain(t.path, tip);
  if (c === true) { rows.push(['정리 가능', where, 'C 바꾼 파일이 전부 main 과 같은 내용(다른 경로로 들어갔다)']); continue; }
  const mr = mergedMrSha(t.branch);
  if (mr.shas && mr.shas.includes(tip)) { rows.push(['정리 가능', where, 'B 머지된 MR 의 sha 와 브랜치 끝이 같다']); continue; }
  const why = mr.unknown ? 'main 에 없는 변경이 있다 · MR 상태는 조회 못 함(판정 불능)' : 'main 에 없는 변경이 있다(푸시·머지 안 된 일)';
  rows.push(['보류', where, why]);
}

const ok = rows.filter((r) => r[0] === '정리 가능').length;
for (const r of rows) console.log(`${r[0]}\t${r[1]}\t${r[2]}`);
console.log(`워크트리 ${rows.length}개 중 정리 가능 ${ok}개 · 보류 ${rows.length - ok}개 (이 도구는 지우지 않는다 — 지우는 순서는 /done 단계상세 §4)`);
process.exit(0);
