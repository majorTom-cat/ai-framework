#!/usr/bin/env node
// /done 합치기 판정기 — main 이 움직였을 때 «그대로 머지해도 되나»와 «합친 뒤 리뷰가 아직 유효한가»를 같은 기준으로 가른다 (배포처 bnsone #610).
// 왜: 무료 GitLab 은 «main 과 합친 결과로 시험»(머지 트레인)이 없어 /done 이 손으로 대신한다. 눈으로 따지면 갈래를 놓친다.
// 한계(솔직히): 파일이 안 겹쳐도 깨질 수 있다(함수 이름 바꿈 + 옛 이름 호출 추가). 아래 위험 경로는 그 흔한 길목을 막을 뿐이고,
//   나머지는 머지 뒤 main 파이프라인 + revert 가 2차 방어다(done/단계상세.md §0).
// 킷 규약 경로를 가정한다: src/modules/{x}/ · src/shared/ · docs/adr/NNNN- · 마이그레이션 폴더(이름이 migrations). 다르면 아래 정규식을 고쳐라.
// 사용(저장소 안에서, 현재 브랜치 HEAD 기준):
//   node scripts/done-merge-verdict.cjs main-moved [mainRef=origin/main]
//   node scripts/done-merge-verdict.cjs after-merge <리뷰한SHA 40자> [mainRef=origin/main]
// 출력: 1행 = 판정 토큰 — 스킬은 이 1행만 파싱한다. 사유는 2행부터.
//   main-moved : 최신(main 이 안 움직임) | 그대로(안 겹침 — 합치지 않고 머지 가능) | 합치기(합치고 다시 시험)
//     «합치기» 사유 = 같은 파일 · 글자 충돌 · ADR 번호 겹침 · main 의 package·lock·CI · 내가 스키마·마이그레이션을 건드릴 때 main 의 새 마이그레이션 ·
//     shared(시험 파일 제외) · «내 코드가 쓰는 모듈의 index.ts 에서 있던 줄이 지워지거나 바뀜». 같은 모듈 다른 파일만으로는 아니다(#716).
//   after-merge: 리뷰유효(병합이 main 쪽 파일만 바꿨다 · 같은 파일이면 main 이 고친 줄이 내 줄과 4줄 이상 떨어지고 기계적 병합과 같다) | 재리뷰(내 파일이 바뀌었거나 병합 중 손댔다)
// 종료코드: 0=판정함(내용 무관) / 2=판정 불능(git 실패·인자 오류 — «모름»을 어느 토큰으로도 위장하지 않는다)
const { execFileSync, spawnSync } = require('child_process');

const [mode, arg1, arg2] = process.argv.slice(2);
const SHA = /^[0-9a-f]{40}$/i;

const die = (msg) => {
  console.error('판정 불능: ' + msg);
  process.exit(2);
};
const git = (...args) => {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 });
  } catch (e) {
    return die(`git ${args.join(' ')} 실패 — ${(e.stderr || e.message).toString().split('\n')[0]}`);
  }
};
const verify = (ref) => git('rev-parse', '--verify', '--quiet', ref + '^{commit}').trim();
// -z + --no-renames: 한글 경로가 따옴표로 깨지지 않고, 이름 바꾼 파일은 옛 경로·새 경로 둘 다 목록에 든다
const names = (...range) => new Set(git('diff', '--name-only', '-z', '--no-renames', ...range).split('\0').filter(Boolean));
const added = (...range) => [...new Set(git('diff', '--name-only', '-z', '--no-renames', '--diff-filter=A', ...range).split('\0').filter(Boolean))];

const moduleOf = (p) => (/^src\/modules\/([^/]+)\//.exec(p) || [])[1];
const adrNo = (p) => (/^docs\/adr\/(\d+)-/.exec(p) || [])[1];

if (mode === 'main-moved') {
  const mainRef = arg1 || 'origin/main';
  verify('HEAD') || die('HEAD 를 못 읽었다');
  const mainSha = verify(mainRef) || die(`${mainRef} 를 못 읽었다 — git fetch origin 먼저`);
  const base = git('merge-base', 'HEAD', mainRef).trim() || die('merge-base 없음');
  if (base === mainSha) {
    console.log('최신');
    console.log(`main(${mainRef})이 내가 합친 뒤로 안 움직였다`);
    process.exit(0);
  }
  const mainNew = names(base, mainSha); // main 이 내가 마지막으로 합친 뒤 새로 바꾼 파일
  const mine = names(base, 'HEAD'); // 내 브랜치가 바꾼 파일
  const why = [];
  const overlap = [...mine].filter((p) => mainNew.has(p));
  if (overlap.length) why.push('같은 파일: ' + overlap.slice(0, 5).join(', '));
  // 위험 경로는 «내 변경에 코드가 있을 때만» 사유다 — 남의 마이그레이션·package·shared·CI 변경이 깨뜨릴 수 있는 건 코드뿐이다.
  // 문서만 바꾸는 MR 이 그 때문에 계속 «합치기» 가 되던 것이 이 카드(#610)의 실제 사례다.
  // ★fail-closed: «문서로 확인된 것만 비코드» 이고 나머지는 전부 코드다. 목록에 빠진 파일이 문서로 떨어지면(fail-open) 안 된다 —
  //   CI 는 scripts/*.cjs·*.sh 를 직접 돌리고(경계 검사기는 src 를 스캔한다) 루트 설정·런타임 파일도 깨질 수 있다(독립 리뷰가 재현).
  // 비코드 = 마크다운·텍스트(어디든), docs/ 아래에서 데이터·스크립트가 아닌 것(그림·html·pdf 등).
  // docs/ 의 json·yaml·스크립트는 CI 검사가 읽는다(예: screen-registry.json) → 코드로 친다.
  const isDoc = (p) => /\.(md|txt)$/i.test(p) || (/^docs\//.test(p) && !/\.(json|ya?ml|[cm]?[jt]sx?|sh|py)$/i.test(p));
  const appCode = (p) => !isDoc(p);
  const myCode = [...mine].filter(appCode);

  // 위험 경로를 «내 변경이 실제로 쓰는 것»으로 좁힌다(배포처 bnsone #716 — #708 에서 남의 무관한 변경 때문에 합치기가 세 바퀴(바퀴당 약 40분) 돌았다).
  // ① 같은 모듈이어도 다른 파일이면 사유가 아니다 — 같은 파일은 위 overlap, 글자 충돌은 아래 merge-tree 가 잡는다.
  //    한계: 같은 모듈 안에서 함수 이름을 바꾸고 다른 파일에서 옛 이름 호출이 늘어나는 길은 머지 뒤 main 파이프라인 + revert 가 막는다.
  const mineMods = new Set([...mine].map(moduleOf).filter(Boolean));
  const isTest = (p) => /\.(test|spec)\.[cm]?[jt]sx?$/.test(p) || /(^|\/)__tests__\//.test(p);
  // ② 모듈 index.ts 는 «있던 줄이 지워지거나 바뀔 때»만 위험하다 — export 를 더하기만 한 변경은 내 코드의 기존 import 를 못 깨뜨린다.
  const indexShrunk = (f) =>
    git('--literal-pathspecs', 'diff', '-U0', '--no-renames', base, mainSha, '--', f)
      .split('\n')
      .some((l) => l.startsWith('-') && !l.startsWith('---'));
  // 그리고 내 코드가 그 모듈을 쓸 때만이다(내 모듈이면 쓴다고 본다). 지워진 파일은 쓰지 않는 것으로 치고, 읽기 오류는 판정 불능이다.
  // «쓴다» = 내 파일 본문에 `modules/<이름>` 이 나온다(별칭 `@/modules/x`·상대경로·`src/modules/x` 모두). import 방식이 다른 repo 면 이 정규식을 고쳐라.
  const usesModule = (m) =>
    mineMods.has(m) ||
    myCode.some((p) => {
      const r = spawnSync('git', ['show', 'HEAD:' + p], { encoding: 'utf8', timeout: 60000, maxBuffer: 64 * 1024 * 1024 });
      // 읽기 «실패»(버퍼 초과·시간 초과·git 실행 오류)는 «안 쓴다» 가 아니다 — 판정 불능(fail-closed). 지워진 파일은 git show 가 비정상 종료할 뿐 r.error 가 없다.
      if (r.error) die(`내 파일 ${p} 를 못 읽었다 — ${r.error.message}`);
      return r.status === 0 && new RegExp('modules/' + m.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?![\\w-])').test(r.stdout);
    });
  // ③ 남의 새 마이그레이션은 내가 스키마·마이그레이션을 건드릴 때만(마이그레이션 순서·스키마 충돌) 사유다. ④ src/shared 의 시험 파일은 뺀다.
  const touchesSchema = [...mine].some((p) => /^prisma\//.test(p) || /(^|\/)migrations\//.test(p));
  const risky = [...mainNew].filter((p) => {
    if (/(^|\/)migrations\//.test(p)) return touchesSchema;
    if (p === 'package.json' || p === 'package-lock.json' || p === '.gitlab-ci.yml') return true;
    if (/^src\/shared\//.test(p)) return !isTest(p);
    const im = /^src\/modules\/([^/]+)\/index\.ts$/.exec(p);
    if (im) return usesModule(im[1]) && indexShrunk(p);
    return false;
  });
  let riskNote = '';
  if (risky.length && myCode.length) why.push('main 의 위험 경로(마이그레이션·package·lock·shared·모듈 index·CI): ' + risky.slice(0, 5).join(', '));
  else if (risky.length) riskNote = '참고: main 의 위험 경로 변경(' + risky.slice(0, 3).join(', ') + ')은 내 변경이 문서뿐이라 사유에서 뺐다';
  const mainAdr = new Map(added(base, mainSha).filter(adrNo).map((p) => [adrNo(p), p]));
  const adrClash = added(base, 'HEAD').filter((p) => adrNo(p) && mainAdr.has(adrNo(p)) && mainAdr.get(adrNo(p)) !== p);
  if (adrClash.length) why.push('ADR 번호 겹침: ' + adrClash.join(', '));
  const mt = spawnSync('git', ['merge-tree', '--write-tree', 'HEAD', mainRef], { encoding: 'utf8', timeout: 60000 });
  if (mt.error) die('git merge-tree 를 못 돌렸다 — ' + mt.error.message);
  if (mt.status === 1) why.push('글자 충돌');
  else if (mt.status !== 0) die('git merge-tree 오류(종료 ' + mt.status + ') — ' + String(mt.stderr).split('\n')[0]);
  console.log(why.length ? '합치기' : '그대로');
  if (why.length) why.forEach((w) => console.log(w));
  else console.log(`main 이 새로 바꾼 ${mainNew.size}개 파일이 내 변경과 안 겹친다 (충돌 없음)`);
  if (riskNote) console.log(riskNote);
  process.exit(0);
}

if (mode === 'after-merge') {
  const reviewed = arg1;
  const mainRef = arg2 || 'origin/main';
  if (!reviewed || !SHA.test(reviewed)) die('리뷰한 SHA 40자가 필요하다 (짐작해 채우지 말고 rev-parse 출력에서 복사)');
  verify(reviewed) || die(`${reviewed} 커밋을 못 읽었다`);
  verify(mainRef) || die(`${mainRef} 를 못 읽었다`);
  const head = verify('HEAD') || die('HEAD 를 못 읽었다');
  if (head === reviewed.toLowerCase()) {
    console.log('리뷰유효');
    console.log('병합 없음 — HEAD 가 리뷰한 커밋 그대로');
    process.exit(0);
  }
  const anc = spawnSync('git', ['merge-base', '--is-ancestor', reviewed, 'HEAD'], { timeout: 60000 });
  if (anc.error || (anc.status !== 0 && anc.status !== 1)) die('조상 확인 실패');
  if (anc.status === 1) {
    console.log('재리뷰');
    console.log('리뷰한 커밋이 HEAD 의 조상이 아니다 (rebase·되돌림 등으로 이력이 바뀜)');
    process.exit(0);
  }
  const base0 = git('merge-base', reviewed, mainRef).trim() || die('merge-base 없음');
  const mine = names(base0, reviewed); // 리뷰받은 내 변경 파일
  const lastMain = git('merge-base', 'HEAD', mainRef).trim() || die('merge-base 없음'); // 마지막으로 합친 main 지점
  const changed = names(reviewed, 'HEAD'); // 리뷰한 뒤 HEAD 까지 바뀐 파일 전부
  const myTouched = [...changed].filter((p) => mine.has(p));
  // «main 이 바꾼 파일»이라고 통과시키지 않는다 — 합친 main 지점과 HEAD 가 다른 파일은 전부 리뷰받은 내 변경이어야 한다.
  // (병합 커밋에서 손으로 고친 것·병합 뒤 직선 커밋으로 고친 것이 main 이 건드린 파일이어도 여기서 걸린다)
  const extra = [...names(lastMain, 'HEAD')].filter((p) => !mine.has(p));

  // 리뷰받은 내 파일을 main 이 «같은 파일의 다른 곳만» 고쳤으면 리뷰는 아직 유효하다(배포처 bnsone #677 — 매번 손으로 대조해 우회했다).
  // 둘 다 맞을 때만 면제한다: ①HEAD 의 그 파일이 «리뷰한 커밋 + main 의 변경»을 git 이 기계적으로 합친 결과와 바이트까지 같다(손으로 고친 흔적 0)
  //   ②main 이 고친 줄이 내가 고친 줄과 MARGIN 줄 안에 없다(둘 다 합친 기준점 줄번호). 읽을 수 없는 건 전부 «재리뷰» — fail-closed.
  // 한계: 줄이 멀어도 뜻이 이어질 수 있다(함수 이름을 바꾸고 다른 곳의 옛 이름 호출이 늘어남) — 이 판정기는 줄만 본다.
  //   그 길목은 위험 경로·머지 뒤 main 파이프라인이 막는다(위 한계 절).
  const MARGIN = 3;
  // 파일 항목 = «권한 종류 해시» — blob 해시만 비교하면 실행권한(100644↔100755) 변경이 가려진다(독립 검토가 재현).
  const blob = (ref, f) => {
    const r = spawnSync('git', ['ls-tree', ref, '--', f], { encoding: 'utf8', timeout: 60000 });
    const line = r.status === 0 ? String(r.stdout).split('\n')[0].split('\t')[0].trim() : '';
    return line || null;
  };
  const hunkRanges = (a, b, f) => { // a→b 에서 바뀐 구간, a(옛) 쪽 줄번호 [시작,끝] — 줄을 «끼운» 곳은 앞뒤 줄을 모두 덮는다
    // --literal-pathspecs: 파일 이름의 [id]·* 가 글롭으로 읽혀 다른 파일의 줄을 끌어오지 않게(독립 검토가 재현)
    const out = git('--literal-pathspecs', 'diff', '-U0', '--no-renames', a, b, '--', f);
    const rs = [];
    for (const l of out.split('\n')) {
      const m = /^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@/.exec(l);
      if (!m) continue;
      const s = Number(m[1]);
      const n = m[2] === undefined ? 1 : Number(m[2]);
      rs.push(n === 0 ? [s, s + 1] : [s, s + n - 1]);
    }
    return rs;
  };
  const mt = spawnSync('git', ['merge-tree', '--write-tree', reviewed, lastMain], { encoding: 'utf8', timeout: 60000 });
  const treeLine = mt.error ? '' : String(mt.stdout).split('\n')[0].trim();
  const T = (mt.status === 0 || mt.status === 1) && /^[0-9a-f]{40,64}$/.test(treeLine) ? treeLine : '';
  const bl = git('merge-base', reviewed, lastMain).trim() || die('merge-base 없음');
  const whyChanged = (f) => { // null = 면제(리뷰 유효), 문자열 = 재리뷰 사유
    if (!T) return '병합 결과를 만들지 못해 줄 단위 판정 불능';
    const h = blob('HEAD', f);
    if (h === null || blob(T, f) !== h) return '기계적 병합과 다름(손으로 고침·충돌 해결·main 변경 없음)';
    if (blob(bl, f) === null) return '파일이 새로 생김';
    const mi = hunkRanges(bl, reviewed, f);
    const ma = hunkRanges(bl, lastMain, f);
    if (!mi.length || !ma.length) return '바뀐 줄을 못 읽음(바이너리 등)';
    for (const x of mi) for (const y of ma) if (x[0] - MARGIN <= y[1] && y[0] - MARGIN <= x[1]) return `main 이 고친 줄이 내 줄과 ${MARGIN}줄 안`;
    return null;
  };
  const bad = [];
  const apart = [];
  for (const p of myTouched) {
    const r = whyChanged(p);
    if (r) bad.push(`${p} (${r})`);
    else apart.push(p);
  }
  // 반대 방향 구멍: main 이 고친 «리뷰받은 내 파일»을 내 쪽으로 통째로 채택하면(-s ours·--ours 해결·main 이 지운 파일 되살리기)
  //   HEAD 가 리뷰한 커밋과 같아 위 목록(changed)에 안 잡히는데 main 의 변경은 사라진다. 기계적 병합 결과와 다르면 재리뷰.
  const mainTouched = names(bl, lastMain);
  for (const p of mine) {
    if (!mainTouched.has(p) || myTouched.includes(p)) continue;
    // 삭제↔수정 충돌은 병합 결과 트리가 내 쪽 파일을 그대로 담는다 → main 이 지운 파일이 HEAD 에 남았는지를 따로 본다
    if (!T || blob('HEAD', p) !== blob(T, p) || (blob(lastMain, p) === null && blob('HEAD', p) !== null)) bad.push(`${p} (main 의 변경이 버려짐 — 내 쪽만 채택·되살림)`);
  }
  if (!bad.length && !extra.length) {
    console.log('리뷰유효');
    if (apart.length) {
      console.log(`병합이 main 쪽 파일을 바꿨고, 리뷰받은 내 파일 ${apart.length}개는 main 이 고친 곳이 내 줄과 ${MARGIN + 1}줄 이상 떨어져 있고 기계적 병합과 같다: ${apart.slice(0, 8).join(', ')}`);
    } else {
      console.log(`병합이 main 쪽 파일 ${changed.size}개만 바꿨고 리뷰받은 내 파일은 그대로다`);
    }
  } else {
    console.log('재리뷰');
    if (bad.length) console.log('리뷰받은 내 파일이 바뀜: ' + bad.slice(0, 8).join(', '));
    if (extra.length) console.log('리뷰받지 않은 내 변경 — 병합 중·뒤에 손댄 파일: ' + extra.slice(0, 8).join(', '));
  }
  process.exit(0);
}

die('사용: node scripts/done-merge-verdict.cjs main-moved [mainRef] | after-merge <SHA> [mainRef]');
