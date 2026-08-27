#!/usr/bin/env bash
# session-guard 훅 회귀 테스트 — `bash scripts/test-session-guard.sh`
# 왜 있나: 이 훅은 **경고 전용**이라 조용히 죽어도 아무도 모른다(무음 = 통과처럼 보인다).
#   check-push.sh 와 같은 규약을 지키는지(ask 아니면 무음·비정상 종료 금지)와,
#   ①SessionStart 점유 감지 ②남의 폴더 HEAD 이동 감지가 실제로 켜지는지를 케이스로 고정한다.
# ★격리 저장소에서 돌린다 — 현재 체크아웃 상태에 좌우되면 브랜치마다 결과가 달라진다
#   (test-check-push.sh 가 그걸로 브랜치 42/47 vs main 47/47 을 낸 실측이 있다).
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/session-guard.sh"
pass=0; fail=0
command -v git >/dev/null 2>&1 || { echo "⛔ git 이 없다 — 이 회귀 테스트는 git 이 있어야 성립한다"; exit 1; }
TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT
TAB=$(printf '\t')

mkrepo() { # $1=이름 → repo 경로
  R="$TMPROOT/$1"; mkdir -p "$R/.claude"; ( cd "$R"
    git init -q -b main . && git config user.email t@example.com && git config user.name t
    echo x > README.md && git add -A && git commit -qm base ) >/dev/null 2>&1
  printf '%s' "$R"
}
MINE=$(mkrepo mine); OTHER=$(mkrepo other)

# 살아있는 '남의 세션'을 흉내낸다 — 오래 자는 프로세스의 pid 를 남의 클론 lock 에 심는다.
sleep 300 & GHOST=$!
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$OTHER" > "$OTHER/.claude/.session-lock"
# 죽은 세션 항목도 하나 — 청소돼야 한다
printf '%s\t%s\t%s\t%s\n' "999999" "dead/x" "2020-01-01 00:00" "$OTHER" >> "$OTHER/.claude/.session-lock"

t() { # $1=ASK|SILENT  $2=기대 조각(-면 무시)  $3=명령
  OUT=$(CLAUDE_PROJECT_DIR="$MINE" printf '{"tool_input":{"command":"%s"}}' "$3" \
        | CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" 2>/dev/null); RC=$?
  if [ "$RC" -ne 0 ]; then echo "FAIL(exit $RC): $3"; fail=$((fail+1)); return; fi
  case "$OUT" in *'"permissionDecision":"allow"'*|*'"permissionDecision":"deny"'*)
    echo "FAIL(철칙 위반 — ask 아님): $3"; fail=$((fail+1)); return;; esac
  if [ "$1" = SILENT ]; then
    [ -z "$OUT" ] && { pass=$((pass+1)); return; }
    echo "FAIL(뜨면 안 되는데 뜸): $3 → $OUT"; fail=$((fail+1)); return
  fi
  if printf '%s' "$OUT" | grep -q "$2"; then pass=$((pass+1)); else
    echo "FAIL(안 뜸/딴 판정 — 기대 '$2'): $3 → ${OUT:-무음}"; fail=$((fail+1)); fi
}

echo "── A. 남의 폴더 HEAD 이동 — 알려야 한다"
t ASK '남의 작업 폴더' "cd $OTHER \&\& git checkout main"
t ASK '남의 작업 폴더' "cd $OTHER \&\& git switch -c feature/y"
t ASK '남의 작업 폴더' "cd $OTHER \&\& git pull origin main"
t ASK '남의 작업 폴더' "git -C $OTHER reset --hard origin/main"

echo "── B. 조용해야 하는 것"
t SILENT - "cd $MINE \&\& git checkout main"                 # 내 repo = ①이 담당
t SILENT - "cd $OTHER \&\& git log --oneline -5"             # HEAD 안 옮김
t SILENT - "cd $OTHER \&\& git status"                       # 〃
t SILENT - "cd $OTHER \&\& npm test"                         # git 아님
t SILENT - "echo git checkout main"                          # 명령 경계 밖(인자)

echo "── C. 점유가 없으면 조용 (죽은 항목만 남은 경우)"
printf '%s\t%s\t%s\t%s\n' "999998" "dead/y" "2020-01-01 00:00" "$OTHER" > "$OTHER/.claude/.session-lock"
t SILENT - "cd $OTHER \&\& git checkout main"
[ -s "$OTHER/.claude/.session-lock" ] && { echo "FAIL(죽은 항목이 안 치워짐)"; fail=$((fail+1)); } || pass=$((pass+1))
# 되돌려 놓는다
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$OTHER" > "$OTHER/.claude/.session-lock"

echo "── D. SessionStart 등록·점유 경고"
OUT=$(CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" register 2>/dev/null); RC=$?
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && pass=$((pass+1)) || { echo "FAIL(빈 클론 첫 세션은 조용해야: rc=$RC out=$OUT)"; fail=$((fail+1)); }
[ -s "$MINE/.claude/.session-lock" ] && pass=$((pass+1)) || { echo "FAIL(등록이 안 됨)"; fail=$((fail+1)); }
# 남의 세션이 이미 있는 클론에서 시작하면 경고
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$MINE" >> "$MINE/.claude/.session-lock"
OUT=$(CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" register 2>/dev/null); RC=$?
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '다른 세션'; } && pass=$((pass+1)) || { echo "FAIL(점유 경고 안 뜸): ${OUT:-무음}"; fail=$((fail+1)); }
# 재진입(같은 세션이 SessionStart 를 또 겪음 — compact 등)에 중복 등록되지 않는다
N1=$(grep -c . "$MINE/.claude/.session-lock"); CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" register >/dev/null 2>&1
N2=$(grep -c . "$MINE/.claude/.session-lock")
[ "$N1" = "$N2" ] && pass=$((pass+1)) || { echo "FAIL(재진입에 중복 등록: $N1 → $N2)"; fail=$((fail+1)); }

echo "── E. 이상 입력 (fail-silent)"
OUT=$(printf '' | bash "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(빈 입력)"; fail=$((fail+1)); }
OUT=$(printf 'not json' | bash "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(비 JSON)"; fail=$((fail+1)); }
OUT=$(printf '{"tool_input":{"command":"cd /nope/nope && git checkout main"}}' | CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(없는 경로)"; fail=$((fail+1)); }

kill "$GHOST" 2>/dev/null
echo "──────── $pass OK / $fail FAIL"
[ "$fail" -eq 0 ] || exit 1
