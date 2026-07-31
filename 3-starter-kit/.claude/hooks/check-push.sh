#!/usr/bin/env bash
# push 전 공통 영역 감지 훅 (PreToolUse:Bash|PowerShell) — **ask만 낸다. allow도 deny도 내지 않는다.**
# 경위(2026-07-30 하루 4구멍 실측): ①좁은 매칭 = 따옴표 체이닝에서 침묵(무확인 push) ②넓은 매칭+allow =
#   "git…push 글자가 든 아무 명령"(rm -rf·curl|bash 체이닝 포함)까지 권한창 없이 자동 승인 ③넓은 매칭+deny = 오탐 차단
#   ④ask 전용+넓은 매칭 = 확인창 폭주(1 push에 8회). → 역할 분리가 답:
#   일반 push 마찰 0 = settings.json allow(명령 "접두" 기준이라 과잉 승인 없음) / force push 차단 = settings.json deny /
#   공통 영역 감지 = 이 훅의 ask 하나. 훅이 allow를 내는 순간 승인 범위가 명령 전체로 넓어진다 — 다시 넣지 마라.

INPUT=$(cat)

# 명령 문자열 추출 후 "명령 경계" 기준 매칭 — 문자열 시작·;·&·|·(·줄바꿈(\n)·\r·\t 뒤의 실제 `git … push`만.
# ★경계에 \\n 필수 — 여러 줄 명령(heredoc 뒤 git push)은 JSON에서 `…\ngit push`가 되어, 없으면 침묵한다(실측).
# 대소문자 무시(-i) — PowerShell은 `Git Push`도 실행한다.
CMD=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)/\1/p')
printf '%s' "$CMD" | grep -Eiq '(^|[;&|(]|\\n|\\r|\\t)[[:space:]]*git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$|"|\\)' || exit 0

# 원격 main 대비 변경 파일. 실패(=ref 없음·repo 밖)는 "모름" — 무출력으로 일반 권한 체계에 위임(allow 반환 = fail-open 금지).
# core.quotepath=false: 한글 경로가 8진 이스케이프로 나오면 앵커가 빗나간다(실측). diff.renames=false: rename이 도착 경로만
# 남아 공통 영역에서 "빼내는" 이동이 침묵한다(실측) — 원본·도착 둘 다 보이게 끈다.
CHANGED=$(git -c core.quotepath=false -c diff.renames=false diff --name-only origin/main...HEAD 2>/dev/null) || exit 0
[ -z "$CHANGED" ] && exit 0
CHANGED=$(printf '%s\n' "$CHANGED" | sed 's/^"//; s/"$//')

# 공통 영역 패턴 (프로젝트에 맞게 수정 — 가드 자신(.claude/)·lockfile·마이그레이션 전체·CI/컨테이너 설정 포함, 대소문자 무시)
HITS=$(printf '%s\n' "$CHANGED" | grep -iE '^(src/shared/|\.claude/|db/migrations/|CLAUDE\.md$|package\.json$|package-lock\.json$|\.gitlab-ci\.ya?ml$|docker-compose\.ya?ml$|Dockerfile$)|(^|/)middleware\.[a-z]+$' || true)
[ -z "$HITS" ] && exit 0

N=$(printf '%s\n' "$HITS" | grep -c .)
FILES=$(printf '%s\n' "$HITS" | head -5 | tr '\n' ' ' | sed 's/"/\\"/g')
[ "$N" -gt 5 ] && FILES="${FILES}외 $((N-5))건 "
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 공통 영역 변경이 포함된 push: %s— 팀 채팅에 공지했으면 승인하세요. (Show 등급: 공지는 알림이지 허락이 아님)"}}\n' "$FILES"
exit 0
# 알려진 한계(의도적 미해결): HEAD 아닌 refspec(git push origin other:main)은 HEAD 기준으로 오판할 수 있다.
