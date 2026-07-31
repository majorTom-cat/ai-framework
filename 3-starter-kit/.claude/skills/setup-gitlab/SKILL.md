---
name: setup-gitlab
description: GitLab 프로젝트 설정을 한 번에 — 라벨·보드 열·main 보호·Pipelines must succeed·멤버 권한. 골격 구축 Day 2에 공통 개발자가 1회. 손으로 클릭하는 반복 설정을 glab으로 대체.
disable-model-invocation: true
argument-hint: "(인자 없음 — 대화로 값 확인)"
allowed-tools: Bash(glab *) Read Edit
---

# /setup-gitlab — GitLab 설정 한 번에 (골격 Day 2, 프로젝트당 1회)

> **계약** · 입력: 없음(대화로 값 확인) · 산출물: GitLab 설정(라벨·보드·main 보호·권한)+CLAUDE.md 값 채움 · 검증: 설정 재조회(main 보호 켜짐 확인, ⏸ 게이트)

> **예시**: `/setup-gitlab` (인자 없음 — 모듈·계정 값은 대화로 확인)

> 손으로 하면 라벨 10여 개·보드·보호를 일일이 클릭해야 하고, **하나라도 빠지면 카드 등록·이동이 조용히 실패**한다. 이 스킬이 `glab`으로 한 번에 처리한다. (`export GITLAB_HOST=<사내GitLab주소>` 전제.)

1. **먼저 값을 묻는다** (한 번에): ①모듈 이름들(라벨용) ②기획/디자이너 계정(→ Maintainer) ③개발자 계정(→ Developer).
  - **모듈 이름은 `docs/06_TechnicalDesign`(설계 산출물)에서** 읽어 제안한다 — Day 2엔 CLAUDE.md 소유표가 아직 빈칸(`<모듈b>` 등)이라 거기선 못 읽는다.
  - ★**읽은 이름은 반드시 사람에게 확인받는다**(설계 문서와 실제 코드가 어긋날 수 있다 — 확인 없이 확정하면 엉뚱한 `모듈:*` 라벨이 생긴다, 2026-07-28 실측). 이미 코드가 있으면 `src/modules/`와 대조해 차이까지 함께 보여준다.
2. **⏸ 게이트**: 아래 "이렇게 설정한다" 요약을 보여주고 **승인받은 뒤 실행** (멤버 권한·브랜치 보호는 되돌리기 번거롭다).
3. **라벨 생성** (`glab label create`): 상태(`진행중`·`검수요청`·`무효`·`대기(불명확)`) + 위험(`고위험`) + 모듈(`모듈:<각각>`·`shared`·`docs`) + **`킷개선`**(스킬·규칙 우회 수집 — CLAUDE.md 규칙 참조). **이미 있으면 건너뜀**(중복 에러 무시). ★스킬들이 이 라벨을 적용하므로 하나도 빠지면 안 된다.
4. **보드 열**: `진행중`·`검수요청` 리스트 생성(`Open`·`Closed`는 기본 제공). glab에 보드 API가 제한적이면 공통 개발자에게 "Plan → Issue boards에서 이 두 열만 수동 추가"로 안내.
5. **멤버 권한** (`glab api projects/:id/members`): 기획/디자이너 = **Maintainer(40)**, 개발자 = **Developer(30)**. 현재값 조회 후 다른 것만 변경.
6. **main 보호 + CI 필수** (셀프머지의 핵심 안전망):
   - `glab api --method POST projects/:id/protected_branches` — merge 허용 = Developer 이상, push는 팀 정책대로(가장 단순=Maintainers, 엄격=No one+MR).
   - `glab api --method PUT projects/:id -f only_allow_merge_if_pipeline_succeeds=true` ("Pipelines must succeed").
   - (정확한 파라미터는 실행 시 `glab api` 응답으로 확인·보정.)
   - **glab이 실패하면 웹으로 대체**: Settings → Repository → **Protected branches** → `main`(Allowed to merge = Developers+, Allowed to push = No one/팀 정책) · Settings → Merge requests → **Pipelines must succeed ✔**.
   - ★**main 보호가 실제로 켜졌는지 조회로 확인**(`glab api projects/:id/protected_branches`)한 뒤 넘어간다 — 이게 안 켜지면 **개발자 착수 전 안전망이 통째로 빈다**(ADR-0001).
7. **플레이스홀더 반영** (Edit) — 지금 아는 값을 채운다:
  - `<사내GitLab주소>`·`<팀채팅주소>`·`<기획자아이디>`(기획 계정. **2인 이상이면 멘션이 전원에게 가도록 `@a @b` 형태로 넣는다**)
  - **`## 소유 경계` 표에 `docs/06`의 모듈 이름으로 행을 만든다**(소유자 칸은 팀 합류 때 `/assign-module <모듈> <사람>`로 — 지금은 행만, 소유자는 비워둠).
  - `<검수서버URL>`·`<본보기모듈>`은 아직(인프라·Day 6).
   ★**`<팀채팅주소>`는 URL이 아니어도 된다** — 채널 URL을 넣거나, 채팅 도구에 AI가 접근할 수 없는 팀이면 **방침 문구**로 채운다(예: `공지 게시는 사람이 직접 — AI는 공지 문구만 작성`, bnsone 실사례). 어느 쪽인지 물어서 정한다.
   ★**`<기획자아이디>`는 CLAUDE.md 밖에도 산다** — `.claude/rules/docs.md`·`.claude/skills/done/SKILL.md`·`.claude/skills/docs/SKILL.md`까지 **함께 치환**한다(안 하면 `/done`·`/docs`가 `@<기획자아이디>`를 그대로 멘션해 **알림이 아무에게도 안 간다** — 2026-07-28 파일럿 실측). 치환 후 `grep '<기획자아이디>'`로 남은 곳 0을 확인한다(가이드 문서의 설명용 언급은 제외).
8. **✅ 확인** — 라벨·보드·보호·멤버가 실제로 걸렸는지 **조회로 재확인**하고, 안 된 항목이 있으면 수동 보완 방법을 알려준다. 요약 보고.
9. **"▶ 다음: Day 3(규칙 빈칸 채우기) → 소유자 정해지면 `/assign-module` → Day 5 파일럿"** 안내.

## ❌ 금지
- 값(모듈·멤버)을 **지어내기** — 반드시 공통 개발자에게 확인.
- 되돌리기 번거로운 것(멤버 권한·브랜치 보호)을 **요약·승인 없이** 실행(2번 게이트).
- main 보호·Pipelines must succeed를 **빼먹기** — 이게 없으면 셀프 머지 구조의 자동 안전망이 통째로 빈다.
