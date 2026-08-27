#!/usr/bin/env bash
# 배포처 여러 곳을 **한 번에** 승인·머지 — `bash approve-all.sh <repo경로> <MR번호> [<repo경로> <MR번호> ...]`
# 왜 있나: approve-mr.sh 를 배포처마다 한 줄씩 치게 하면 오너가 같은 명령을 두 번 친다(2026-08-27 지적).
#   한 곳이 실패해도 나머지는 계속 돌리고, 끝에 한 번에 결과를 보여준다(중간에 죽으면 뭘 했는지 모른다).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 2 ] || { echo "⛔ 인자: <repo경로> <MR번호> 쌍을 하나 이상"; exit 2; }
RESULT=""; FAIL=0
while [ $# -ge 2 ]; do
  REPO="$1"; MR="$2"; shift 2
  NAME=$(basename "$REPO")
  echo; echo "════════ $NAME  !$MR ════════"
  if bash "$HERE/approve-mr.sh" "$REPO" "$MR"; then
    RESULT="$RESULT
  ✅ $NAME !$MR — 머지·main 종결초록"
  else
    RESULT="$RESULT
  ⛔ $NAME !$MR — 실패(위 로그 확인)"; FAIL=1
  fi
done
echo; echo "════════ 전체 결과 ════════$RESULT"
[ "$FAIL" -eq 0 ] || exit 1
