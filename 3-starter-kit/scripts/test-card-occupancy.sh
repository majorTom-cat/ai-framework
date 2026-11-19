#!/usr/bin/env bash
# card-occupancy.cjs(카드 점유 대조기) 회귀 테스트 — `bash scripts/test-card-occupancy.sh`
# 왜 있나: 착수·권유 전에 «이미 다른 작업 폴더·브랜치가 그 카드를 잡았나»를 기계로 가르는지 센다 — 놓치면 같은 카드에 세션이 둘 붙는다(배포처 bnsone #1344).
# 시험할 도구를 바꾸려면(유효성 증명용): OCC_TOOL=/경로/가짜.cjs bash scripts/test-card-occupancy.sh
set -u
TOOL="${OCC_TOOL:-$(cd "$(dirname "$0")" && pwd)/card-occupancy.cjs}"
[ -f "$TOOL" ] || { echo "⛔ 도구가 없다: $TOOL — 테스트 실패가 아니라 미배포다."; exit 1; }
node -e '0' >/dev/null 2>&1 || { echo "⛔ node 가 실행되지 않는다 — 검증 불능(합격 아님)."; exit 1; }
pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }

WT='worktree /r/bnsone
HEAD abc
branch refs/heads/main

worktree /r/issue-1344
HEAD def
branch refs/heads/fix/1344-m09-5-job-history

worktree /r/issue-13440
HEAD 123
branch refs/heads/feature/13440-other'
RM=$'aaa\trefs/heads/main\nbbb\trefs/heads/feature/12-login\nccc\trefs/heads/feature/112-x\nddd\trefs/heads/fix/1234-y'
fake() { node -e 'process.stdout.write(JSON.stringify({worktree:process.argv[1],remote:process.argv[2]}))' "$1" "$2"; }

# 1) 워크트리로 점유 → 1, 13440 은 안 걸린다
OUT=$(CARD_OCC_FAKE="$(fake "$WT" "$RM")" node "$TOOL" 1344); RC=$?
[ "$RC" = 1 ] && ok || no "워크트리 점유인데 종료 $RC"
printf '%s\n' "$OUT" | grep -q $'^워크트리\t/r/issue-1344\tfix/1344-m09-5-job-history' && ok || no "issue-1344 를 못 잡음: $OUT"
printf '%s\n' "$OUT" | grep -q '13440' && no "13440 을 1344 로 셌다" || ok

# 2) 원격 브랜치로 점유 → 1, 112·1234 는 안 걸린다
OUT=$(CARD_OCC_FAKE="$(fake "$WT" "$RM")" node "$TOOL" 12); RC=$?
[ "$RC" = 1 ] && ok || no "원격 브랜치 점유인데 종료 $RC"
printf '%s\n' "$OUT" | grep -q $'^원격 브랜치\tfeature/12-login' && ok || no "feature/12-login 을 못 잡음: $OUT"
printf '%s\n' "$OUT" | grep -q '112-x\|1234-y' && no "112·1234 를 12 로 셌다" || ok

# 3) 신호 없음 → 0
OUT=$(CARD_OCC_FAKE="$(fake "$WT" "$RM")" node "$TOOL" 777); RC=$?
[ "$RC" = 0 ] && ok || no "신호 없는데 종료 $RC"
case "$OUT" in *"점유 신호 0건 · 조회실패 0건"*) ok;; *) no "요약이 틀림: $OUT";; esac

# 4) 조회 실패 → 2 (점유 신호가 있어도 실패가 이긴다 — «없음»으로 읽히면 안 된다)
OUT=$(CARD_OCC_FAKE='{"worktree":"fail","remote":""}' node "$TOOL" 777); RC=$?
[ "$RC" = 2 ] && ok || no "워크트리 조회 실패인데 종료 $RC"
OUT=$(CARD_OCC_FAKE="$(fake "$WT" fail)" node "$TOOL" 1344); RC=$?
[ "$RC" = 2 ] && ok || no "원격 조회 실패인데 종료 $RC"
printf '%s\n' "$OUT" | grep -q $'^조회실패\t원격 브랜치' && ok || no "조회실패 줄이 없다: $OUT"

# 5) 번호가 아니면 2
node "$TOOL" abc >/dev/null 2>&1; RC=$?
[ "$RC" = 2 ] && ok || no "번호 아닌 인자인데 종료 $RC"

echo "card-occupancy: 통과 $pass · 실패 $fail"
[ "$fail" = 0 ]
