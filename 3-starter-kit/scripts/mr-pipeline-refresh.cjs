#!/usr/bin/env node
// MR 파이프라인을 «게이트 라벨을 읽은 판»으로 맞춘다 — 필요할 때만 새로 만들고, 새로 만들면 같은 커밋의 앞 것을 취소한다.
//
// 왜 있나: 게이트 잡은 MR 라벨(`셀프승인`·`고위험`)을 **파이프라인 생성 시점**에 읽는다. 그래서 절차가
//   «라벨을 붙이고 새 파이프라인을 돌려라»였는데, 그 문장은 «라벨이 이미 붙은 채 push 했다(MR 을 라벨과 함께 만든
//   경우 포함)»를 가리지 않았다. push 가 만든 파이프라인이 이미 라벨을 읽었는데도 한 벌을 더 만들면, GitLab 의
//   자동 취소는 **커밋이 달라야만** 서므로 같은 커밋의 두 벌이 끝까지 돈다. 러너 자리는 한정돼 있어 그 한 벌이
//   남의 MR 을 대기열에 세운다.
// 판정축은 시각이다: «지금 붙어 있는 게이트 라벨이 마지막으로 붙은 때» 가 «현재 커밋의 파이프라인이 만들어진 때» 보다
//   늦으면 그 파이프라인은 라벨을 못 읽었다 → 새로 만든다. 아니면 아무것도 하지 않는다.
//
// 사용: node scripts/mr-pipeline-refresh.cjs <MR번호> [--dry-run] [--force]     (glab 인증·현재 repo 컨텍스트 사용)
// 출력: 1행 = 토큰 — 2행부터 사유·파이프라인 번호.
//   유지 = 할 일 없음(이미 라벨을 읽었다) · 대기 = 현재 커밋의 파이프라인이 아직 없다, 잠시 뒤 다시 돌려라
//   새로만듦 = 만들고 앞 것을 취소했다 · 새로만들것 = --dry-run 이라 말만 했다
// 종료코드: 0 = 판정·실행 성공 / 2 = 조회·생성·취소 실패(판정 불능 — «유지»로 위장하지 않는다)
// 자기시험 = scripts/test-mr-pipeline-refresh.sh (가짜 glab 으로 «무엇을 불렀나»를 단언한다)
const { execFileSync } = require('child_process');

const iid = process.argv[2];
const dryRun = process.argv.includes('--dry-run');
const force = process.argv.includes('--force');
if (!iid || !/^\d+$/.test(iid)) {
  console.error('사용: node scripts/mr-pipeline-refresh.cjs <MR번호> [--dry-run] [--force]');
  process.exit(2);
}

// 게이트 잡의 rules 가 읽는 라벨 — `.gitlab-ci.yml` 의 `high-risk-gate`(셀프승인 자동 통과 규칙)·
//   `high-risk-label-gate`(고위험 라벨 입구)와 맞춘다. 라벨 입구를 더하거나 이름을 바꾸면 여기도 함께 고쳐라.
const GATE_LABELS = ['셀프승인', '고위험'];
// 러너 자리를 차지하고 있거나 곧 차지할 상태만 취소한다. `manual`(게이트에 서 있는 파이프라인)·끝난 것은 건드리지 않는다.
const ACTIVE = ['created', 'waiting_for_resource', 'preparing', 'pending', 'running'];

function glab(args) {
  return execFileSync('glab', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 });
}
function get(path) {
  return JSON.parse(glab(['api', path]));
}
function die(what, e) {
  console.error(`${what} 실패(판정 불능):`, String(e && e.message ? e.message : e).split('\n')[0]);
  process.exit(2);
}

let mr;
try {
  mr = get(`projects/:id/merge_requests/${iid}`);
  if (!mr || typeof mr !== 'object' || !mr.sha || !Array.isArray(mr.labels)) throw new Error('MR 응답에 sha·labels 가 없다 — MR 번호 확인');
} catch (e) {
  die('MR 조회', e);
}

const present = GATE_LABELS.filter((l) => mr.labels.includes(l));
if (present.length === 0) {
  console.log('유지');
  console.log(`사유: MR 에 게이트 라벨(${GATE_LABELS.join('·')})이 없다 — 파이프라인이 다시 읽을 것이 없다`);
  process.exit(0);
}

const head = mr.head_pipeline;
if (!head || head.sha !== mr.sha) {
  // push 직후 몇 초는 새 커밋의 파이프라인이 아직 안 보인다. 여기서 만들면 push 가 만드는 것과 두 벌이 된다.
  // 토큰을 «유지» 와 가른다 — «유지» 는 «할 일 없음» 인데 이 갈래는 «아직 모른다, 다시 물어라» 다.
  //   같은 토큰이면 라벨을 못 읽은 파이프라인이 곧 생겨도 아무도 다시 안 돌려 게이트가 manual 로 서 있게 된다.
  console.log('대기');
  console.log(`사유: 현재 커밋(${mr.sha.slice(0, 8)})의 파이프라인이 아직 없다 — push 가 곧 만든다. 잠시 뒤 다시 돌려라`);
  process.exit(0);
}

// 지금 붙어 있는 게이트 라벨이 «마지막으로 붙은 시각» — 뗐다 다시 붙였으면 나중 것이 기준이다.
let lastAdd = 0;
let lastLabel = '';
try {
  for (let page = 1; page <= 20; page++) {
    const evs = get(`projects/:id/merge_requests/${iid}/resource_label_events?per_page=100&page=${page}`);
    if (!Array.isArray(evs)) throw new Error('라벨 이력 응답이 배열이 아니다');
    for (const e of evs) {
      if (e.action !== 'add' || !e.label || !present.includes(e.label.name)) continue;
      const t = Date.parse(e.created_at);
      if (Number.isNaN(t)) throw new Error(`라벨 이력의 시각을 못 읽었다: ${e.created_at}`);
      if (t > lastAdd) {
        lastAdd = t;
        lastLabel = e.label.name;
      }
    }
    if (evs.length < 100) break;
  }
} catch (e) {
  die('라벨 이력 조회', e);
}

const created = Date.parse(head.created_at);
if (Number.isNaN(created)) die('파이프라인 생성 시각 읽기', head.created_at);

// 이력에 «붙인 기록»이 없는데 라벨은 있다 = MR 을 만들 때부터 붙어 있었다(생성 시 라벨은 이력에 안 남을 수 있다).
//   그 경우 모든 파이프라인이 라벨을 읽었다 → 유지. (lastAdd = 0 이라 아래 비교에서 자연히 유지가 된다)
// `--force` = 시각 판정을 건너뛴다. 쓰는 자리는 하나다: «유지» 가 나왔는데 그 파이프라인의 게이트 잡이 끝내 manual 로
//   서 있을 때(`pipeline-verdict.cjs` = 게이트대기). GitLab 은 파이프라인을 «만드는 도중»에 라벨을 읽고 `created_at` 은
//   저장 시각이라, 그 사이에 붙은 라벨은 시각으로는 «먼저» 인데 실제로는 못 읽혔을 수 있다(실물 재현은 안 됐다).
//   그때 손으로 POST 하지 말고 이 옵션을 써라 — 앞 파이프라인 취소까지 같이 한다.
if (lastAdd <= created && !force) {
  console.log('유지');
  console.log(`사유: 파이프라인 ${head.id} 가 라벨(${present.join('·')})이 붙은 뒤에 만들어졌다 — 이미 라벨을 읽었다. 새로 만들면 같은 커밋에 두 벌이 돈다`);
  process.exit(0);
}

const why =
  lastAdd > created
    ? `라벨 '${lastLabel}' 이 파이프라인 ${head.id} 생성 뒤에 붙었다 — 그 파이프라인은 라벨을 못 읽었다`
    : `--force — 시각으로는 파이프라인 ${head.id} 가 라벨을 읽었어야 하지만 사람이 다시 만들라고 했다`;
if (dryRun) {
  console.log('새로만들것');
  console.log(`사유: ${why}`);
  process.exit(0);
}

// 만들기 먼저, 취소는 그 다음 — 생성이 실패했는데 앞 것을 취소하면 MR 에 도는 파이프라인이 하나도 안 남는다.
let fresh;
try {
  fresh = JSON.parse(glab(['api', '--method', 'POST', `projects/:id/merge_requests/${iid}/pipelines`]));
  if (!fresh || !fresh.id) throw new Error('생성 응답에 id 가 없다');
} catch (e) {
  die('새 파이프라인 생성', e);
}
console.log('새로만듦');
console.log(`새 파이프라인: ${fresh.id}`);
console.log(`사유: ${why}`);

// 같은 커밋의 앞 파이프라인 중 아직 자리를 차지하는 것만 취소한다(다른 커밋 것은 GitLab 자동 취소의 몫).
let older = [];
try {
  const all = get(`projects/:id/merge_requests/${iid}/pipelines?per_page=100`);
  if (!Array.isArray(all)) throw new Error('파이프라인 목록 응답이 배열이 아니다');
  older = all.filter((p) => p.sha === mr.sha && p.id !== fresh.id && ACTIVE.includes(p.status));
} catch (e) {
  // 새 파이프라인은 이미 만들어졌다 — 취소만 못 한 것이므로 판정 불능(2)으로 끝내되 무엇이 남았는지 말한다.
  console.error('앞 파이프라인 목록 조회 실패 — 취소를 못 했다(두 벌이 돌 수 있다):', String(e.message).split('\n')[0]);
  process.exit(2);
}
let cancelFailed = false;
for (const p of older) {
  try {
    glab(['api', '--method', 'POST', `projects/:id/pipelines/${p.id}/cancel`]);
    console.log(`취소: ${p.id} (${p.status})`);
  } catch (e) {
    cancelFailed = true;
    console.error(`취소 실패: ${p.id} —`, String(e.message).split('\n')[0]);
  }
}
if (older.length === 0) console.log('취소할 앞 파이프라인 없음(이미 끝났거나 게이트에 서 있다)');
process.exit(cancelFailed ? 2 : 0);
