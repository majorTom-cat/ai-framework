#!/usr/bin/env bash
# 배포처 여러 곳을 **한 번에** 승인·머지 — `bash approve-all.sh <repo경로> <MR번호> [<repo경로> <MR번호> ...]`
# 왜 있나: approve-mr.sh 를 배포처마다 한 줄씩 치게 하면 오너가 같은 명령을 두 번 친다(2026-08-27 지적).
#   한 곳이 실패해도 나머지는 계속 돌리고, 끝에 한 번에 결과를 보여준다(중간에 죽으면 뭘 했는지 모른다).
# ★2026-09-07: **순차 → 병렬**. 곳마다 CI 시간이 다른데(bnsone 10분 · 파일럿 2분) 순차로 돌리면
#   빠른 쪽이 느린 쪽을 그냥 기다린다 — 실측 22분 중 4분이 그 손해였다(오너 「너무 느린데」).
#   로그는 곳마다 파일로 받아 **끝난 순서가 아니라 준 순서대로** 출력한다(섞이면 못 읽는다).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 2 ] || { echo "⛔ 인자: <repo경로> <MR번호> 쌍을 하나 이상"; exit 2; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
NAMES=""; i=0
while [ $# -ge 2 ]; do
  REPO="$1"; MR="$2"; shift 2
  NAME=$(basename "$REPO")
  i=$((i+1))
  NAMES="$NAMES$i|$NAME|$MR
"
  # ★머지까지만 하고 돌려받는다 — main 초록은 아래에서 «전부 머지된 뒤» 한꺼번에 본다.
  ( SKIP_MAIN_WAIT=1 bash "$HERE/approve-mr.sh" "$REPO" "$MR" > "$TMP/$i.log" 2>&1; echo $? > "$TMP/$i.rc" ) &
done
echo "── ${i}곳을 동시에 돌린다(로그는 끝난 뒤 순서대로)"
wait

RESULT=""; FAIL=0
while IFS='|' read -r n NAME MR; do
  [ -z "${n:-}" ] && continue
  echo; echo "════════ $NAME  !$MR ════════"
  cat "$TMP/$n.log"
  if [ "$(cat "$TMP/$n.rc" 2>/dev/null)" = "0" ]; then
    RESULT="$RESULT
  ✅ $NAME !$MR — 머지됨"
  else
    RESULT="$RESULT
  ⛔ $NAME !$MR — 실패(위 로그 확인)"; FAIL=1
  fi
done <<< "$NAMES"

echo; echo "════════ 전체 결과 ════════$RESULT"
[ "$FAIL" -eq 0 ] || exit 1
echo
echo "※ main 파이프라인은 아직 도는 중이다 — 호출한 쪽(a.sh)이 뒤에서 확인하고 빨간불일 때만 알린다."
