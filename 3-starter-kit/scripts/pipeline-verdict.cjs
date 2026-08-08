#!/usr/bin/env node
// 파이프라인 실질 종결 판정기 — status 한 값 대신 **잡 단위**로 판정한다 (킷 2026-08-09 라운드2).
// 왜: 수동 게이트 잡이 있는 파이프라인은 실질 종결이어도 status가 manual(blocked)에 머물고(bnsone #34),
//     반대로 allow_failure 잡 실패는 status=success에 가려진다(파일럿 2863) — status 한 값은 양방향으로 속인다.
// 사용: node scripts/pipeline-verdict.cjs <파이프라인ID>   (glab 인증·현재 repo 컨텍스트 사용)
// 출력: 1행 = 판정 토큰(실패|진행중|게이트대기|종결초록) — 스킬은 이 1행만 파싱한다. 상세는 2행부터.
// 종료코드: 0=판정 성공(내용 무관) / 2=조회 실패(판정 불능 — "모름"을 실패로 위장하지 않는다)
const { execFileSync } = require('child_process');

const pid = process.argv[2];
if (!pid || !/^\d+$/.test(pid)) {
  console.error('사용: node scripts/pipeline-verdict.cjs <파이프라인ID>');
  process.exit(2);
}

// 차단형 게이트 잡 이름 — .gitlab-ci.yml의 게이트 잡과 1:1로 맞춘다(킷 표준 2종).
const GATE_NAMES = ['high-risk-gate', 'high-risk-label-gate'];

let jobs;
try {
  jobs = JSON.parse(
    execFileSync('glab', ['api', `projects/:id/pipelines/${pid}/jobs?per_page=100`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 60000,
    })
  );
  if (!Array.isArray(jobs) || jobs.length === 0) throw new Error('잡 0개 — 파이프라인 ID 확인');
} catch (e) {
  console.error('조회 실패(판정 불능):', e.message.split('\n')[0]);
  process.exit(2);
}

const isGate = (j) => GATE_NAMES.includes(j.name) || (j.status === 'manual' && !j.allow_failure);
// 판정 순서가 곧 우선순위다:
// ①차단형 잡이 failed/canceled → 실패  ②아직 돌(예정인) 잡 잔존 → 진행중
// ③차단형 게이트가 manual/created로 잔존 → 게이트대기(승인 대기 — 절대 '종결'로 보고하지 않는다: 게이트 우회 방지)
// ④나머지(성공·skipped·무시 가능 manual만 잔존) → 종결초록
const failedBlocking = jobs.filter((j) => ['failed', 'canceled'].includes(j.status) && !j.allow_failure);
const stillRunning = jobs.filter((j) => ['running', 'pending', 'preparing', 'waiting_for_resource'].includes(j.status));
const gateWaiting = jobs.filter((j) => ['manual', 'created'].includes(j.status) && isGate(j));
const createdNonGate = jobs.filter((j) => j.status === 'created' && !isGate(j));

let verdict;
if (failedBlocking.length) verdict = '실패';
else if (stillRunning.length || createdNonGate.length) verdict = '진행중';
else if (gateWaiting.length) verdict = '게이트대기';
else verdict = '종결초록';

console.log(verdict);
if (verdict === '실패') failedBlocking.forEach((j) => console.log(`실패 잡: ${j.id} ${j.name}`));
if (verdict === '게이트대기') gateWaiting.forEach((j) => console.log(`남은 게이트 잡: ${j.id} ${j.name} (${j.status})`));
// 경고 가시화(파일럿 2863 실측): allow_failure 잡의 실패는 status에 안 드러난다 — 어느 판정이든 덧붙인다.
jobs.filter((j) => j.status === 'failed' && j.allow_failure).forEach((j) => console.log(`경고(allow_failure 실패): ${j.name}`));
