#!/usr/bin/env bash
# memory-size-warn.sh 회귀 시험 — `bash scripts/test-memory-size-warn.sh`
# 대조군(작은 목차 → 조용) 먼저, 그다음 줄 수·바이트 문턱, 목차 없음, 경로 계산(«/»→«-»). 어느 갈래든 종료 0 이어야 한다.
# 시험할 훅을 바꾸려면(유효성 증명): MEMORY_HOOK=/경로/가짜.sh bash scripts/test-memory-size-warn.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${MEMORY_HOOK:-$HERE/../.claude/hooks/memory-size-warn.sh}"
[ -f "$HOOK" ] || { echo "⛔ 없다: $HOOK — 테스트 실패가 아니라 미배포다."; exit 1; }
D=$(mktemp -d) || { echo "⛔ 임시폴더를 못 만들었다 — 검증 불능."; exit 1; }
pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }
run() { env "$@" bash "$HOOK" 2>&1; }

seq 1 10 > "$D/small.md"
OUT=$(run CLAUDE_MEMORY_INDEX="$D/small.md"); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok || no "작은 목차는 조용해야 한다(RC $RC): $OUT"

OUT=$(run CLAUDE_MEMORY_INDEX="$D/small.md" MEMORY_WARN_LINES=5); RC=$?
[ "$RC" = 0 ] && ok || no "줄 문턱 초과 종료코드 $RC"
case "$OUT" in *"10줄"*"memory-tidy.md"*) ok;; *) no "줄 문턱 초과 문구 없음: $OUT";; esac

OUT=$(run CLAUDE_MEMORY_INDEX="$D/small.md" MEMORY_WARN_BYTES=10); RC=$?
[ "$RC" = 0 ] && ok || no "바이트 문턱 초과 종료코드 $RC"
case "$OUT" in *"memory-tidy.md"*) ok;; *) no "바이트 문턱 초과 문구 없음: $OUT";; esac

seq 1 169 > "$D/edge.md"
OUT=$(run CLAUDE_MEMORY_INDEX="$D/edge.md" MEMORY_WARN_BYTES=999999); [ -z "$OUT" ] && ok || no "169줄은 조용해야 한다: $OUT"
seq 1 170 > "$D/edge.md"
OUT=$(run CLAUDE_MEMORY_INDEX="$D/edge.md" MEMORY_WARN_BYTES=999999); [ -n "$OUT" ] && ok || no "170줄은 알려야 한다"

OUT=$(run CLAUDE_MEMORY_INDEX="$D/없는파일.md"); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok || no "목차가 없으면 조용히 종료 0 이어야 한다(RC $RC): $OUT"

# 경로 계산: 프로젝트 경로의 «/» 를 «-» 로 바꾼 이름의 메모리 폴더를 본다
mkdir -p "$D/home/.claude/projects/-tmp-proj-x/memory"
seq 1 200 > "$D/home/.claude/projects/-tmp-proj-x/memory/MEMORY.md"
OUT=$(env HOME="$D/home" CLAUDE_PROJECT_DIR=/tmp/proj/x bash "$HOOK" 2>&1); RC=$?
[ "$RC" = 0 ] && ok || no "경로 계산 종료코드 $RC"
case "$OUT" in *"200줄"*) ok;; *) no "경로 계산: 200줄 목차를 못 찾았다: $OUT";; esac
OUT=$(env HOME="$D/home" CLAUDE_PROJECT_DIR=/tmp/proj/other bash "$HOOK" 2>&1)
[ -z "$OUT" ] && ok || no "다른 프로젝트 경로는 조용해야 한다: $OUT"

# 숫자가 아닌·음수 문턱은 기본값(170줄)으로: stderr 오류 없이 종료 0, 10줄 목차는 조용
for bad in abc -1 0 ""; do
  OUT=$(run CLAUDE_MEMORY_INDEX="$D/small.md" MEMORY_WARN_LINES="$bad" MEMORY_WARN_BYTES="$bad"); RC=$?
  [ "$RC" = 0 ] && [ -z "$OUT" ] && ok || no "잘못된 문턱 «${bad}» 는 기본값이어야 한다(RC $RC): $OUT"
done

rm -r "$D"
echo "통과 $pass / 실패 $fail"
[ "$fail" -eq 0 ] && [ "$pass" -ge 15 ]
