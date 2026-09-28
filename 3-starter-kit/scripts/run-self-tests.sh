#!/bin/bash
# 검사기 자기시험(scripts/test-*.sh)을 전부 돈다 — CI `self-tests` 잡과 로컬 `/done` 3단계가 같은 것을 부른다.
# 저장소 루트에서: bash scripts/run-self-tests.sh
# 종료 0 = 전부 통과 · 1 = 실패한 시험 있음 · 2 = 돌 시험이 없다(자리를 잘못 잡았다 — 초록 아님)
cd "$(dirname "$0")/.." || exit 2
RC=0
N=0
FAILED=""
for t in scripts/test-*.sh; do
  [ -f "$t" ] || continue
  N=$((N + 1))
  echo "════════ $t"
  if ! bash "$t"; then
    RC=1
    FAILED="$FAILED $t"
  fi
done
if [ "$N" = 0 ]; then
  echo "⛔ 돌 자기시험이 0개 — 저장소 루트가 맞나? (판정 불능)"
  exit 2
fi
if [ "$RC" = 0 ]; then
  echo "자기테스트 ${N}개 전부 통과"
else
  echo "⛔ 실패한 자기테스트:$FAILED"
  echo "   울타리(샌드박스) 안에서만 실패하면 거짓 실패일 수 있다 — 울타리 밖에서 다시 돌려 갈라라."
fi
exit $RC
