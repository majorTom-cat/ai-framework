#!/usr/bin/env bash
# 위험 명령 앞단 훅 (PreToolUse:Bash|PowerShell) — **ask만 낸다. allow도 deny도 내지 않는다.**
# 보는 것 4가지: ①검수요청 카드 자기닫기(glab issue close) ②git 훅 우회(--no-verify·commit -n·core.hooksPath)
#   ③force push(-f/--force*/+refspec) ④공통 영역 push.
# 경위(2026-07-30 하루 4구멍 실측): ①좁은 매칭 = 따옴표 체이닝에서 침묵(무확인 push) ②넓은 매칭+allow =
#   "git…push 글자가 든 아무 명령"(rm -rf·curl|bash 체이닝 포함)까지 권한창 없이 자동 승인 ③넓은 매칭+deny = 오탐 차단
#   ④ask 전용+넓은 매칭 = 확인창 폭주(1 push에 8회). → 역할 분리가 답:
#   일반 push 마찰 0 = settings.json allow(명령 "접두" 기준이라 과잉 승인 없음) / force push 차단 = settings.json deny /
#   공통 영역·체이닝 force·카드 닫기 감지 = 이 훅의 ask. 훅이 allow를 내는 순간 승인 범위가 명령 전체로 넓어진다 — 다시 넣지 마라.

INPUT=$(cat)

# 명령 문자열 추출 후 "명령 경계" 기준 매칭 — 문자열 시작·;·&·|·(·줄바꿈(\n)·\r·\t 뒤의 실제 명령만.
# ★경계에 \\n 필수 — 여러 줄 명령(heredoc 뒤 git push)은 JSON에서 `…\ngit push`가 되어, 없으면 침묵한다(실측).
# 대소문자 무시(-i) — PowerShell은 `Git Push`도 실행한다.
# ★값의 닫는 따옴표에서 끊는다(`\"`·`\\`는 넘어감) — 안 끊으면 뒤 필드(`description` 등)의 글자가 판정에 섞여
#   무해한 조회 명령이 오탐 ask를 낸다(2026-08-11 fresh 리뷰 M-2 실측). 형식이 안 맞으면 옛 방식으로 폴백(무음화 방지).
CMD=$(printf '%s' "$INPUT" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p')
[ -z "$CMD" ] && CMD=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)/\1/p')

# ask 출력기 — 사유문에 `"`·`\`를 쓰지 마라(JSON이 깨진다).
emit_ask() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"; }

# ── ① 검수요청 카드 자기닫기 게이트 (push와 무관하므로 push 판정보다 먼저) ──
# 근거(2026-08-06 실측): 검수요청 경로 카드 9/9를 구현자와 같은 계정이 닫았고 5장은 라벨 부여 2초 뒤에 닫혔다.
# CLAUDE.md 전이표(2026-08-12 개정) = 막는 것은 '같은 사람'이 아니라 '사람이 안 본 것' — 구현자 본인 검수는 허용,
#   확답 없는 close만 금지(확답+증적 댓글+라벨 해제). 9/9 동일계정보다 '라벨 2초 뒤 닫힘'이 사고의 실체였다.
# 셀프완료 경로(검수요청 라벨 없음)는 그대로 통과시킨다.
if printf '%s' "$CMD" | grep -Eiq '(^|[;&|(]|\\n|\\r|\\t)[[:space:]]*glab[[:space:]]+issue[[:space:]]+close([[:space:]]|$|"|\\)'; then
  # `close` 뒤의 이슈 번호(들) = 숫자만인 토큰. 플래그·그 값(`-R a/b`)이 끼어도 넘어가고, 명령 구분자
  # (;&|"·역슬래시)에서 멈춘다 — 뒷 명령의 숫자를 이슈 번호로 오인하지 않게. 최대 3건만 조회한다.
  IIDS=$(printf '%s' "$CMD" | tr 'A-Z' 'a-z' \
    | grep -oE 'glab[[:space:]]+issue[[:space:]]+close([[:space:]]+[^[:space:];&|"\\]+)*' \
    | tr -s '[:space:]' '\n' | grep -E '^#?[0-9]+$' | tr -d '#' | sort -u | head -3)
  # glab은 GET만 쓴다(라벨 조회). Windows에서 glab이 stdin을 물고 무기한 행에 걸린 실측이 있어 </dev/null +
  # timeout(있는 환경에서만 — macOS엔 기본 미설치) 필수. ★조회 실패·번호 미검출은 "모름"이니 통과시킨다
  # (가용성 우선 — 훅이 네트워크 사정으로 작업을 막으면 안 된다. 대신 /done 절차의 사람 게이트가 백스톱).
  TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 20"
  for IID in $IIDS; do
    if $TO glab api "projects/:id/issues/$IID" </dev/null 2>/dev/null \
       | grep -Eq '"labels"[[:space:]]*:[[:space:]]*\[[^]]*검수요청'; then
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ #%s 는 `검수요청` 카드입니다 — **사람이 화면을 직접 보고 이상 없다고 확답**했나요? 확답 없이 닫으면 검수 자체가 사라집니다(구현자 본인이 검수해도 되지만, AI가 알아서 닫는 것은 금지). 필요한 것: 확답 + 증적 댓글(확답자·일시·3기준 결과) + `검수요청` 라벨 해제. (셀프완료 대상이면 라벨을 떼고 진행)"}}\n' "$IID"
      exit 0
    fi
  done
fi

# ── ② git 훅 우회 **판정** (--no-verify · commit -n · core.hooksPath · HUSKY=0) ──
# 팀 git 훅(husky pre-push·commit 검사 — Leader Day 4 설치)은 -n 한 번이면 조용히 꺼진다. 셀프 머지의 전제 = 검사 우회 불가.
# ECC(Everything Claude Code) block-no-verify.js에서 차용(경위 _reference/push-guard.md) — 원본의 exit 2 차단이 아니라 이 훅의 철칙대로 ask만.
# ★여기서는 **판정만** 하고 출력은 ③ 뒤로 미룬다 — 한 명령에 force push가 섞이면 그 문구가 우선이다.
#   (사용자가 읽는 사유문이 승인 근거인데 "원격 이력을 덮어씁니다"가 약한 문구로 덮였다 — 2026-08-11 fresh 리뷰 I-4 실측.)
# ★GBODY는 `\\.`로 **모든 이스케이프(\" \\ \n \t \u)를 넘는다** — heredoc 커밋(`-m "$(cat <<EOF\n…`)이 Claude Code의 표준
#   커밋 형태인데 \n에서 멈춰 통째로 침묵했다(리뷰 I-1). --no-verify는 아예 분리 판정한다(인용문 안 `;`·`|`이 가리던 문제 — I-3).
BYPASS_MSG=""
GBODY='([^;&|\\]|\\.)*'
GEND='([[:space:];&|()<>]|$|"|\\)'                       # ★`;`·`)` 필수 — `git commit --no-verify;` 한 글자로 뚫렸다(I-1)
GPRE='(^|[;&|("]|\\n|\\r|\\t)[[:space:]]*((then|do|else)[[:space:]]+)?(env[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|\\]*[[:space:]]+)*'
GITSEG="${GPRE}"'git[[:space:]]'                          # 환경변수 접두(`HUSKY=0 git …`)·제어문(`then git …`)까지 넘는다(I-2)
GOPT='((-[Cc][[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+|--no-pager)[[:space:]]+)*'
if printf '%s' "$CMD" | grep -Eiq "${GITSEG}" && printf '%s' "$CMD" | grep -Eiq "(^|[[:space:]\"])--no-verify${GEND}"; then
  BYPASS_MSG="⚠️ git 훅 우회 감지(--no-verify) — 팀 git 훅(pre-push·commit 검사)을 건너뜁니다. CLAUDE.md 금지 항목: 훅이 잘못 막으면 우회하지 말고 훅을 고치세요. 정말 진행하나요?"
elif printf '%s' "$CMD" | grep -Eiq 'core\.hooksPath|(^|[[:space:];&|("])HUSKY=0([[:space:]]|$)'; then
  BYPASS_MSG="⚠️ git 훅 무력화 감지(core.hooksPath / HUSKY=0) — 팀 git 훅이 통째로 꺼집니다. 조회·복원 목적이면 승인하세요."
# commit의 -n(번들 -an·-nm 포함)도 --no-verify다. ★push의 -n은 --dry-run(무해)이라 commit 뒤에서만 본다.
#   `git`+전역옵션 다음이 곧 `commit`일 때만 본다 — 안 그러면 `push origin feature/commit-fix -n`이 오탐이었다(M-3).
elif printf '%s' "$CMD" | grep -Eiq "${GITSEG}${GOPT}commit${GBODY}[[:space:]]-[a-z]{0,2}n[a-z]{0,2}${GEND}"; then
  BYPASS_MSG="⚠️ git commit -n 감지 — -n은 --no-verify(팀 git 훅 건너뜀)입니다. CLAUDE.md 금지 항목: 검사는 우회가 아니라 통과가 답입니다. 정말 진행하나요?"
fi

# ── ③ 이하 push 게이트 ── 문자열 시작·;·&·|·( 뒤의 실제 `git … push`만.
# ★조각은 반드시 **단일 인용**으로 만들어 변수로 넘긴다 — 이중 인용 안에 `\\n`을 쓰면 bash가 `\n`으로 줄여
#   ERE가 "글자 n"을 찾게 되고 여러 줄 명령 감지가 통째로 죽는다(경계의 `\\n`이 이 훅의 급소).
# git 과 push 사이의 전역 옵션(-C <경로>·-c k=v·--git-dir=·--work-tree=·--no-pager)까지 넘어간다
#   — `git -c core.pager=x push -f` 는 settings.json deny(접두)도 훅 옛 버전도 둘 다 못 봤다.
GITP='(^|[;&|(]|\\n|\\r|\\t)[[:space:]]*git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+|--no-pager))*[[:space:]]+push'
ARGS='([[:space:]]+[^[:space:];&|\\]+)*[[:space:]]+'   # push 뒤 인자들(명령 구분자에서 멈춤)
ENDW='([[:space:]]|$|"|\\)'                            # 토큰 끝
ENDF='([[:space:]=]|$|"|\\)'                           # 토큰 끝(`--force-with-lease=ref` 포함)
# push 명령이 아니면 여기서 끝 — 단 ②의 훅 우회 판정(commit·config 등)은 이때 낸다.
printf '%s' "$CMD" | grep -Eiq "${GITP}${ENDW}" || { [ -n "$BYPASS_MSG" ] && emit_ask "$BYPASS_MSG"; exit 0; }

# ★force push의 우회 경로 2종 — 둘 다 settings.json deny가 못 잡는다(deny는 명령 "접두" 기준이라
#   체이닝 `git status && git push -f`·`git -C <path> push --force`에 침묵. 2026-08-06 실측).
#   (a) 플래그형: -f / -fu 같은 묶음 / --force / --force-with-lease / --force-if-includes(`=`도)
#   (b) +refspec형: `git push origin +HEAD:main` — -f 없이도 force다.
#   여기서도 ask만 낸다(deny 금지 — 오탐이 실제 작업을 막았던 게 2026-07-30 실패 ③).
#   오탐 억제: (a)는 `-`로 시작하는 토큰만(`--follow-tags`·`--set-upstream`은 안 걸린다), (b)는 `+` 뒤에 공백 없는 refspec 토큰만.
if printf '%s' "$CMD" | grep -Eiq "${GITP}${ARGS}(-[a-z]*f[a-z]*|--force[a-z-]*)${ENDF}"; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ force push 감지 (-f / --force / --force-with-lease) — 원격 이력을 덮어씁니다. CLAUDE.md 금지 항목입니다. main이 잘못됐으면 force가 아니라 revert 커밋으로 되돌리세요(_reference/revert 레시피)."}}\n'
  exit 0
fi
REFSPEC='\+[^[:space:];&|"\\]+'
if printf '%s' "$CMD" | grep -Eiq "${GITP}${ARGS}${REFSPEC}${ENDW}"; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ +refspec force push 감지 (예: git push origin +HEAD:main) — -f 없이 원격 이력을 덮어씁니다. main이 잘못됐으면 force가 아니라 revert 커밋으로 되돌리세요."}}\n'
  exit 0
fi

# force가 아닌 push에 훅 우회가 섞였으면 여기서 낸다(공통 영역 안내보다 우선 — 검사를 건너뛰는 쪽이 더 위험하다).
[ -n "$BYPASS_MSG" ] && { emit_ask "$BYPASS_MSG"; exit 0; }

# 원격 main 대비 변경 파일. 실패(=ref 없음·repo 밖)는 "모름" — 무출력으로 일반 권한 체계에 위임(allow 반환 = fail-open 금지).
# core.quotepath=false: 한글 경로가 8진 이스케이프로 나오면 앵커가 빗나간다(실측). diff.renames=false: rename이 도착 경로만
# 남아 공통 영역에서 "빼내는" 이동이 침묵한다(실측) — 원본·도착 둘 다 보이게 끈다.
CHANGED=$(git -c core.quotepath=false -c diff.renames=false diff --name-only origin/main...HEAD 2>/dev/null) || exit 0
[ -z "$CHANGED" ] && exit 0
CHANGED=$(printf '%s\n' "$CHANGED" | sed 's/^"//; s/"$//')

# 공통 영역 패턴 — **프로젝트에 맞게 수정**: `.gitlab-ci.yml`의 `high-risk-gate` `changes:` 목록과 1:1로 맞춘다.
# (CI가 고위험이라 부르는 경로를 로컬 훅이 침묵하면 이중화의 앞단이 비고 CI만 남는다.)
# 스택 치환 지점: 마이그레이션 경로(`db/migrations/` — Prisma면 `prisma/`)·라우팅 핫스팟 파일(스택마다 위치가 다르다).
# scripts/ 는 **게이트 실물만** 열거한다 — 전체를 걸면 스파이크·작업 코드까지 매번 확인창이 떠 도장찍기가 된다.
# ★lockfile·package.json은 루트 앵커(^) 밖 — 모노레포 하위(`apps/web/package.json`)를 못 잡았다.
HITS=$(printf '%s\n' "$CHANGED" | grep -iE '^(src/shared/|\.claude/|\.gitlab/|\.husky/|db/migrations/|CLAUDE\.md$|\.gitattributes$|\.gitlab-ci\.ya?ml$|docker-compose\.ya?ml$|Dockerfile$|scripts/(check-boundaries\.cjs|check-density\.sh|gen-module\.cjs)$)|(^|/)(middleware|proxy)\.[a-z.]+$|(^|/)package(-lock)?\.json$|(^|/)(yarn\.lock|pnpm-lock\.yaml)$' || true)
[ -z "$HITS" ] && exit 0

N=$(printf '%s\n' "$HITS" | grep -c .)
# ★역슬래시 먼저, 따옴표 나중 — 순서가 바뀌거나 역슬래시를 빼면 파일명의 `\`가 깨진 JSON을 만들어
#   훅 출력 전체가 무효가 된다(= 판정이 통째로 사라진다).
FILES=$(printf '%s\n' "$HITS" | head -5 | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
[ "$N" -gt 5 ] && FILES="${FILES}외 $((N-5))건 "
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 공통 영역 변경이 포함된 push: %s— 팀 채팅에 공지했으면 승인하세요. (Show 등급: 공지는 알림이지 허락이 아님)"}}\n' "$FILES"
exit 0
# 알려진 한계(의도적 미해결): HEAD 아닌 refspec(git push origin other:main)은 HEAD 기준으로 오판할 수 있다.
#   커밋 메시지 등 인용문 "안"의 --no-verify·-n 문구는 오탐 ask가 뜰 수 있다(ask라 작업을 막지는 않는다 — 승인하면 진행).
#   `glab issue close 96 97`처럼 여러 번호는 앞 3건만 조회한다. `glab issue update N --state close`·웹 UI 닫기는 미탐(close 명령만 본다).
#   훅 출력은 1건뿐 — 한 명령에 위험이 둘 섞이면(`glab issue close 97 && git push -f`) 먼저 걸린 하나만 알린다(위 순서대로).
#   timeout 이 없는 환경(macOS 기본)에서는 라벨 조회에 시간 상한이 없다 — glab이 행에 걸리면 훅도 같이 기다린다.
