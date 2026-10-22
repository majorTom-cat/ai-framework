#!/usr/bin/env node
// 파이프라인 실질 종결 판정기 — status 한 값 대신 **잡 단위**로 판정한다 (킷 2026-08-09 라운드2).
// 왜: 수동 게이트 잡이 있는 파이프라인은 실질 종결이어도 status가 manual(blocked)에 머물고(bnsone #34),
//     반대로 allow_failure 잡 실패는 status=success에 가려진다(파일럿 2863) — status 한 값은 양방향으로 속인다.
// 사용: node scripts/pipeline-verdict.cjs <파이프라인ID>   (glab 인증·현재 repo 컨텍스트 사용)
// 출력: 1행 = 판정 토큰(실패|취소|진행중|게이트대기|종결초록) — 스킬은 이 1행만 파싱한다. 상세는 2행부터.
//   ※`취소` 는 통과가 아니다 — 더 새 커밋에 밀려 끊긴 것일 뿐 그 커밋의 검사·배포가 끝났다는 뜻이 없다(#826).
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
// ①차단형 잡이 failed → 실패(canceled 가 섞여도 실패가 우선)  ②failed 없이 차단형 canceled → 취소
// ③아직 돌(예정인) 잡 잔존(canceling·scheduled·모르는 상태 포함) → 진행중
// ④차단형 게이트가 manual/created로 잔존 → 게이트대기(승인 대기 — 절대 '종결'로 보고하지 않는다: 게이트 우회 방지)
// ⑤나머지(성공·skipped·무시 가능 manual만 잔존) → 종결초록
const failedBlocking = jobs.filter((j) => j.status === 'failed' && !j.allow_failure);
const canceledBlocking = jobs.filter((j) => j.status === 'canceled' && !j.allow_failure);
// canceling(취소 진행 중)·scheduled(지연 실행 대기)는 아직 끝나지 않은 잡이다 — canceling 은 곧 canceled 로 굳으니 «취소» 가 아니라 «진행중»
//   으로 두고 다시 판정하게 한다(굳기 전엔 실패·취소 여부를 확정할 수 없다). 모르는 새 상태값도 «종결» 로 흘리지 않고 진행중으로 막는다(#828).
const SETTLED = ['success', 'failed', 'canceled', 'skipped', 'manual', 'created'];
const RUNNING = ['running', 'pending', 'preparing', 'waiting_for_resource', 'canceling', 'scheduled'];
const stillRunning = jobs.filter((j) => RUNNING.includes(j.status));
const unknownStatus = jobs.filter((j) => !SETTLED.includes(j.status) && !RUNNING.includes(j.status));
const gateWaiting = jobs.filter((j) => ['manual', 'created'].includes(j.status) && isGate(j));
const createdNonGate = jobs.filter((j) => j.status === 'created' && !isGate(j));

let verdict;
if (failedBlocking.length) verdict = '실패';
else if (canceledBlocking.length) verdict = '취소';
else if (stillRunning.length || createdNonGate.length || unknownStatus.length) verdict = '진행중';
else if (gateWaiting.length) verdict = '게이트대기';
else verdict = '종결초록';

console.log(verdict);
if (verdict === '실패') {
  failedBlocking.forEach((j) => console.log(`실패 잡: ${j.id} ${j.name} (${j.status})`));
  canceledBlocking.forEach((j) => console.log(`취소 잡: ${j.id} ${j.name} (${j.status})`));
}
if (verdict === '취소') {
  canceledBlocking.forEach((j) => console.log(`취소 잡: ${j.id} ${j.name} (${j.status})`));
  // 대신 도는 파이프라인을 여기서 단정하지 않는다 — 취소 사유(새 커밋·사람 취소·시간 초과)를 잡 목록만으로는 못 가린다.
  console.log('안내: 통과 아님 — 더 새 파이프라인이 대신 돌 수 있으나 이 판정만으로 확정하지 않는다. MR 은 현재 head_pipeline 을 다시 판정(같은 ID 면 대신 도는 것이 없다 — 사람에게 보고), 머지 뒤 배포는 검수 서버 health sha 가 머지 커밋의 후손인지로 확인.');
  console.log('안내: 취소는 revert 사유가 아니다(실패 잡 없음).');
}
if (verdict === '진행중') {
  jobs.filter((j) => ['canceling', 'scheduled'].includes(j.status)).forEach((j) => console.log(`아직 안 끝난 잡: ${j.id} ${j.name} (${j.status}) — 굳은 뒤 다시 판정`));
  unknownStatus.forEach((j) => console.log(`모르는 상태: ${j.id} ${j.name} (${j.status}) — 종결로 읽지 않고 진행중으로 막는다(이 판정기에 상태를 더해야 한다)`));
}
if (verdict === '게이트대기') gateWaiting.forEach((j) => console.log(`남은 게이트 잡: ${j.id} ${j.name} (${j.status})`));
// 경고 가시화(파일럿 2863 실측): allow_failure 잡의 실패는 status에 안 드러난다 — 어느 판정이든 덧붙인다.
jobs.filter((j) => j.status === 'failed' && j.allow_failure).forEach((j) => console.log(`경고(allow_failure 실패): ${j.name} (잡 ${j.id}) — 머지 전 warning-ack.cjs 로 처리 기록 확인`));
