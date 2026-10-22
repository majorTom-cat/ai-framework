#!/usr/bin/env node
// 머지 전 경고 처리 확인 — allow_failure 잡의 경고를 담당 AI 가 읽고 경고별로 처리했는지, MR 댓글 기록으로 확인한다.
// 왜: allow_failure 잡(mr-warnings·density-check)은 실패해도 파이프라인이 초록이고, pipeline-verdict 는 경고를 이름만 덧붙인다.
//     «읽었다»는 증거가 없어서 경고가 무음으로 머지된다. 사용자가 경고를 대신 읽는 구조로 만들지 않는다(배포처 bnsone #789).
// 사용: node scripts/warning-ack.cjs <MR iid>   (glab 인증·현재 repo 컨텍스트 사용 — pipeline-verdict 와 같은 방식)
// 출력: 1행 = 토큰(경고없음|경고처리됨|경고미처리|미종료) — 스킬은 이 1행만 파싱한다. 상세는 2행부터.
// 종료코드: 0=판정함(토큰 무관) / 2=조회 실패·인자 오류(판정 불능 — «경고없음»으로 위장하지 않는다)
//
// 대상: MR 의 «현재 head SHA» 의 head pipeline. 파이프라인 sha 가 MR sha 와 다르면(낡은 파이프라인) 미종료.
// 경고 잡 = status failed + allow_failure. allow_failure 잡이 아직 안 끝났으면 미종료(끝나기 전에 경고없음이라 하지 않는다).
// 경고 항목 = 잡 로그에서 «[검사이름] 시작» ~ «[검사이름] ⛔ 실패» 사이의 줄머리 `[경고:키]` — 키가 항목, 키가 없으면 검사이름이 항목,
//   실패 구간 자체가 없으면 잡 이름이 항목이다(✅ 통과 구간의 키는 버린다). 이 접두 규약은 배포처가 경고 출력부에서 찍는다(킷 제안, 바꾸면 이 파일과 시험을 같이 고쳐라).
// 처리 기록 = MR 댓글(시스템 댓글 제외). 머리 줄에 `sha=<40자> pipeline=<id> job=<id>`, 이어서 항목마다
//   `- <키>: 수정함|수정불필요 — <근거>`. 머리 줄 하나 = 잡 하나(잡이 둘이면 머리 줄 둘, 한 댓글에 같이 써도 된다).
// ⚠️이 도구가 보는 것은 «대상(sha·pipeline·job) 일치 + 모든 항목 존재 + 처리값 + 근거가 비어 있지 않음» 뿐이다.
//   근거의 진위는 보장하지 않는다 — 그건 리뷰의 몫이다. 로그 원문·토큰은 출력하지 않는다(키·잡 이름만).
const { execFileSync } = require('child_process');

const iid = process.argv[2];
if (!iid || !/^\d+$/.test(iid)) {
  console.error('사용: node scripts/warning-ack.cjs <MR iid>');
  process.exit(2);
}

function die(msg) {
  console.error('조회 실패(판정 불능):', String(msg).split('\n')[0]);
  process.exit(2);
}

function api(path) {
  try {
    return execFileSync('glab', ['api', path], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 60000,
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch (e) {
    die(`${path}: ${e.stderr ? String(e.stderr) : e.message}`);
  }
}
function apiJson(path) {
  try {
    return JSON.parse(api(path));
  } catch (e) {
    die(`${path}: JSON 이 아니다`);
  }
}

const UNFINISHED = ['created', 'pending', 'preparing', 'waiting_for_resource', 'scheduled', 'running', 'canceled'];
const HEADER = /sha=([0-9a-f]{40})\s+pipeline=(\d+)\s+job=(\d+)/;
const ITEM = /^\s*[-*]\s*(.+?)\s*:\s*(수정함|수정불필요)\s*(?:—|–|--|-)\s*(\S.*?)\s*$/;
const ANSI = /\x1b\[[0-9;?]*[A-Za-z]/g;

const mr = apiJson(`projects/:id/merge_requests/${iid}`);
const mrSha = mr && mr.sha;
if (!mrSha || !/^[0-9a-f]{40}$/.test(mrSha)) die(`MR !${iid} 의 head sha 를 못 읽었다`);
const pl = mr.head_pipeline;
const head = `MR !${iid} sha ${mrSha.slice(0, 8)}`;

if (!pl || !pl.id) {
  console.log('미종료');
  console.log(`${head} — 이 커밋의 파이프라인이 아직 없다(생기면 다시 돌려라)`);
  process.exit(0);
}
if (pl.sha !== mrSha) {
  console.log('미종료');
  console.log(`${head} — 파이프라인 ${pl.id} 는 다른 커밋(${String(pl.sha).slice(0, 8)})의 것이다(낡은 파이프라인 — 새 파이프라인을 기다려라)`);
  process.exit(0);
}

const jobs = apiJson(`projects/:id/pipelines/${pl.id}/jobs?per_page=100`);
if (!Array.isArray(jobs) || jobs.length === 0) die(`파이프라인 ${pl.id} 의 잡 0개`);

const unfinished = jobs.filter((j) => j.allow_failure && UNFINISHED.includes(j.status));
if (unfinished.length) {
  console.log('미종료');
  console.log(`${head} 파이프라인 ${pl.id} — 아직 끝나지 않은 경고 잡: ${unfinished.map((j) => `${j.name}(${j.status})`).join(', ')}`);
  process.exit(0);
}

const warnJobs = jobs.filter((j) => j.allow_failure && j.status === 'failed');
if (warnJobs.length === 0) {
  console.log('경고없음');
  console.log(`${head} 파이프라인 ${pl.id} — allow_failure 실패 잡 없음`);
  process.exit(0);
}

// 항목 뽑기 — 로그 원문은 출력하지 않고 키·이름만 쓴다.
// 실제 로그 순서(scripts/ci-run-checks.sh): «════ [이름] 시작 ════» → 검사 출력 → «════ [이름] ✅ 통과|⛔ 실패 (종료코드 N) ════».
// 키는 시작~결과 머리 줄 «사이»에 찍히고, 결과가 ⛔ 실패인 구간의 것만 항목이다(✅ 통과 구간의 키는 버린다).
function itemsOf(job) {
  const trace = api(`projects/:id/jobs/${job.id}/trace`).replace(ANSI, '').replace(/\r/g, '');
  const sections = []; // 실패한 검사 { name, keys }
  let cur = null; // 열려 있는 구간 { name, keys }
  for (const line of trace.split('\n')) {
    const st = /^\s*═{3,}\s*\[([^\]]+)\]\s*시작/.exec(line);
    if (st) { cur = { name: st[1].trim(), keys: [] }; continue; }
    const rs = /^\s*═{3,}\s*\[([^\]]+)\]\s*(✅\s*통과|⛔\s*실패)/.exec(line);
    if (rs) {
      const name = rs[1].trim();
      if (/실패/.test(rs[2])) sections.push({ name, keys: cur && cur.name === name ? cur.keys : [] });
      cur = null;
      continue;
    }
    const k = cur && /^\s*\[경고:([^\]\s]{1,80})\]/.exec(line);
    if (k && !cur.keys.includes(k[1])) cur.keys.push(k[1]);
  }
  const keys = [];
  for (const s of sections) for (const k of s.keys.length ? s.keys : [s.name]) if (!keys.includes(k)) keys.push(k);
  return keys.length ? keys : [job.name];
}

// 댓글 → 잡별 기록 블록(머리 줄 하나 = 블록 하나).
const notes = [];
for (let page = 1; page <= 10; page++) {
  const batch = apiJson(`projects/:id/merge_requests/${iid}/notes?per_page=100&page=${page}`);
  if (!Array.isArray(batch)) die('댓글 목록이 배열이 아니다');
  notes.push(...batch);
  if (batch.length < 100) break;
}
const blocks = []; // { sha, pipeline, job, order, items: Map(key → {value, reason}) }
notes
  .filter((n) => n && !n.system && typeof n.body === 'string')
  .sort((a, b) => (a.id || 0) - (b.id || 0))
  .forEach((n) => {
    let cur = null;
    for (const raw of n.body.split(/\r?\n/)) {
      const h = HEADER.exec(raw);
      if (h) { cur = { sha: h[1], pipeline: h[2], job: h[3], order: n.id || 0, items: new Map() }; blocks.push(cur); continue; }
      const m = cur && ITEM.exec(raw);
      if (m) cur.items.set(m[1], { value: m[2], reason: m[3] });
    }
  });

const out = [];
let missingAny = false;
for (const job of warnJobs) {
  const keys = itemsOf(job);
  const mine = blocks.filter((b) => b.sha === mrSha && b.pipeline === String(pl.id) && b.job === String(job.id));
  const items = new Map(); // 같은 (sha,pipeline,job) 기록이 여럿이면 합치되 같은 키는 나중 것이 이긴다
  mine.forEach((b) => b.items.forEach((v, k) => items.set(k, v)));
  const bad = [];
  for (const k of keys) {
    if (!items.get(k)) bad.push(`${k} — 처리 기록이 없다(또는 머리 줄 sha·pipeline·job 불일치·처리값·근거 누락)`);
  }
  if (bad.length) {
    missingAny = true;
    out.push(`미처리: ${job.name}(잡 ${job.id}) 항목 ${keys.length}개 중 ${bad.length}개`);
    bad.forEach((b) => out.push(`  - ${b}`));
    out.push(`  기록 머리 줄: sha=${mrSha} pipeline=${pl.id} job=${job.id}`);
    out.push(`  항목 줄 서식: - <키>: 수정함|수정불필요 — <근거>   (키: ${keys.join(' | ')})`);
  } else {
    out.push(`처리됨: ${job.name}(잡 ${job.id}) 항목 ${keys.length}개`);
  }
}
console.log(missingAny ? '경고미처리' : '경고처리됨');
console.log(`${head} 파이프라인 ${pl.id} — 경고 잡 ${warnJobs.length}개`);
out.forEach((l) => console.log(l));
process.exit(0);
