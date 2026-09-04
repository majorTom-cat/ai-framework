---
name: setup-gitlab
description: GitLab 프로젝트 설정을 한 번에 — 라벨·보드 열·main 보호·Pipelines must succeed·멤버 권한. 골격 구축 Day 2에 공통 개발자가 1회. 손으로 클릭하는 반복 설정을 glab으로 대체.
disable-model-invocation: true
argument-hint: "(인자 없음 — 대화로 값 확인)"
allowed-tools: Bash(glab *) Bash(echo *) Read Edit
---

# /setup-gitlab — GitLab 설정 한 번에 (골격 Day 2, 프로젝트당 1회)

> **계약** · 입력: 없음(대화로 값 확인) · 산출물: GitLab 설정(라벨·보드·main 보호·권한)+CLAUDE.md 값 채움 · 검증: 설정 재조회(main 보호 켜짐 확인, ⏸ 게이트)

> **예시**: `/setup-gitlab` (인자 없음 — 모듈·계정 값은 대화로 확인)

> 손으로 하면 라벨 10여 개·보드·보호를 일일이 클릭해야 하고, **하나라도 빠지면 카드 등록·이동이 조용히 실패**한다. 이 스킬이 `glab`으로 한 번에 처리한다. (`export GITLAB_HOST=<사내GitLab주소>` 전제.)

1. **먼저 값을 묻는다** (한 번에): ①모듈 이름들(라벨용) ②기획/디자이너 계정(→ Maintainer) ③개발자 계정(→ Developer).
  - **모듈 이름은 `docs/06_TechnicalDesign`(설계 산출물)에서** 읽어 제안한다 — Day 2엔 CLAUDE.md 소유표가 아직 빈칸(`<모듈b>` 등)이라 거기선 못 읽는다.
  - ★**읽은 이름은 반드시 사람에게 확인받는다**(설계 문서와 실제 코드가 어긋날 수 있다 — 확인 없이 확정하면 엉뚱한 `모듈:*` 라벨이 생긴다, 2026-07-28 실측). 이미 코드가 있으면 `src/modules/`와 대조해 차이까지 함께 보여준다.
2. **⏸ 게이트**: 아래 "이렇게 설정한다" 요약을 보여주고 **승인받은 뒤 실행** (멤버 권한·브랜치 보호는 되돌리기 번거롭다).
3. **라벨 생성** (`glab label create`): 상태(`진행중`·`검수요청`·`무효`·`대기(불명확)`·**`셀프완료`**) + 위험(**`고위험`·`셀프승인`·`승인요청`**(동료 승인 대기 표식 — 채팅 알림용)) + 모듈(`모듈:<각각>`·`shared`·`docs`). **이미 있으면 건너뜀**(중복 에러 무시). (`킷개선` 라벨은 폐지 — 마찰 수집은 `docs/friction.md`가 유일 창구, 2026-08-09)
   ★스킬들이 이 라벨을 적용하므로 하나도 빠지면 안 된다 — `셀프승인`이 없으면 1인 상황의 고위험 MR이 게이트에서 탈출구 없이 막히고(`.peer-approval-gate`), `셀프완료`가 없으면 /done 라벨 전환이 조용히 실패해 /metrics 커버리지가 무너진다.
3-b. **«마찰 수거» 카드 1장** (`glab issue create`): 제목 `마찰 수거 — 안 고쳐진 [막힘]`, **담당자 = 공통 개발자**(멘션이 To-Do·채팅 알림을 타게 하는 것이 이 카드의 전부다), 라벨 `docs`. 본문에 「`docs/friction.md` 의 안 고쳐진 `[막힘]`을 소유자에게 알리는 **상설** 카드 — 줄을 적은 세션이 멘션 댓글로 올리고, 수리한 세션이 닫음 댓글을 남긴다. **이 카드는 닫지 않는다.**」 만든 **번호를 `docs/friction.md` 머리의 `#<수거카드번호>` 자리에 채워 넣는다**(안 채우면 규칙이 가리키는 곳이 없어 그대로 무음이 된다).
   ★왜 카드인가: `friction.md` 는 **아무 기계도 내용을 안 읽는다**(2026-09-04 전수 실측: CI·훅·스크립트 파싱 0건). 담당자 있는 카드의 **멘션 댓글**이라야 알림을 탄다 — **체크박스·라벨 변경은 GitLab 알림 자체가 없다**(2026-08-19 실측). 카드 폭증 걱정은 없다: repo 당 **한 장**이고 「킷 개선은 카드 대신 friction 한 줄」과도 안 부딪힌다(이건 «킷을 고치는 카드»가 아니라 «미해결 목록»이다).
4. **보드 열**: `진행중`·`검수요청` 리스트 생성(`Open`·`Closed`는 기본 제공). glab에 보드 API가 제한적이면 공통 개발자에게 "Plan → Issue boards에서 이 두 열만 수동 추가"로 안내.
5. **멤버 권한** (`glab api projects/:id/members`): 기획/디자이너 = **Maintainer(40)**, 개발자 = **Developer(30)**. 현재값 조회 후 다른 것만 변경.
6. **main 보호 + CI 필수** (셀프머지의 핵심 안전망):
   - `glab api --method POST projects/:id/protected_branches` — merge 허용 = Developer 이상, push는 팀 정책대로(가장 단순=Maintainers, 엄격=No one+MR).
   - `glab api --method PUT projects/:id -f only_allow_merge_if_pipeline_succeeds=true` ("Pipelines must succeed").
   - (정확한 파라미터는 실행 시 `glab api` 응답으로 확인·보정.)
   - **glab이 실패하면 웹으로 대체**: Settings → Repository → **Protected branches** → `main`(Allowed to merge = Developers+, Allowed to push = No one/팀 정책) · Settings → Merge requests → **Pipelines must succeed ✔**.
   - ★**main 보호가 실제로 켜졌는지 조회로 확인**(`glab api projects/:id/protected_branches`)한 뒤 넘어간다 — 이게 안 켜지면 **개발자 착수 전 안전망이 통째로 빈다**(ADR-0001).
6-1. **게이트 토큰 등록** (고위험 게이트의 작성자 판정용 — **없으면 게이트가 fail-open**: 커밋 author 메일≠GitLab 메일이면 셀프 승인이 무음 통과한다):
   - read_api 전용 **프로젝트 액세스 토큰**을 발급해 CI 변수로 등록한다(웹 불필요, Maintainer 권한이면 API로 됨):
     `echo '{"name":"gate-reader","scopes":["read_api"],"access_level":20,"expires_at":"<1년 내>"}' | glab api --method POST "projects/:id/access_tokens" --input - -H "Content-Type: application/json"`
     → 응답의 `token` 값을 `glab variable set GATE_API_TOKEN <값> --masked`. (★glab의 `-f "scopes[]=…"` 표기는 HTTP 400, `--input`만 쓰면 415 — JSON 본문+명시적 헤더가 필수. 2026-08-07 실측)
   - **만료일을 팀 캘린더·카드로 남긴다** — 만료되면 fail-open이 소리 없이 되살아난다. 인스턴스가 프로젝트 토큰을 막아 뒀으면 웹에서 개인 read_api 토큰으로 대체.
   - (기획/디자이너 push 감시를 쓰려면 `PLANNER_EMAILS`도 여기서: `glab variable set PLANNER_EMAILS a@x,b@x` — 미등록이어도 무해, planner-guard가 비활성일 뿐.)
7. **플레이스홀더 반영** (Edit) — 지금 아는 값을 채운다:
  - `<사내GitLab주소>`·`<팀채팅주소>`·`<기획자아이디>`(기획 계정. **2인 이상이면 멘션이 전원에게 가도록 `@a @b` 형태로 넣는다**)
  - **`## 소유 경계` 표에 `docs/06`의 모듈 이름으로 행을 만든다**(소유자 칸은 팀 합류 때 `/assign-module <모듈> <사람>`로 — 지금은 행만, 소유자는 비워둠).
  - `<검수서버URL>`·`<본보기모듈>`은 아직(인프라·Day 6).
   ★**`<팀채팅주소>`는 URL이 아니어도 된다** — 채널 URL을 넣거나, 채팅 도구에 AI가 접근할 수 없는 팀이면 **방침 문구**로 채운다(예: `공지 게시는 사람이 직접 — AI는 공지 문구만 작성`, bnsone 실사례). 어느 쪽인지 물어서 정한다.
   ★**`<기획자아이디>` 치환은 CLAUDE.md뿐이다** — rules·스킬 파일은 치환하지 마라(킷 동기 byte 복사가 되돌린다 — 2026-08-14 구조 수리): `/done`·`/docs`·rules/docs.md는 `{기획자}`를 실행 시점에 CLAUDE.md에서 읽는다.
8. **✅ 확인** — 라벨·보드·보호·멤버가 실제로 걸렸는지 **조회로 재확인**하고, 안 된 항목이 있으면 수동 보완 방법을 알려준다. 요약 보고.
9. **"▶ 다음: Day 3(규칙 빈칸 채우기) → 소유자 정해지면 `/assign-module` → Day 5 파일럿"** 안내.

## ❌ 금지
- 값(모듈·멤버)을 **지어내기** — 반드시 공통 개발자에게 확인.
- 되돌리기 번거로운 것(멤버 권한·브랜치 보호)을 **요약·승인 없이** 실행(2번 게이트).
- main 보호·Pipelines must succeed를 **빼먹기** — 이게 없으면 셀프 머지 구조의 자동 안전망이 통째로 빈다.
