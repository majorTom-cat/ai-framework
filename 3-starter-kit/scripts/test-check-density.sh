#!/usr/bin/env bash
# check-density 회귀 테스트 — `bash scripts/test-check-density.sh`
# 왜 있나: 다른 검사기 3개(check-push·session-guard·tamper)엔 회귀 테스트가 있는데 이것만 없었다.
#   그 사이 «한글을 바이트로 세는» 결함이 오래 살아 있었다(맥 awk: 한글 10자 → 30) — 상한이 3배 엄해져
#   지킬 수 없는 줄이 "옛 초과"로 쌓였고, 아무도 그 숫자를 의심하지 않았다(2026-08-27 bnsone 세션 발견).
# ★격리 저장소에서 돌린다 — 이 repo 에서 그냥 돌리면 현재 체크아웃 상태에 결과가 좌우된다.
set -u
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-density.sh"
pass=0; fail=0
# ★검사기 자체가 없으면 전 케이스가 exit 127 로 무더기 FAIL 이 된다 — "미배포"라고 말하고 끝낸다.
[ -f "$SCRIPT" ] || { echo "⛔ 검사기가 없다: $SCRIPT"; echo "   킷의 scripts/check-density.sh 를 복사한 뒤 다시 돌려라."; exit 1; }
command -v git >/dev/null 2>&1 || { echo "⛔ git 이 없다 — base 비교(건드린 줄만 막기)가 성립하지 않는다"; exit 1; }

TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT
R="$TMPROOT/repo"; mkdir -p "$R/.claude/skills/x" "$R/.claude/rules"
( cd "$R" && git init -q -b main . && git config user.email t@example.com && git config user.name t ) >/dev/null 2>&1

ko() { # $1=글자수 → 한글 그만큼
  awk -v n="$1" 'BEGIN{ s=""; for(i=0;i<n;i++) s=s "가"; print s }'
}
en() { awk -v n="$1" 'BEGIN{ s=""; for(i=0;i<n;i++) s=s "a"; print s }'; }

commit_base() { ( cd "$R" && git add -A && git commit -qm base && git update-ref refs/heads/main HEAD ) >/dev/null 2>&1; }
run() { ( cd "$R" && bash "$SCRIPT" 2>&1 ); }
rc()  { ( cd "$R" && bash "$SCRIPT" >/dev/null 2>&1; echo $? ); }

t() { # $1=기대(OK|FAIL)  $2=설명  [$3=출력에 있어야 할 조각]
  local got; got=$(rc)
  local want=0; [ "$1" = FAIL ] && want=1
  if [ "$got" != "$want" ]; then echo "FAIL(종료코드 $got, 기대 $want): $2"; fail=$((fail+1)); return; fi
  if [ -n "${3:-}" ]; then
    if ! run | grep -q "$3"; then echo "FAIL(출력에 '$3' 없음): $2 →"; run | head -4; fail=$((fail+1)); return; fi
  fi
  pass=$((pass+1))
}

echo "── A. 한글은 글자로 센다 (바이트로 세면 3배 엄해진다)"
# ★경계 주의: 한글 100자 = 정확히 300바이트라 옛(바이트) 판에서도 «초과 아님»이 된다 — 케이스가 무력해진다.
#   반드시 100자를 넘겨서(=300바이트 초과) 잡아야 옛 결함이 실제로 FAIL 로 드러난다.
ko 250 > "$R/CLAUDE.md"; commit_base            # 250자 = 750바이트 — 글자 기준으론 상한 300 이내
t OK "한글 250자는 상한 300 이내다(바이트로 세면 750으로 잡혀 FAIL 난다)"
ko 250 >> "$R/CLAUDE.md"                        # 건드린 줄로 추가
t OK "새로 추가한 한글 250자 줄도 통과"

# ★옛(바이트) 검사기의 경계를 정확히 찌르는 케이스 — 한글 101자 = 303바이트.
#   100자(=300바이트)는 옛 판도 «초과 아님»이라 판별력이 없다. 101자여야 옛 FAIL / 새 PASS 로 갈린다.
ko 101 >> "$R/CLAUDE.md"
t OK "한글 101자(=303바이트) — 옛 바이트 계수였다면 여기서 걸린다"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :

echo "── A2. 다른 문자 폭도 글자로 센다 (bnsone 케이스 수용)"
awk 'BEGIN{s="";for(i=0;i<200;i++)s=s "\360\237\230\200";print s}' >> "$R/CLAUDE.md"   # 이모지 200자 = 800바이트
t OK "이모지 200자(800바이트)는 통과"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :
awk 'BEGIN{s="";for(i=0;i<125;i++)s=s "가a";print s}' >> "$R/CLAUDE.md"                    # 혼합 250자 = 500바이트
t OK "한글+ASCII 혼합 250자(500바이트)는 통과"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :
en 300 >> "$R/CLAUDE.md"
t OK "ASCII 300자 — 경계 이내는 통과"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :
: > "$R/CLAUDE.md"
t OK "빈 파일도 조용히 통과"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :

echo "── B. 진짜 초과는 막는다"
ko 301 >> "$R/CLAUDE.md"
t FAIL "한글 301자 줄은 막는다" "이번에 건드린 줄이 300"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :

echo "── C. 영문도 같은 기준"
en 301 >> "$R/CLAUDE.md"
t FAIL "영문 301자 줄은 막는다"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :
en 299 >> "$R/CLAUDE.md"
t OK "영문 299자 줄은 통과"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :

echo "── D. 옛 초과는 알리되 막지 않는다"
ko 400 > "$R/CLAUDE.md"; commit_base            # 이미 커밋된 초과 줄
t OK "건드리지 않은 옛 초과 줄은 통과시킨다" "예전부터"

echo "── E. 스킬·규칙 파일은 500자"
ko 50 > "$R/CLAUDE.md"; ko 499 > "$R/.claude/skills/x/SKILL.md"; ko 499 > "$R/.claude/rules/y.md"; commit_base
t OK "스킬·규칙 499자는 통과"
ko 501 > "$R/.claude/skills/x/SKILL.md"
t FAIL "스킬 501자는 막는다" "500"
git -C "$R" checkout -q -- .claude 2>/dev/null || :
ko 501 > "$R/.claude/rules/y.md"
t FAIL "규칙 501자는 막는다" "500"
git -C "$R" checkout -q -- .claude 2>/dev/null || :

echo "── F. 줄 수 상한"
awk 'BEGIN{for(i=0;i<201;i++) print "가"}' > "$R/CLAUDE.md"
t FAIL "CLAUDE.md 201줄은 막는다(상한 200)" "상한 200"
git -C "$R" checkout -q -- CLAUDE.md 2>/dev/null || :

echo "── G. 대상 파일이 없으면 조용히 통과"
rm -rf "$R/.claude/skills/x" "$R/.claude/rules"; ko 10 > "$R/CLAUDE.md"; commit_base
t OK "대상이 없어도 종료 코드 0"

echo "──────── $pass OK / $fail FAIL"
[ "$fail" -eq 0 ] || exit 1
