# 프레임워크 설계 결정 로그 (framework-level DDR)

> **무엇**: 프레임워크(킷·스킬·구조) 자체에 대한 설계 결정과 그 근거. **프로젝트 ADR(`docs/adr/`)과 구별** — 저건 OfficeOne 앱의 결정(PWA·PostgreSQL 등), 이건 "프레임워크를 이렇게 만든다"의 결정.
> **왜 있나**: "이거 왜 이렇게 했지 / 이거 추가할까?"를 다시 물을 때 재논쟁 대신 참조. 뒤집으려면 여기 새 항목으로 대체(옛 항목엔 "대체됨" 표시).
> **읽는 사람**: 프레임워크를 고치는 사람(공통 개발자·유지보수자). 일상 개발자는 볼 필요 없음.

---

## DD-01 — 개발환경 세팅은 새 스킬을 만들지 않는다 (`/scaffold`·`/start`가 담당) · 2026-07-22

**결정**: "정해진 스택으로 개발환경 세팅을 돕는" 별도 스킬(`/setup` 등)을 **만들지 않는다.** 세팅은 ①`/scaffold`가 스택 확정 후 **실행 파일로 생성**(README `docker compose up` 온보딩·`npm run reseed`·리셋 스크립트·CLAUDE.md `<기동명령>` 치환)하고, ②반복 마찰이 실증되면 **기존 `/start`에 가벼운 환경 자가진단**(CLAUDE.md `기동명령`을 읽어 "의존성/DB 미준비 → 무엇 먼저"를 짚기)을 더한다.

**이유**:
1. **가장 중요한 세팅은 claude 밖**이다 — `CLAUDE_CODE_GIT_BASH_PATH`(bash 훅 전제)는 claude가 돌기 *전에* 있어야 하는데 스킬은 claude *안*에서 돈다. 스택이 뭐로 정해지든 이 한계는 불변.
2. **스킬 축적은 명시된 반패턴** — CLAUDE.md("추가 1건당 삭제 후보 1건")·`agent-skills-analysis`·`ecosystem-analysis`가 일관되게 경계. "나중에 필요할지도"로 스킬을 늘리지 않는다.
3. **세팅은 이미 두 곳에 녹아 있다** — `/scaffold`가 진입점(README·스크립트)을 만들고, ONBOARDING이 유일한 비자명 단계(환경변수)를 안내. "문서는 구현되면 실행 파일로 은퇴"라는 프레임워크 철학과 일치.

**근거**: `ecosystem-analysis.md`(환경변수만 ONBOARDING에 반영, 스크립트 아님 / 내장 `/team-onboarding`=문서 생성기), `claude-code-docs-analysis.md`("단일 repo 팀 = `.claude/` 직접 커밋이 공식 정답"), README("끝까지 사람이 읽는 건 README+GitLab 가이드뿐").

**적용**: 2026-07-22 리허설 중 만들었던 킷 `scripts/setup.ps1`·`setup.cmd`는 **철회**(킷은 스택 무관 템플릿인데 `npm install`을 박아 원칙 위반 — 사용자 지적). ONBOARDING 딸깍 문구도 되돌림.

**뒤집힐 조건**: 팀이 실제 온보딩할 때 세팅 마찰이 반복 실증되면 → 먼저 `/start` 자가진단 한 줄, 그보다 큰 마찰이면 devcontainer(스택 확정 후). 그때도 "새 스킬"이 아니라 이 순서로.

---

## DD-02 — 권한·규칙은 커밋된 파일로 배포한다 (AI는 settings.json을 못 고침) · 2026-07-22

**결정**: 팀 권한(`.claude/settings.json`)·규칙(`.claude/rules`)·스킬은 **repo에 커밋** → 팀원은 **clone만으로 자동 적용**(각자 설정할 것 0). 권한 변경은 **사람(유지보수자)의 1회 편집**이고, 그 뒤 clone으로 전파된다.

**이유**: **AI는 settings.json을 편집·복사·커밋할 수 없다** — 자기 권한 상승 방지 하드 경계(2026-07-22 세션에서 편집·`cp`·커밋 3방향 전부 차단 실측). 따라서 "권한을 자동으로 맞춰주는 AI 자동화"는 원천 불가. 대신 커밋된 파일이 clone으로 전파되는 구조가 정답.

**함의(운영)**:
- 권한 규칙 추가는 **사람이** `/permissions` 또는 파일 편집으로. 한 번 커밋하면 이후 전원 자동.
- 리허설에서 AI가 권한을 못 넣어 "사용자 1회 실행 스크립트"로 우회한 이력 있음(node --test·curl·git 조회 반영) — 이건 사용자가 실행한 것이지 AI가 한 게 아님(경계 존중).

**근거**: `claude-code-docs-analysis.md`("단일 repo 팀 = `.claude/` 직접 커밋이 공식 정답"), 2026-07-22 실측.

---

## DD-03 — 프레임워크 검증은 파일럿에서 "실제 역할·권한 계정"으로 한다 (bnsone 전) · 2026-07-22

**결정**: 프레임워크 변경·새 문서(요구사항 등)는 **bnsone에 닿기 전 파일럿에서 먼저 리허설**한다. 그리고 리허설은 **실제 팀 구조와 같은 역할·권한 계정**으로 돈다 — 기획(Maintainer)·개발(Developer)·공통 개발자(Owner)를 각각의 권한으로.

**이유**: 2026-07-22 멀티세션 리허설에서 실증 — **모든 걸 Owner(yskim) 하나로만 테스트하면 권한 구멍이 안 보인다.** 파일럿 main 보호가 `merge=Maintainers`였는데 실개발자는 Developer라, 그대로 bnsone을 잠그면 개발자가 셀프 머지를 못 한다. 이건 Developer 계정으로 한 번만 돌려봤으면 즉시 걸릴 것을, Owner-only 테스트가 가려온 것. **역할·권한까지 실제와 같게 맞춰야 이음매 버그가 잡힌다.**

**방법(실증된 절차)**:
1. 파일럿에 가상 역할 계정 생성(admin API, 이메일 `<owner>-<계정>@사내도메인` + `skip_confirmation`) — 기획·개발 각 권한으로 프로젝트 멤버 추가, 개발 계정엔 PAT 발급.
2. 새 문서(bnsone STEP 문서)가 오면 파일럿으로 미러 → `/docs`(digest·지도) → `/design`·`/card`·`/ui`·`/scaffold`가 그 문서를 매끄럽게 소화하는지 → 구멍 발견 → 킷 정본 수정 → 3배포본 동기 → 그 다음 bnsone 적용.
3. 리허설 전 **파일럿을 최신 킷과 동기 확인**(안 하면 낡은 프레임워크를 시험).
4. **질문 주도 검증 포함(2026-07-23 편입)**: 페르소나(기획·개발·검수·공통 개발자)별로 "실사용자가 물을 질문"을 생성해 **가이드·스킬만으로 답이 되는지** 검사 — 렌즈 스윕은 "있는 문장"만 보고 "없는 답"은 못 잡는다. 1차 실행(57문·43답·갭 14건)으로 실증됨. 특히 곤란 경로(사고·거절·부재·책임)가 얇게 남는 경향.

**적용**: bnsone `main` 보호는 **Allowed to merge = Developer 이상**(HANDOFF §3·Leader Day 2). 파일럿 5역할 계정(planner·designer·dev1·dev2·yskim)은 앞으로의 문서 리허설 재사용 위해 유지.

★**리허설이 덮는 범위와 못 덮는 범위(2026-08-26 실측)** — "파일럿 초록"을 과신하지 않기 위한 경계선.
- **덮는다(스택 동일)**: 파일럿도 bnsone과 같은 Next.js(App Router)+Prisma+vitest+docker-compose이고, 경계검사기도 같은 Next판이다(파일 이름만 달랐다가 2026-08-26 통일). CI 게이트 공통 11종(test·boundaries·tamper-check·density-check·secret-scan·filename-nfc·high-risk 2종·migration-immutable·planner-guard·deploy-review)도 양쪽에 있다 → **스킬·절차·게이트·경계 규칙 변경은 파일럿 리허설이 유효하다**.
- **못 덮는다(배포층 부재)**: 파일럿엔 `k8s/`(app·postgres·configmap·secret·ci-rbac·cronjob 2종)도, `service-deploy`·`docker-build`·`seed-int` 잡도 없다. 사내 클러스터가 필요해 구조적으로 못 만든다 → **배포·인프라·권한(rbac)·정기작업·시드 통합 변경은 파일럿에서 리허설되지 않는다.** 이 층의 정기 점검은 `/overhaul` **배포 갈래**(대조 6쌍)가 맡고, 실검증은 bnsone에서만 가능하다. 그런 변경을 동기할 땐 보고에 **"배포층 미검증"**을 명시하라.

**뒤집힐 조건**: 없음(검증 방법론). 다만 가상 계정 대신 실팀 계정을 쓰는 건 **팀 착수 후에만**(그 전엔 실 알림 발송 위험 — 메모리 `no-team-notifications-before-launch`).

---

## DD-04 — 바깥 산출물은 "남기기 전 미리보기 → 사용자 OK" (전 스킬 공통) · 2026-07-23

**결정**: GitLab·repo에 남는 모든 산출물(카드 등록·댓글·멘션·라벨·MR 생성·auto-merge·머지·docs 배치·ADR·시안 발행)은 **만들기 직전 "무엇을 어디에 남길지" 요약을 보여주고 사용자 OK 후에만 실행**한다. 규칙 정본 = **CLAUDE.md '작업 절차' 절의 공통 규칙 1줄**(개별 스킬에 중복 기술하지 않음 — 단 문구가 모순되던 `/card`는 교체, 최다 빈도인 `/done`·`/ui`엔 포인터 1줄).

**이유**: 사용자(리더) 지시 — "모든 스킬이, 사람이 이 프로젝트가 어떻게 진행되는지 자연스럽게 알 수 있게끔". 목적은 **통제가 아니라 가시성·학습** — 확인하는 순간마다 팀원이 프레임워크 동작을 익힌다. 마찰 증가(카드당 확인 3~5회)는 선택지로 명시 제시했고 사용자가 인지하고 채택("모든 바깥 산출물" > "AI 재량 산출물만").

**예외(확인 불요)**: 조회·읽기·테스트 실행 · 작업 브랜치의 커밋·push(/dev·/fix의 계획 승인에 이미 포함된 실행). 동종 배치(분해 카드 등)는 1회 확인.

**조건부 기록(7-23 추가)**: 미리보기에서 사용자가 **산출물의 방향을 바꾸는 수정**을 시키면 그 요지를 관련 카드 댓글 한 줄로 남긴다 — 바꾼 '이유'가 채팅과 함께 휘발되는 갭을 막는다. 소소한 문구 손질은 제외(전부 댓글화하면 카드가 노이즈로 비대해짐 — 조건부인 이유).

**정밀화(7-23 미니 리허설 경계 발견 2건 → 문구 반영)**: ①**선택지 게이트가 등록 승인을 겸할 땐 핵심 필드를 접지 말고 본문에 펼친다** — 실측: 범위 선택 다이얼로그의 미리보기가 14줄 접힌 채 선택=승인으로 등록 직행 ②**배치 1회 확인의 범위 = 승인받은 계획에 명시된 산출물까지** — 실측: /change 계획 승인 1회가 카드 3건 조작+docs MR+auto-merge를 커버(합리적이나 경계를 명문화). ※같은 리허설에서 관찰된 effort=xhigh는 **사용자 전역 설정으로 확인**(프레임워크 무관 — 스킬 effort 핀은 DD-05대로 design·scaffold뿐).

**뒤집힐 조건**: 팀 숙련 후 확인 마찰이 실증되면(회고·/metrics) "AI 재량 산출물만"으로 완화 — CLAUDE.md 규칙 1줄만 고치면 되도록 규칙을 한 곳에 뒀다.

**미검증**: 스킬이 행동으로 이 규칙을 지키는지 = STEP 3 리허설 때 실세션 검증 예약(HANDOFF 🎯 1).

---

## DD-05 — 스킬별 model·effort: 상향 2개만, 하향은 실증 후 · 2026-07-23
> ⚠️**대체됨(2026-08-08 · 2026-09-08)** — 아래 «model 핀 금지»는 더 이상 사실이 아니다: 08-08 에 fail-soft 확인 후 `design`·`scaffold` 에 `model: opus` 를 박았고, 09-08 오너 결정으로 effort 핀이 9개(overhaul·design·scaffold=max / dev·fix·done·adr·change·ui=xhigh)로 늘었다. **현재 배정표 정본 = `3-starter-kit/_reference/skill-tiers.md`.** 아래 본문은 당시 판단 근거로 보존한다.

**결정**: `/design` = `effort: xhigh` · `/scaffold` = `effort: high`만 킷에 박는다(저빈도·고파급 — 상향은 부작용 없음. design이 xhigh인 이유 = 가장 파급 큰 결정·프로젝트당 1~3회, max는 게이트 대화가 느려져 기각). **model 핀은 어떤 스킬에도 박지 않는다** — `model:` 필드는 "최소"가 아니라 "고정"이라 sonnet을 박으면 상위 모델 사용자가 끌려 내려오고, opus를 박으면 요금제(Pro 등)에서 미보장. 대신 **소프트 플로어**: 두 스킬 지시문에 "세션이 경량 모델(haiku급)이면 시작 전 멈추고 `/model` 상향 안내" 1줄(강제가 아니라 게이트 — 프레임워크 방식과 일치).

**하향 후보(팀 착수 후 `/metrics`로 비용·속도 병목이 실증되면)**: `/log`·`/assign-module`=low, `/setup-gitlab`=medium. **하향 금지**: `/card`·`/todo` — 싸 보여도 판단 스킬(고위험 판정·재개 마커 스캔), 내리면 조용한 사고. 상향 후보: `/change`=high(영향 분석). 나머지는 상속(세션 설정).

**근거**: effort·model은 SKILL.md frontmatter 공식 지원(스킬 활성 턴에만 적용 후 세션 복귀 — 2026-07-23 공식 문서 확인). 실증 없는 최적화는 안 한다(DD-01 정신).

**뒤집힐 조건**: `/metrics` 실증 → 하향 후보표 적용. 팀 요금제 통일 확인 → model 핀 재검토.

**개정 2026-09-08(오너 결정)**: 「상향 2개만」을 버리고 **판단이 무거운 스킬 9개 전부에 effort 핀**을 박는다 — `max`: overhaul·design·scaffold / `xhigh`: dev·fix·done·adr·change·ui. **AI 는 effort 를 판정하지 않는다**(같은 날 아침 핀을 빼고 산문 판정으로 옮겼다가 헛정지 1회, 그리고 `/done` 리뷰 수준이 AI 판정에 맡겨진 채 실호출 70건 중 40건이 low·medium 이었던 실측). design 의 「max 는 게이트 대화가 느려져 기각」은 「전체를 재설계하는 스킬에 xhigh 는 낮다」로 뒤집힘. 근거 문서: platform.claude.com effort 가이드(Opus 5: high→xhigh→max) · code.claude.com skills frontmatter(`effort` 값 `low`~`max`, override). 경위 = `3-starter-kit/_reference/skill-tiers.md`.

---

## 함정·교훈 (프레임워크 기여자용)

### G-12 — 인자 없이 스킬을 부르면 `$0`이 **셸 이름**으로 확장돼 조회가 조용히 깨진다 · 2026-08-04
파일럿 개발자(jiyeon0426) 제보(#91) → 킷에서 재현·수리. `/fix`를 번호 없이 부르면 자동 조회가 `Invalid issue format: "/bin/zsh"`로 깨진다. **공식 문서 확인**: `$N`은 `$ARGUMENTS[N]`의 축약이고, **"인자가 없는 위치 플레이스홀더는 내용에 그대로 남는다"**(stays in the content unchanged). 그래서 `!`glab issue view $0`` 안의 `$0`이 리터럴로 남고 **bash/zsh가 자기 이름으로 확장**한다. **진짜 위험은 조회 실패가 아니라 그다음**: 스킬이 이슈 본문·댓글을 하나도 못 읽은 채 본문 절차로 진입하고, AI가 **번호를 문맥으로 추측**한다(실측: 직전 대화의 카드 번호로 추정해 착수). 맞으면 티가 안 나고 틀리면 **엉뚱한 카드의 브랜치·커밋** — 특히 `/done`은 머지까지 하므로 남의 MR이 머지된다. **처방**: bash 주입을 숫자 가드로 감싼다 — `case "$0" in ''|*[!0-9]*) echo "⛔ …";; *) glab issue view "$0" …;; esac`. 이 한 줄이 **세 경우를 다 잡는다**(정상 번호=실행 / 인자 없음=셸이름은 비숫자라 ⛔ / 숫자 아닌 인자=⛔). bash·zsh 양쪽 실측. **명명 인자(`arguments:` 프론트매터 + `$name`)는 빈 문자열로 확장**돼 더 깔끔하지만 **채택하지 않았다** — 팀원 Claude Code 버전이 제각각일 수 있는데 그 필드를 모르는 버전에서는 `$name`이 리터럴로 남아 더 나빠진다. 숫자 가드는 **버전 무관**이다. bash 주입이 없는 스킬(`/done`·`/inspect`)은 제목의 `#$0`이 숫자가 아니면 멈추라는 한 줄로 대신했다. **적용**: `dev`·`fix`(가드) · `done`·`inspect`(정지 지시) — 3배포처 동기.

### G-11 — `needs`가 `changes:`로 빠지는 잡을 가리키면 파이프라인이 통째로 안 만들어진다 · 2026-08-03
bnsone 실사고: 코드 경로를 안 건드린 main 푸시 **8회 전부 잡 0개**(#2786·#2797~2803)(`secret-scan`·`planner-guard`·`tamper-check`·`density-check` 전부 미실행). 원인 = `service-deploy`(rules에 `changes` 없음 → 항상 포함)가 `docker-build`(`changes` 있음 → 문서만 바뀌면 제외)를 `needs`로 가리킴. GitLab은 그 잡만 빼는 게 아니라 **파이프라인 생성 자체를 거부**한다. **가장 아픈 점**: `planner-guard`는 기획자 docs 직접 push(ADR-0001, 길 A)를 감시하려고 만든 잡인데 **정확히 그 상황에서만 100% 꺼졌다** — 안전망이 필요한 순간에만 꺼지는 유형. **정적 검사 원리상 무력(실측)**: `glab ci lint`·`POST /ci/lint?dry_run=true` 둘 다 `valid` — **비교할 diff가 없으면 `changes:`를 참으로 계산**해 needs가 충족돼 보인다. #79로 넣은 `glab ci lint` 단계로는 이 유형이 안 걸린다. **★파생 함정: 새 브랜치 첫 푸시도 같은 이유로 항상 초록** → "배포 설정을 새 브랜치에서 검증 → 초록 → main 머지 → 그다음 문서 푸시부터 터짐"(7-31 검수 서버 세팅이 이 경로를 그대로 밟음). **"브랜치에서 초록이었다"는 안전의 근거가 안 된다.** **처방(순서 있음)**: ①**두 잡의 `rules`를 맞춘다**(같은 `changes:`를 앵커로 공유) ②`optional: true`는 **산출물을 안 쓸 때만** — 배포 잡이 빌드 이미지를 쓰는데 optional로 두면 **눌러봤자 반드시 실패하는 버튼**이 남는다(없는 태그 → rollout 타임아웃까지 대기 후 빨간불). ※당초 "조용한 ImagePullBackOff가 된다"고 적었으나 **오류** — `rollout status --timeout`이 붙어 있으면 빨간불로 끝나고 `maxUnavailable: 0`이면 서비스도 안 끊긴다(2026-08-03 fresh 리뷰 정정). 단 `rollout status` 없이 `set image`만 하는 배포 잡은 진짜로 조용히 깨진다. **★기계 검사는 시도했다가 철회(같은 날)**: `check-ci-needs.py`+CI 잡을 만들었으나 fresh-context 리뷰가 블로커 4건 — `extends` 상속 needs를 못 봄(잡아야 할 그 모양) · 양쪽 changes 경로가 다르거나 "MR엔 changes·main엔 무조건"인 형태를 못 봄(이 킷이 도처에 쓰는 모양) · 부모/자식 파이프라인 needs를 오판해 영구 빨간불 · `include:` 분할 프로젝트 전부 거짓 경보. GitLab 문법이 넓어 "빠질 수 있나"의 정적 판정은 예외가 계속 나온다 — **잘못 짠 검사기는 없는 것보다 나쁘다**(거짓 경보로 CI를 막거나 통과 도장으로 안심시킨다). 규칙 문서(`_reference/ci-needs.md`)로만 남긴다. ※**부수 교훈**: 자체 검증 "6/6 통과"로 보고했으나 그 6가지는 **만든 사람이 상상한 6가지**였다 — 자기 물건의 자기 검증은 커버리지 근거가 못 된다. CLAUDE.md 셀프 승인 증적 3종(fresh-context 리뷰)이 실제로 나쁜 변경을 막은 첫 사례. **DD-03 우회가 원인**: 검수 서버 배포 잡은 파일럿·킷을 거치지 않고 bnsone에 바로 들어가 파일럿이 잡을 기회가 없었다. 재현은 파일럿 #90(푸시 3회). **킷에 배포 잡 자체는 안 올린다** — Harbor·사내 도메인·k8s 네임스페이스가 박혀 있어 `3-starter-kit` 사내정보 0건(공개 가능) 성질이 깨진다. 배포 레시피는 `review-server-setup.md`가 정본. 상세: `3-starter-kit/_reference/ci-needs.md`

### G-10 — 킷 마이그레이션 규칙은 plain-SQL 전제 → Prisma엔 tool-aware 패스 필요(핀 후 검증, 지금 처방 금지) · 2026-07-27
bnsone 스택이 **Next.js + Prisma**로 확정(ADR-0003)됐는데, 킷 `CLAUDE.md 스키마·데이터` 절·`rules/migrations.md`는 **plain-SQL + 자체 러너** 전제다("날짜시각 파일명·down 대신 새 마이그레이션·내 마이그레이션을 최신 뒤로 재생성"). **웹 확인(2026-07-27) 결과 Prisma는 메커닉이 다르다**: 두 브랜치가 각자 마이그레이션을 만들어 머지하면 `_prisma_migrations` 테이블 ↔ 폴더 불일치를 감지해 **dev DB 리셋을 요구**(파일 재이름이 아님) — 해결은 `prisma migrate resolve`/재생성 워크플로. 즉 킷의 "SQL 파일 재생성" 레시피가 Prisma엔 **불완전/오도**할 수 있다(merge-driver와 같은 부류의 blind-prescription 위험).
**파일럿 scaffold-ahead 실측(2026-07-27, 리더 "파일럿은 미리 검증하는 곳" 지적 반영)**: Prisma+SQLite 미니 fixture로 직접 돌려 **Prisma 7.x의 breaking change를 발견** — ①**`datasource.url`을 스키마 파일에서 제거**(P1012 에러: "url is no longer supported in schema files") → 연결 설정을 `prisma.config.ts` + **드라이버 어댑터**로 옮겨야 함(6.x와 완전히 다른 셋업) ②`--skip-generate` 등 CLI 플래그 제거·스키마 자동탐색 안 함(--schema 필수) ③다중파일 스키마 깨짐(#28673). **의미**: bnsone이 **Prisma 6 패턴을 가정하고 scaffold하면 셋업 단계에서 깨진다** — 킷 scaffold 스킬이 url-in-schema식 Prisma 6 골격을 생성하면 7.x에서 실패. 이건 마이그레이션 충돌 이전의 더 앞단 리스크. (Docker 불필요 — SQLite로 CLI레벨 확인 가능했음. 앞선 "타임아웃"은 pglite 번들 npm 설치였음, hang 아님.)
**끝까지 실측 완료(2026-07-27, 리더 "밀어붙여")**: Prisma 7 정식 셋업(`prisma.config.ts`+어댑터+.env, 웹으로 형식 확인)으로 SQLite fixture 구축 → base 마이그레이션 성공 → 두 브랜치(dev1 attendance·dev2 approval) 동시 마이그레이션 → git 머지. **3대 발견**:
1. **★AI 차단(Prisma 7 신기능)** — `migrate reset`(드리프트 해결에 필요)을 실행하면 Prisma가 **"invoked by Claude Code … As an AI agent you are forbidden from performing this action without explicit user consent"**로 **거부**한다. 즉 팀 개발에서 반드시 생기는 드리프트 해결(파괴적 리셋)을 **AI가 못 하고 사람이 해야 한다**. → 프레임워크 철학(파괴적=사람)과 **일치**하지만, 킷 마이그레이션 스킬·규칙이 이걸 명시 안 해 bnsone AI가 예기치 않게 막힌다. (이 차단이 내 npx 시도의 exit 130/1의 정체 — 내 실수 아님.)
2. **schema.prisma = 공유파일 충돌** — 두 개발자가 각자 모델 추가 시 **git 충돌**(package-lock과 같은 부류, 킷은 이 충돌면을 언급 안 함). 해결 = 양쪽 모델 union + 재생성.
3. **마이그레이션 폴더 = 가산적, 충돌 없음** — 날짜시각 별도 디렉터리라 서로 안 부딪힘(킷 "머지된 마이그레이션 불변" 규칙과 정합 ✓). package-lock과 **다른** 좋은 점.
**킷 시사 — 버전 무관/의존 구분(리더 지적 "스키마 충돌은 어느 버전이든")**:
- ✅ **버전 무관 = 지금 킷 반영 완료(2026-07-27)**: ①마이그레이션 *파일* 불변·가산 = 킷 규칙 유효(무변경) ②**선언형 스키마 파일(schema.prisma 등)이 공유 충돌 자산** = CLAUDE.md 스키마 절에 규칙 1줄 추가(union+검증·모듈별 분리·리셋은 사람) — bnsone #14·MR !25, 파일럿 #59·MR !76, 3배포처 동일.
  - **★실제 워커 세션으로 end-to-end 검증(2026-07-27, 리더 "헤드리스는 못 잡는 게 많아 실제처럼 해봐")**: 파일럿 버림 워크트리에 Prisma 얹고 devA(attendance)·devB(approval) 진짜 충돌 상태를 만든 뒤 **실제 Claude 워커 세션**이 devB로 해결. **헤드리스가 못 보는 AI 행동 전부 통과**: union 해결(양쪽 모델 유지)·`prisma validate` 통과·**AI 차단 규칙을 스스로 소환**("리셋은 규칙상 사람이 하는 파괴적 작업")하고 이 경우 해당 없음을 정확히 판단해 forward-only `migrate deploy` 선택·마이그레이션 타임스탬프 순서 규칙 인지(재생성 불필요)·미리보기 게이트·전용 카드 규칙(번호 안 지어내고 물음)·스테이징 잔재(merge.out)까지 스스로 정리. 결과 `migrate status` = "up to date"(드리프트 0·3테이블). → **규칙 + AI 행동 모두 검증**(지난 턴의 "충돌 발생만 봄"은 반쪽이었다 — 리더 지적으로 완성). **★드리프트 시나리오도 완주(2026-07-27, 리더 "반쪽 말고 다 해봐 — 여러 상황 강제해봐야 실제 마찰 없다")**: 두 하위 시나리오 실측 —
  - **① 순서 꼬임(흔한 팀 케이스)**: devA(예전 ts)가 devB(늦은 ts, 이미 자기 dev.db 적용) 뒤에 머지 → attendance가 "미적용 pending". **Prisma는 이걸 드리프트 아닌 단순 pending으로 봄** → `migrate deploy`(AI 허용·비파괴 정방향)로 해결, **AI차단 안 건드림**(앞 워커가 실제로 이 경로 선택). = 흔한 케이스는 마찰 없음.
  - **② 진짜 드리프트(수동 DB 변경/적용된 마이그레이션 변경 = 규칙위반 사후)**: dev.db에 마이그레이션에 없는 테이블(StrayTable) 직접 삽입 → `migrate dev`가 **드리프트 정확 감지, 자동으로 안 밀고 멈춤**("We need to reset … All data will be lost" 경고만, exit 130) → 그 복구인 `migrate reset`은 **AI 차단**(사람만). = **이중 안전장치**(조용한 손실 없음 + 파괴적 복구 사람 전용). 프레임워크 "위험한 건 사람" 철학을 Prisma 7이 기계적으로 강제 = 내가 넣은 "리셋은 사람이" 규칙이 실측으로 맞음.
  **종합 결론**: Prisma 팀-마이그레이션은 (a)스키마 파일 충돌=union+validate(워커 실증) (b)순서 꼬임=deploy 정방향(마찰 없음) (c)진짜 드리프트=migrate dev 안전 정지+reset은 사람. 셋 다 실측·안전 확인.

**★Prisma 6.x 실측(2026-07-27, 리더 "6.x로 한 번 더" — 6.x가 유력 핀이라 대표성 있음, 추측 아님)**: Prisma **6.19.3**로 검증 —
  1. **다중파일 스키마 작동 ✅**: `prisma/schema/` 폴더(main+모듈별 .prisma)를 `package.json`의 `prisma.schema="prisma/schema"`로 가리키면 migrate가 **전 파일의 모델을 다 컴파일**(init 마이그레이션에 People+Attendance 둘 다). 7.x에서 깨진(#28673) 바로 그 기능이 **6.x는 됨** — 문서 주장 실측 확인. (실무 디테일: 폴더 스키마면 마이그레이션이 `prisma/schema/migrations/`에 생김, 단일파일 기본값 `prisma/migrations/`와 다름.)
  2. **다중파일 = 스키마 충돌 소멸 ✅**: 두 개발자가 **각자 다른 모듈 파일**(devA→attendance.prisma·devB→새 approval.prisma) 편집 후 머지 → **충돌 0건**. 단일 schema.prisma면 충돌났던 게(위 워커 실증) 모듈별 파일로 나누니 안 부딪힘. = **프레임워크 모듈 소유 모델의 정확한 DB층 실현** → 6.x + 다중파일이 이 프레임워크에 최적.
  3. **★AI 차단은 6.x에도 있음 — 내 앞선 주장 정정**: 6-vs-7 트레이드오프에 "6.x엔 AI차단 없음"이라 적었으나 **틀림**. 6.19.3도 `migrate reset`을 "invoked by Claude Code … forbidden"으로 차단(7.9와 동일). 즉 **파괴적 작업 AI차단은 버전 무관**(6-vs-7 차별점 아님). 탈출구 = `PRISMA_USER_CONSENT_FOR_DANGEROUS_AI_ACTION` env에 사용자 동의 원문. → 프레임워크 "리셋은 사람" 규칙이 **어느 버전이든 기계적으로 강제됨**(좋은 소식).
  **정정된 6-vs-7 결론**: 다중파일(모듈 소유)이 6.x만 되고 실측 확인 + 충돌 소멸까지 실증 + AI차단은 양쪽 다 = **bnsone은 6.x(현재 6.19.3)가 명확히 유리**. 남은 ⏳ = 없음에 가까움(핀만 하면 됨). ※테스트가 내 blind claim(6.x AI차단 없음)을 잡은 사례 — DD-03 재확인.
- ⏳ **버전 의존 = 핀 후 반영**: ③Prisma 7 **AI 차단**(migrate reset을 "invoked by Claude Code"로 거부 — 프레임워크 철학과 일치하나 킷에 "AI는 리셋 못 함" 명시는 버전 확정 후) ④`prisma.config.ts`+어댑터 셋업 구조 ⑤다중파일 스키마 완화책(6.7 GA·7.0 버그). 6.x면 이것들이 다를 수 있음.
**결론**: bnsone은 **Prisma 버전을 명시 결정(ADR)으로 핀**해야 하고, 핀 후 실 scaffold에서 ③④⑤를 킷에 반영. merge-driver 교훈 = 버전 미확정 상태의 blind 처방 금지. **정합 확인**: Prisma 공식 팀 권고("작업 전 pull+대기 마이그레이션 적용, 스키마 변경 전 팀 상의")는 킷 기존 규칙(먼저 git pull·마이그레이션 카드 착수 전 채팅 공지·고위험 라벨)과 정신 일치 — 취지는 맞고 **기계적 해결 레시피만** Prisma용 보정 대기.

### G-09 — package-lock 자동 머지 드라이버는 조용한 손상을 낸다(쓰지 마라, merge=binary로) · 2026-07-27
"마지막 기회" 동시성 리허설에서 실측: 두 브랜치가 각각 다른 dep(dayjs/nanoid)을 추가한 뒤 머지하면 package.json은 충돌하고, **자동 lock 머지 드라이버**(npm-merge-driver든 자체 스크립트든)는 git merge 도중 **package.json이 해결되기 전에** `npm install --package-lock-only`로 lock을 재생성한다 → **한쪽 dep이 조용히 누락된 valid-but-wrong lock**(nanoid 증발, JSON은 유효해 `npm ci` 통과·머지됨 = 눈에 안 보이는 손상). 눈에 보이는 충돌보다 나쁘다. **처방**: 자동 드라이버 두지 말고 `.gitattributes`에 `package-lock.json merge=binary`(자동머지 대신 시끄러운 충돌로 강제) + 해결은 CLAUDE.md 금지 절 **수동 규칙**(package.json만 통합 → `npm install --package-lock-only` — 실측: 3 dep 다 정확). ※이건 **내가 눈감고 바꾼 처방(#12)을 리허설이 잡은 사례** — DD-03(파일럿 선행 검증)의 값을 재확인. **실 Next.js lock 검증 완료(2026-07-27, bnsone 스택 Next.js+PG16 개발자 2인 합의 후)**: 실 Next.js lockfile(902줄·51패키지, sharp/swc optional dep 포함)로 재현 → `merge=binary`가 충돌 강제 ✅, 수동 재생성이 **두 dep + optional dep 24+8개 전부 온전한 canonical 세트로 복원** ✅. **핵심**: OS별로 optional dep가 갈려도(sharp-darwin↔linux) 재생성 한 방이 전체 집합으로 치유 — 혼합 OS 팀도 이 레시피로 충분. (버림 fixture = scratchpad, 정리됨.) 부수: 충돌 마커 제거 정규식은 CRLF(`\r?\n`)를 봐야 한다(G-01/G-03 계열 재현).

### G-08 — 워커에게 브라우저 자동 검증을 맡기면 MCP 호출이 행(hang)될 수 있다 · 2026-07-24
Next.js scaffold 리허설에서 워커 세션이 렌더 검사를 마치고 **`browser_session_stop`에서 24분간 멈춤**(agentStatus=running인데 트랜스크립트 무갱신 — 도구 호출 자체가 반환 안 함). `escape`+`ctrl+c`로 인터럽트해 회수했고, 이미 검증은 끝난 뒤라 결과 손실은 없었다. **처방**: ①워커에게 브라우저 검증을 맡길 땐 **대체 경로를 함께 지시**(curl로 서버 HTML 확인 — 실제로 이 워커는 두 경로 교차 확인을 스스로 했다) ②오케스트레이터는 "정지 = 게이트 대기"로만 보지 말고 **마지막 도구 호출이 MCP면 행을 의심**(트랜스크립트 마지막 tool_use 확인) ③인터럽트 후에는 "브라우저 도구 쓰지 말고 지금까지 확인분으로 보고"로 회수한다.

### G-07 — wmux 원격 조종 수칙 3 + Windows 세션의 권한 규칙은 PowerShell 도구를 봐야 한다 · 2026-07-24
STEP 3 본 리허설(로그 11) 실측 4건. ①**pane을 리허설 도중 닫거나 리사이즈하면 워커 TUI 렌더가 굳는다** — 입력은 살아 있고 화면만 정지(같은 read가 byte 동일 반복이 신호), `ctrl+l`로 리드로우 복구. 관전 무대는 처음부터 pane 폭을 넉넉히. ②**AskUserQuestion 폼은 답변 전까지 트랜스크립트에 안 남는 경우가 있다** → "agentStatus=idle + 트랜스크립트 수 분 정지"가 **폼 대기의 판독법**(G-05의 짝: 트랜스크립트 조용=행 아님). ③**워커의 완료 보고가 뜨기 전에 다음 명령을 보내면 유실된다**(턴 중 입력이 소비됨 — /design 1차 전송 유실 실측) → 보고 확인 후 전송. ④**Windows 세션은 명령을 PowerShell "도구"로 실행하므로 `Bash(...)` allowlist가 안 먹는다** — 승인 연쇄 8회의 뿌리(스킬 allowed-tools도 질문·답변 후 증발 — 공식 문서). 처방 = `PowerShell(...)` 규칙 미러(공식 문법, 킷 settings 반영 MR !65) + 긴 명령 965B 파서 한계는 잔존(그건 프롬프트가 정상). 부수: 권한 파일 수정은 **JSON 재직렬화 금지**(G-01 짝 — 포맷 churn 140줄 사고) → 앵커 줄 텍스트 삽입으로.

### G-06 — 리허설 승인자 계정: 비밀번호를 리셋하면 임퍼서네이션 토큰이 막힌다 · 2026-07-23
관리자 API로 가상 계정 비밀번호를 설정하면(`PUT /users/:id -f password=…`) GitLab이 `password_expired=true`(첫 로그인 시 변경 필수)를 걸고, 이게 **그 계정의 임퍼서네이션 토큰 API까지 403 "Your password expired"로 막는다**(7-23 실측: dev2 승인자 세션 좌초). dev1은 비밀번호를 안 건드려 토큰이 멀쩡했던 것과 대조. **처방**: 리허설용 워커/승인자 Claude 세션은 **비밀번호를 리셋하지 말고 임퍼서네이션 토큰만** 발급해 glab 명의로 쓴다(브라우저 로그인이 꼭 필요할 때만 비밀번호를 설정하되, 그 계정으론 토큰 세션을 돌리지 않는다). 승인 Play가 막히면 **작성자와 다른 유효 계정(Owner=yskim 등)으로 Play**해도 셀프승인 방지 요건은 충족(7-23 이 경로로 #45 완주). 명세 ③은 비번 안 건드린 신규 dev3로 완주(#46).
**추가 함정(7-23 #46)**: `glab api "users?username=X"`는 **fuzzy(부분일치) 검색**이라 `pilot-dev3`를 물어도 `yskim` 같은 부분일치 계정을 함께/먼저 반환한다 → 스크립트가 `sed …"id"…| head -1`로 엉뚱한 uid(yskim=17)를 잡아 멤버추가·토큰발급·잡링크 3곳이 틀어졌다(서버 실측으로 발견·uid 못박아 교정). **처방**: 타계정 uid는 **생성 API 응답의 id**로 확정하거나 정확 매칭으로 걸러라. 토큰은 **발급 즉시 `/api/v4/user`로 명의를 검증**(fix-dev3.sh가 이 검증을 내장).

### G-05 — wmux TUI 조종: "▶ 다음: /cmd" 제안은 입력창이 아니라 렌더 텍스트다 · 2026-07-23
Claude Code 세션을 wmux로 조종할 때, 모델이 출력한 `▶ 다음: /dev 45`는 **화면에 그려진 텍스트지 입력창 내용이 아니다** — 그 상태에서 `terminal_send_key enter`/`escape`/`ctrl+c`는 아무것도 제출·삭제하지 않는다(입력창이 비어 있으므로). **제출은 항상 `terminal_send({text:"/dev 45", submit:true})`**로 하고, 보낸 뒤 `terminal_read`로 화면이 실제로 넘어갔는지 확인한다(도구가 "key delivered ≠ submitted"를 경고). 반대로 **진짜 인터랙티브 선택 메뉴(승인자 고르기·go/수정·Submit)는 렌더된 위젯이라 `enter`/화살표가 정상 동작**한다 — 둘을 구분하는 기준: 물음이 선택지 위젯(`> 1. …`)으로 떴으면 키, 모델이 문장으로 안내만 했으면 `terminal_send` 제출.

### G-04 — planner-guard 운영 노트 2건 (정본 = 여기, CI 주석 동봉은 철회) · 2026-07-23
파일럿 #43 fresh 리뷰의 Minor 2건. 킷 CI 주석으로 반영하려 했으나 bnsone 편집이 분류기에 반복 차단돼(내용 무해 확인, 사유 불명) 드리프트 금지 원칙상 3배포본 모두 주석 없이 두고 **DDR이 정본**:
- **Protected 변수 함정**: `PLANNER_EMAILS`를 protected로 등록하면 비보호 브랜치 파이프라인에 미주입 → 가드가 조용히 비활성. **unprotected로 등록**(bnsone·파일럿 현행 = unprotected 확인, 7-22·7-23).
- **머지 커밋 사각지대**: 가드는 해당 커밋의 author만 본다 — MR 경유 기획자 커밋은 머지 커밋의 머지자 명의에 가려진다. 주 감지 대상 = 비개발자의 main 직접 push(길 A 경로)이므로 설계상 허용, 백스톱 = Leader 매일 점검.

### G-03 — Git Bash(MSYS)로 헤드리스 프로브를 쏘면 슬래시 명령이 경로로 오변환된다 · 2026-07-23
`claude -p "/design"`을 Bash(MSYS) 도구·Git Bash에서 실행하면 인자 선두의 `/`를 POSIX 경로로 해석해 `C:/Program Files/Git/design` 같은 경로 문자열로 바꿔 전달한다 — 스킬이 주입되지 않은 세션이 **오류 없이 조용히** 돈다(겉보기엔 그냥 "이상한 답"). 우회 = 이중 슬래시 `"//design"`(MSYS가 `/design`으로 환원) 또는 PowerShell에서 실행. **프로브가 헛돌면 판정 전에 트랜스크립트(`~/.claude/projects/<repo폴더명>/*.jsonl`)의 첫 user 메시지로 "실제 도착한 프롬프트"부터 확인하라** — 7-23 실측: haiku 소프트 플로어 프로브가 이걸로 무효 시행이 됐고, 트랜스크립트 확인으로 원인을 잡았다(무효 시행을 "실패"로 판정하는 오보 방지).

### G-02 — 헤드리스 프로브는 "여러 턴 경로"를 구조적으로 못 본다 · 2026-07-23
`claude -p` 헤드리스는 1문 1답 일회용이라 **단일 턴 행동·규칙 준수 검증엔 싸고 좋지만**, 선택 다이얼로그·계획 승인 후 배치 실행·수정 왕복 같은 **여러 턴 경로는 아예 발생하지 않는다** — 그 경로의 결함(예: 접힌 미리보기로 등록 직행, 배치 승인 범위)은 실세션 리허설에서만 잡힌다(7-23 실측: 헤드리스 "통과" 직후 실세션에서 경계 2건 발견). **"헤드리스 통과"를 보고할 땐 "단일 턴 범위에서"라는 커버리지 한계를 함께 명시하라.** 행동 검증 체계 = 헤드리스(넓고 싸게, 반복) + 실세션 리허설(깊고 비싸게, DD-03) 병행 — 하나로 다른 하나를 대체하지 않는다.

### G-01 — Windows PowerShell 5.1은 파일을 CP949로 읽어 UTF-8 한글을 손상시킨다 · 2026-07-22
프레임워크용 PS 스크립트를 쓸 때:
- **읽기**: `Get-Content -Raw -Encoding UTF8` (안 주면 한글이 `?몄뀡`처럼 깨져 재기록 시 손상 — settings.json hooks의 한글 메시지를 실제로 손상시킨 사고 있음).
- **쓰기**: `[System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding $false))` = BOM 없는 UTF-8(깨끗한 diff). `Set-Content -Encoding utf8`은 PS5.1에서 **BOM을 붙인다**.
- **native 명령 stderr**: `& git ... 2>&1` + `$ErrorActionPreference='Stop'` 조합은 git의 정상 stderr("Already on 'main'")를 치명적 에러로 취급해 스크립트를 멈춘다 → `Continue` + `2>$null`.
- **한글 코드 조각**: `.ps1`이 UTF-8(BOM 없음)이면 5.1이 CP949로 파싱해 문자열·중괄호가 깨질 수 있음 → 코드/메시지는 ASCII로, 필요하면 BOM 저장.
- **검증 습관**: 실 파일 편집 전 **복사본으로 round-trip 테스트**(한글 보존·유효 JSON·BOM 여부)한 뒤 실행.
