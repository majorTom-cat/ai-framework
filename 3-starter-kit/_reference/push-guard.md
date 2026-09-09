# push 가드 경위 — 실측 예외 (CLAUDE.md '공통 영역' 절에서 옮김, 삭제 아님)

> CLAUDE.md 밀도 규약(300자/줄)에 따라 규칙 본문에서 분리한 **근거·사고 이력**. 규칙 자체는 CLAUDE.md에 짧게 있다. 여기는 "왜 이렇게 됐나"가 궁금할 때만 읽는다.

## 2026-07-30 하루에 push 가드가 네 번 뚫린 경위

같은 가드에서 네 번, 전부 "훅이 판단을 넓게 하려다" 났다:

1. **좁은 매칭 → 우회**: 훅 정규식 `[^"]*git push`가 따옴표 섞인 체이닝(`git add X && git commit -m "msg" && git push`)에서 이스케이프 따옴표에 끊겨 **침묵** = 무확인 push 2회. 커밋 메시지에 따옴표는 표준이라 노출도 높음.
2. **넓은 매칭 + allow → 과잉 승인**: 공통 영역이 전혀 없는데 `git status && rm -rf node_modules && … && git push` 같은 **임의 명령까지 allow**(권한창 없이 통과). allow는 툴 호출 전체의 프롬프트를 건너뛴다.
3. **넓은 매칭 + deny → 오탐**: "git…push" 글자가 든 댓글·문서·MR 생성 명령까지 차단.
4. **ask 전용 + 넓은 매칭 → 확인창 폭주**: 1회 push에 8회 이상.

**결론(정착)**: 훅은 **ask 하나만** 낸다. allow도 deny도 내지 않는다.
- 일반 push 마찰 0 = `settings.json` allow (명령 **접두** 기준 — 문자열만 포함한 명령엔 오탐 없음)
- force push 차단 = `settings.json` deny (`-f`·`--force`·`--force-with-lease`·`git -C` 변형 — 26줄. 단 **접두 규칙이라 체이닝 `git status && git push -f`는 못 막음** → 아래 훅 ask가 덮는다)
- 공통 영역 감지 = 훅의 **알림**(`additionalContext` — 확인 창 아님). ★2026-09-10 에 ask 에서 내렸다: 기준은 「위험한가」가 아니라 **「revert 커밋 하나로 되돌아가나」**이고(오너 결정), 공통 영역 push 는 되돌아간다. 되돌릴 수 없는 것(force·훅 우회·`검수요청` 카드 닫기)만 ask 로 남았다. ⚠️같이 고친 것: **회귀 시험이 «창»과 «알림»을 구분하지 못했다** — 사유 문구만 grep 해서 ask 를 알림으로 바꿔도 56/56 초록이었다. `t()` 에 판정 종류 검사를 넣었고, 기대를 뒤집으면 3건이 FAIL 하는 것으로 잣대를 증명했다.
- **2026-08-07 훅 확장(검증 7건 후속)**: force 플래그 체이닝(`&&`·묶음 `-fu`·여러 줄)·`git -c`/`--git-dir`/`--work-tree` 전역옵션 변형 → **ask** / `glab issue close`로 검수요청 카드를 닫으려 하면 라벨 조회 후 **ask**(검수요청→완료는 사람만). 시뮬 34케이스 검증 — 한계: ask는 승인하면 실행되고, 한 명령에 위험 둘이면 먼저 걸린 하나만 알린다.
- **2026-08-11 훅 확장(외부 차용) + 같은 날 fresh 리뷰 2인의 수리**: git 훅 우회(`--no-verify`·`commit -n`(=no-verify. push의 `-n`은 dry-run이라 제외)·`core.hooksPath`·`HUSKY=0`) → **ask**. husky로 까는 팀 git 훅(Day 4)이 플래그 하나로 조용히 꺼지는 구멍을 막는다. ECC(affaan-m/ECC)의 `block-no-verify.js`에서 차용하되 원본의 exit 2 하드 차단은 이 훅의 철칙(ask만)대로 낮췄다.
  **★1차 구현이 fresh-context 리뷰 2인에게 Blocker 1·Important 8을 맞았다 — 전부 수리 후 채택**(자기 설계 케이스로 20/20 통과했던 것이 실제로는 뚫려 있었다 = 자기 검증의 한계 재확인, G-11 계열):
  - **B-1 정작 지킬 자산이 무방비였다** — `.husky/`가 훅 공통영역 패턴에도 CI `high-risk-gate` `changes:`에도 없었다. `--no-verify`는 커밋 1회를 우회하고 확인창이 뜨는데, `.husky/pre-push`를 `exit 0`으로 고치면 **전원의 앞으로 모든 커밋**이 확인창 없이 우회된다. 비싼 길에 문 달고 싼 길을 열어둔 꼴 → 양쪽에 `.husky/` 추가.
  - **I-4 강한 경고가 약한 경고로 덮였다** — 새 게이트를 push 게이트 **앞**에 두어 `git commit --no-verify && git push -f`가 "훅 우회"로만 떴다(A/B 5/5 강등 실측). 사용자가 읽는 사유문이 승인 근거인데 "원격 이력을 덮어씁니다"가 사라졌다 → **판정만 앞에서 하고 출력은 force·refspec 뒤로** 미룬다.
  - **I-1·I-3 heredoc·인용문 안 구분자로 침묵** — `git commit -m "$(cat <<EOF…)" --no-verify`(Claude Code의 표준 커밋 형태)·`-m "a;b" --no-verify`가 통째로 안 잡혔다 → `--no-verify`는 **분리 판정**(git 명령 존재 + 플래그 존재), 안쪽 매칭은 `\\.`로 모든 이스케이프를 넘는다.
  - **I-1' 종결자 한 글자로 무력화** — `git commit --no-verify;`·`(…)`·`if …; then …; fi` 침묵 → 토큰 끝에 `;`·`)` 등 추가.
  - **I-2 환경변수 접두 한 토큰으로 전면 무력화** — `HUSKY=0 git commit`·`GIT_CONFIG_KEY_0=core.hooksPath … git commit` 침묵 → 접두(`env`·`VAR=…`·`then`/`do`)를 넘고, `core.hooksPath`·`HUSKY=0`은 위치 무관 판정.
  - **M-2 뒤 JSON 필드 누수** — 추출 sed가 줄 끝까지 잡아 `description`의 글자가 판정에 섞였다(무해한 조회가 오탐) → 값의 닫는 따옴표에서 끊고 실패 시 옛 방식 폴백.
  - **M-3 `commit` 부분문자열 오탐** — `git push origin feature/commit-fix -n`이 "commit -n"으로 떴다(설계가 금지한 push -n 발화) → `git`+전역옵션 다음이 곧 `commit`일 때만.
  **남은 한계(의도적)**: 인용문 안에 `--no-verify`·` -n `이 글자로 들어가면 오탐 ask(막지는 않음 — 이 훅을 고치는 세션에서 자주 뜬다) · `bash -c '…'`(홑따옴표)·별칭 사용·`~/.gitconfig` 직접 편집·`npm run` 간접 실행은 미탐 · Edit/Write는 훅 matcher(`Bash|PowerShell`) 밖이라 `.husky` 편집 자체는 훅이 못 본다(막는 건 push·머지 게이트).
  **검증**: `scripts/test-check-push.sh` **47케이스**(우회 20·오탐 회귀 13·기존 게이트 8·이상 입력 2 등) — 리뷰가 실측으로 뚫은 케이스를 전부 포함. 훅을 고치면 이걸 먼저 돌려라. 실세션 발화 1회 확인이 정본(파일럿 실측 완료). 분석 전문: ai-framework `4-reference/ecc-skills-sh-analysis.md`.

## 훅 매칭 세부 (재발 방지)

- **명령 경계** 기준: 문자열 시작·`;`·`&`·`|`·`(`·**줄바꿈(`\n`·`\r`·`\t`)** 뒤의 실제 `git … push`만. 줄바꿈을 빼면 heredoc 뒤 `…\ngit push`가 침묵(실측).
- `git -c core.quotepath=false`(한글 경로가 8진 이스케이프로 나와 앵커 빗나감) + `diff.renames=false`(rename이 도착 경로만 남아 shared에서 빼내는 이동이 침묵).
- 판단 불가(origin/main ref 없음·repo 밖)는 **무출력 위임** — allow를 내면 fail-open.
- 공통 패턴에 `.claude/`(가드 자신)·`.gitlab/`·`package-lock.json`·`db/migrations/`(**스택 마이그레이션 경로로 치환** — Prisma면 `prisma/`)·CI/컨테이너 설정·게이트 스크립트·`middleware.*`/`proxy.*`(Next 16 개명) 포함, 대소문자 무시. **CI `high-risk-gate`의 `changes:` 목록과 1:1로 유지하라**(CI가 고위험이라 부르는 경로에 로컬 훅이 침묵하면 이중화의 앞단이 빈다).

## allow/ask 우선순위

Claude Code 권한 문서는 deny→ask→allow 순서로 정의하고 "allow가 있어도 ask는 뜬다"고 한다. 다만 관측이 엇갈려(무확인 push가 allow 우선 때문인지 훅 미발화 때문인지) **단정하지 않는다** — 실제 확정 원인은 ①의 정규식 침묵이었다. 자동승인(auto/bypass) 세션의 훅 동작도 재검증 전까지 "믿지 마라"로 둔다.
