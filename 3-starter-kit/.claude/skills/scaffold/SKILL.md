---
name: scaffold
model: opus # 조직 allowlist에 없으면 무시되고 세션 모델 유지(공식 fail-soft) — 본문 소프트 플로어가 백스톱
effort: high
description: 프로젝트 앱 뼈대(골격)를 생성한다 — Day 0 기술설계(스택·모듈)를 읽어 src 구조·docker-compose·CI·CLAUDE.md 빈칸까지 채운다. 골격 구축 Day 1에 공통 개발자가 1회.
disable-model-invocation: true
argument-hint: "(인자 없음 — docs/06_TechnicalDesign을 읽는다)"
allowed-tools: Read Glob Grep Edit Write Bash(git *) Bash(npm *) Bash(docker compose *) Bash(glab *)
---

# /scaffold — 앱 뼈대 생성 (골격 Day 1, 프로젝트당 1회)

> **계약** · 입력: 설계(docs/06) · 산출물: 앱 뼈대(src·docker·CI·CLAUDE.md 빈칸·훅) 커밋 · 검증: 새 clone→docker compose up→빈 앱 렌더 (⏸ 게이트)

> **예시**: `/scaffold` (인자 없음 — `docs/06` 설계를 읽는다)

> ★**모델 확인(소프트 플로어)**: 골격은 이후 전부의 토대다 — 현재 세션이 경량 모델(haiku급)이면 **시작 전에 멈추고** "골격 생성은 상위 모델 권장 — `/model`로 올린 뒤 다시 `/scaffold`"를 안내하라. 상위 모델이면 그대로 진행.

> 이건 **공통 개발자 스킬**이다. 개발자의 `/dev`처럼, 공통 개발자의 "앱 뼈대 만들기"를 붙여넣기 프롬프트 대신 이 스킬로 한다.

**전제**: Day 0 기술설계가 끝나 `docs/06_TechnicalDesign/`에 **스택·DB·모듈 분할**이 있고 `docs/adr/`에 핵심 결정이 있다. **없으면 여기서 멈추고 Day 0(설계)부터** 하라 — 감으로 스택을 정하면 뒤에 재작업이 크다.

1. **설계 읽기** — `docs/06_TechnicalDesign/`(스택·ERD·모듈)·`docs/adr/INDEX.md`(결정)를 읽고, **"이 스택·구조로 뼈대를 짠다"를 5줄로** 요약(스택 / DB·마이그레이션 도구 / 모듈 이름들 / 배포 방식 / 범위 밖).
   - **마이그레이션 도구가 설계에 없으면** 기본값(plain-SQL + 자체 러너)을 제안하고 게이트에서 확정한다.
   - **언어가 설계에 없으면 TypeScript를 기본값으로** 제안한다(근거는 /design ② — 타입=AI의 기계 검증 루프). TS면 test 잡에 **typecheck를 반드시 포함**(3단계 ② CI 잡·4단계) — 검사 없는 타입은 이득이 준다.
   - **repo에 기존 src·CI(다른 앱 잔재)가 있으면** 교체/보존 범위도 요약에 넣는다(어느 모듈·파일을 걷어내고 무엇을 새로 짓는지 — 4단계 "주석 스테이지 활성화"는 이미 CI가 켜진 repo엔 해당 없음).
2. **⏸ 게이트**: **위 5줄 요약을 먼저 텍스트로 출력**하라 — 승인 UI(질문 위젯)엔 질문만 크게 보여 본문 요약이 안 보일 수 있으니, **승인 요청 문구에도 요약(축약)을 포함**한다. 사용자가 승인(스택·모듈 이름·교체범위 확정)할 때까지 **코드 생성 금지**.
2-1. **골격 카드 발행** — 게이트 승인 후 `/card`로 골격 카드(제목 예 `앱 골격 생성`, **`고위험` 라벨** — shared 전체를 건드리므로)를 만들고 **그 번호를 커밋(6단계)에 쓴다**.
   - (CLAUDE.md '카드 #1 예외'는 최초 구축 한정 — 이미 보드가 도는 repo엔 이 단계로 카드를 남긴다.)
   - **3단계에서 모듈 플래그를 만들면 그 자리에서 플래그 제거 카드도 함께 발행**한다(CLAUDE.md '플래그 생성 = 제거 카드 동시 발행' 규칙).
3. **뼈대 생성** — ★먼저 **설계에 DB·마이그레이션이 없으면**: 아래 db·migrate·reseed·`db/migrations/`를 생략하고 **CLAUDE.md '스키마·데이터' 절·`/done` 마이그레이션 단계·`rules/migrations.md`를 제거**한다(그 절 주석 지침대로). **비웹 플랫폼**(데스크톱·네이티브)이면 docker-compose·"빈 화면 뜬다" 기준을 그 플랫폼의 기동·실행 방식으로 바꾼다. (아래는 웹+DB 기본형):
   - `src/shared/`(auth·ui·db·nav), `src/modules/{설계의 모듈들}/`(각각 `ui/`·`api/`·`schema`·`seed`·`tests/`·`index`), `db/migrations/`
   - 각 모듈은 **`index`만 외부에 노출** (공개 인터페이스)
   - **docker-compose**: db(헬스체크) → migrate(마이그레이션+시드) → app 순서. **로그인 없이 빈 화면이 뜨게**, 화면 하단에 커밋 해시·배포 시각 푸터.
   - 기능 플래그(flags 파일 + `?preview=플래그명` 미들웨어) · `npm run reseed` — ★플래그는 **배선까지가 산출물**: 미들웨어가 심은 프리뷰 값(쿠키 등)을 **읽어서 `isEnabled` 판정에 넘기는 코드까지** 만들고, 플래그 하나로 실제 on/off가 왕복되는지 확인하라(미들웨어만 만들면 프리뷰가 동작하지 않는 반쪽 산출물 — bnsone 실측 2026-07-29)
     - ★Next 스택이면: 파일명은 **`proxy.ts`**(16에서 `middleware` 개명·폐기예고, 함수명도 `proxy`) · **`src/` 구조면 반드시 src/ 안**(=app과 같은 층 — 공식 규약 "project root, or inside src if applicable"). 루트에 두면 **prod는 돌고 dev만 무음으로 안 도는** 비대칭이 난다(bnsone #54 실측 — 전 라우트 Set-Cookie 0건인데 빌드는 정상).
     - ★프리뷰 판정(쿼리+쿠키 폴백)은 **페이지마다 복사 금지** — shared 헬퍼 1개(`isPreviewEnabled` 류)로 내려 페이지는 한 줄만 부르게 하라(bnsone #51 리뷰 실측 — 4줄이 플래그 페이지마다 복제될 뻔).
   - **시안 열람은 앱이 아니라 시안 허브가 담당** — `docs/05_UIUX/`를 git-sync가 자동 동기해 `<시안허브URL>/{프로젝트}/`로 보여준다(공통 개발자가 인스턴스에 1회 세팅 — `docs/00_Guide/sian-hub-setup.md`).
     - **검수 서버에 별도 `/sian/` 라우트를 만들지 마라** — 허브가 대체하고, 허브는 `docs/`만 보므로 앱 스캐폴드/배포 전에도 시안을 열람할 수 있다. (Pages가 정상인 인스턴스면 CI `pages` 잡이 1순위.)
   - README에 "clone 후 `docker compose up` 한 줄" 온보딩
   - **강제 장치**(Day 4):
     - husky(+`"prepare":"husky"`)
     - `src/shared` 공개 API 스냅샷 테스트
     - **lock 충돌 안전판 = `.gitattributes`에 `package-lock.json merge=binary` 한 줄**:
       - ⚠️**자동 머지 드라이버를 두지 마라** — `npm-merge-driver`(6년 미유지)든 자체 스크립트든, git merge 도중 package.json 해결 *전에* lock을 재생성해 **한쪽 의존성이 조용히 누락된 valid-but-wrong lock**을 만든다〔2026-07-27 파일럿 실측〕.
       - `merge=binary`는 자동머지 대신 **시끄러운 충돌로 강제**해 수동 해결로 유도한다 — 해결은 CLAUDE.md '금지' 절 규칙: package.json만 통합 → `npm install --package-lock-only`
     - Edit/Write 모듈 가드 훅 (package.json이 여기서 생기니 husky도 지금 붙인다 — check-push·settings 훅·security 플러그인은 킷 제공)
   - **화면 하단 버전 표시**(웹 앱이면 필수 관례): `<프로젝트> · <git 해시 7자리> · <기동 시각> 기동`을 전 화면 푸터에 작게 — 검수자가 "내가 보는 게 최신인가"를 판별하는 유일한 수단이다(가이드 §5와 짝). git 정보 없으면 `dev` 폴백(그 자체가 "판별 불가" 신호).
   - **스택에 맞춰 다시 쓸 것 2가지**(킷 제공본은 CommonJS·JS 기준이다):
     - ①**경계검사 스크립트** — 킷 동봉 `scripts/check-boundaries*.cjs`(기본형·Next용 `-next` 변형 — CJS·ESM·TS·별칭 해석 + 순환 + Prisma DB 경계)를 기본으로 쓰되 **상단 값(SCAN_FILES·ALIAS·SCHEMA_DIR·SHARED_DB_ALLOWLIST)을 이 스택으로 치환**한다(회귀 테스트 `test/check-boundaries*.test.js` 동봉).
       **DB부는 Prisma 전용** — 다른 ORM이면 "DB 검사 비활성" 경고가 정상이고 DB 경계는 리뷰 몫이라고 CLAUDE.md에 남긴다(+shared→모듈 역방향 의존 금지)
     - ②**CI 잡** — 타입 검사·빌드가 있는 스택이면 test 잡에 typecheck 추가 + build 잡 신설, `high-risk-gate`의 `changes` 목록에 그 스택의 설정 핫스팟(미들웨어·빌드 설정·compose·Dockerfile·CI 자신)을 더한다.
     - `check-push`는 **파일 경로로만** 감지한다(테이블 이름 패턴은 없다 — 초기 커밋부터 0건, 2026-08-06 실측). 폴더 구조가 킷 기본값과 다를 때만 경로 패턴을 고친다.
   - **시드·리셋**(Day 5): `modules/*/seed.ts`(멱등) · `scripts/reset-review-server.sh`(확인 프롬프트) · `npm run reseed`. (ship은 킷의 `/done` 스킬이 감싸므로 별도 스크립트 불필요)
   - ★**시드를 실제 DB에 붙여 돌리는 테스트도 함께 만든다** — 시드는 파드 기동마다 도는 경로라 **깨지면 앱이 아예 안 뜬다**.
     - 가장 치명적인데 검증이 없다: bnsone 실측 — 시드의 `$queryRawUnsafe`가 P2010으로 죽어 검수 서버 첫 기동 CrashLoopBackOff인데 `npm test`·typecheck·`ci lint`·CI 잡 넷 다 초록이었다. 넷 중 시드를 돌리는 게 하나도 없다.
     - `$queryRaw`↔`$executeRaw` 같은 함정은 스택별이라 규칙으론 못 막고 테스트만 잡는다.
     - 실행법은 스택마다 다르니 "이 스택에서 어떻게 할지 적고 만들라":
     ① 마이그레이션→시드 순서로 **실제 DB에 실행**  ② **두 번 연속 돌려 결과가 같은지**(멱등성 실증 — 지금은 주석으로만 "멱등")  ③ 고의로 깨뜨리면 빨간불이 되는지
4. **CI 활성화** — `.gitlab-ci.yml`의 주석 처리된 **`test`·`boundaries` 스테이지를 이 스택 명령으로 채워 활성화** (`<스택이미지>`·`<테스트명령>`·`<경계검사명령>` — 경계검사 기본은 `node scripts/check-boundaries.cjs`) + **`high-risk-gate`의 `changes:`에 이 스택의 인증·라우팅·설정 경로를 추가**(스택별 고위험 경로를 넓혀야 그 카드도 승인 게이트를 탄다).
   **`migration-immutable`의 `DIR`·`high-risk-gate`의 마이그레이션 경로도 이 스택 값으로 치환**(Prisma 폴더형이면 `prisma/schema/migrations`). 고치면 `glab ci lint`로 문법 검증.
   ★**`needs`를 쓰면 가리키는 잡과 `rules`를 맞춰라** — 한쪽만 `changes:`로 빠지면 그 커밋에서 **파이프라인 생성이 거부**되어 잡 0개(전 게이트 무효)가 된다. 원칙: 같은 `changes:`를 공유(앵커)하거나, 산출물을 안 쓰는 경우에만 `optional: true`. `ci lint`·dry_run 다 통과하니 문법 검증으론 안 잡힌다 — **배포 잡을 만들 땐 `_reference/ci-needs.md`를 읽어라.**
   ★**자기 검증 대조표(필수 — 지시만 있고 이행이 새는 게 실측됐다)**:
     - CLAUDE.md '머지 등급'의 고위험 유형 **각각**(인증·결제·마이그레이션·shared 승격·라우팅·설정·lockfile)에 대해 **이 스택에서의 실제 경로를 적고**, `high-risk-gate`의 `changes:`와 `tamper-check` 조건에 반영됐는지 **항목별로 대조해 보고**한다.
     - 대응 경로가 없으면 **"없음"이라고 명시**(빈칸 금지).
     - `tamper-check`의 소스 감지(`^src/` 등)에 스택 가정이 박혀 있지 않은지도 함께 — 예시 두 경우:
       - **라우팅이 `src/app/**`인 스택**(Next.js)이면 `src/app/**/page.*`·`route.*`·`layout.*`·`proxy.*`(구 `middleware.*`)를 `changes:`에 추가
       - **라우팅이 루트 파일인 스택**(단일 `server.js`)이면 그 루트 파일 자체를 추가하고 tamper의 `^src/`도 `^src/|^server\.` 처럼 넓힌다(bnsone은 라우팅 경로 누락·파일럿은 루트 파일 누락으로 고위험 3카드가 게이트 없이 수동 우회 — 2026-07-29 실측).
5. **CLAUDE.md 빈칸 채우기** — 이 스택으로 결정되는 플레이스홀더 채움(`<기동명령>` 등, '실행·테스트' 절). 
   — **+ check-push의 경로 패턴을 이 스택에 맞춘다**: 마이그레이션 폴더가 `db/migrations/`가 아니면(Prisma는 `prisma/`) 그 경로로 바꾸고, **CI `high-risk-gate`의 `changes:` 목록과 같게 맞춰라**(훅=로컬 앞단, CI=백스톱 — 어긋나면 한쪽만 뜬다).
   (`<검수서버URL>`·`<본보기모듈>`·소유표는 인프라·Day 6·합류 후 — `/setup-gitlab`·`/assign-module`이 채운다.)
6. **커밋** (첫 줄 `#<카드> chore: 앱 골격`, 카드 = 2-1 발행분) — **새 clone 검증(7)은 커밋된 상태만 보므로 커밋이 먼저다**(순서 뒤집지 말 것).
   - ⚠️ Day 1 골격 커밋은 공통 영역(shared·CI·CLAUDE.md) 전부를 건드리지만 `<팀채팅주소>`가 아직 비어 채팅 공지를 할 수 없다 — **이 최초 골격 커밋만은 카드 번호로 공지를 갈음한다**(예외; Day 2 `/setup-gitlab`에서 채팅주소가 채워지면 이후 공통 변경은 정상 공지).
7. **✅ 눈으로 확인** — **다른 폴더에 새로 clone → `docker compose up` → 브라우저에 빈 앱이 뜨는지.** 안 뜨면 여기서 고쳐 **수정 커밋을 추가**한다(뜨는 게 완료 기준).
   - **+ 남은 `<…>` 플레이스홀더를 grep으로 훑어** 무엇이·누가·언제 채우는지 보고 — 특히 `<본보기모듈>`은 여러 파일·스킬에 있어 Day 6에 일괄 치환(그때까지 dev·ui가 리터럴 `<본보기모듈>`을 읽지 않게 주의).
   - → **"▶ 다음: `/setup-gitlab` (Day 2)"** 안내.

## ❌ 금지 — 핑계와 반박
| 핑계 | 반박 |
| --- | --- |
| "설계 문서 없지만 스택은 대충 알아" | 감 스택 = 뒤에서 전면 재작업. Day 0부터. |
| "코드는 짰으니 됐다" | 브라우저에 실제로 뜨기 전엔 완료 아님(2번 게이트·7번 확인) |
| "모듈 이름은 내가 정하지 뭐" | 모듈 경계는 설계(요구 근거) 산출물이다 — 임의로 만들지 마라 |
