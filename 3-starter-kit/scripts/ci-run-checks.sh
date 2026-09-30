#!/usr/bin/env bash
# 가벼운 검사 여러 개를 «잡 하나»에서 차례로 돌린다.
# 사용: bash scripts/ci-run-checks.sh <검사이름>...   → 검사마다 `scripts/ci-job-<검사이름>.sh` 를 실행
#
# 왜 묶나: 공용 러너는 동시 실행 자리가 한정돼 있다. 10~80초짜리 검사가 잡마다 자리를 따로 잡으면(파드 기동·패키지
#   설치를 잡마다 되풀이) MR 둘만 겹쳐도 무거운 검사가 그 뒤에 줄을 선다. 검사 «내용»은 그대로 두고 «자리»만 합친다.
# 하나가 실패해도 **나머지를 끝까지 돈다** — 앞에서 멈추면 뒤 검사의 결과를 다음 파이프라인에서야 보고,
#   고칠 때마다 한 바퀴씩 더 돈다(묶기 전에는 잡마다 따로 빨개졌으니 한 번에 다 보였다).
# 끝에 «어느 검사가 실패했나»를 이름으로 찍는다 — 잡 이름 하나로는 무엇이 깨졌는지 안 보인다.
# 종료코드: 0 = 전부 통과 · 1 = 하나 이상 실패 · 2 = 호출이 잘못됨(인자 없음·없는 검사 이름)
#   없는 이름은 «건너뜀»이 아니라 실패다 — 오타 하나로 검사가 조용히 빠지는 것이 이 묶음의 가장 큰 위험이다.
# 묶는 기준(`.gitlab-ci.yml` 이 지킨다): 같은 이미지 · 같은 rules · 같은 차단 여부. `allow_failure` 는 잡 단위라
#   차단형과 경고형을 한 잡에 섞으면 차단형 실패가 경고로 묻힌다. 자기시험 = scripts/test-ci-run-checks.sh

set -u
cd "$(dirname "$0")/.." || exit 2

if [ "$#" -eq 0 ]; then
  echo "⛔ 돌릴 검사 이름이 없다 — 사용: bash scripts/ci-run-checks.sh <검사이름>..."
  exit 2
fi

for name in "$@"; do
  if [ ! -f "scripts/ci-job-$name.sh" ]; then
    echo "⛔ 없는 검사: $name (scripts/ci-job-$name.sh 없음) — 아무것도 돌리지 않고 멈춘다"
    exit 2
  fi
done

FAILED=""
PASSED=""
for name in "$@"; do
  echo ""
  echo "════════ [$name] 시작 ════════"
  # 검사마다 작업 폴더를 따로 준다(CHECK_WORK) — 중간 파일이 필요한 검사는 저장소 루트가 아니라 여기에 쓴다.
  #   한 폴더를 같이 쓰면 같은 이름의 중간 파일을 뒤 검사가 읽는 교차 오염이 생긴다.
  WORK=$(mktemp -d) || { echo "⛔ 임시 폴더를 못 만들었다"; exit 2; }
  # 서브셸로 격리 — 검사 안의 `exit` 가 이 실행기를 끝내지 않게 한다.
  ( CHECK_WORK="$WORK" bash "scripts/ci-job-$name.sh" )
  rc=$?
  rm -rf "$WORK"
  if [ "$rc" -eq 0 ]; then
    echo "════════ [$name] ✅ 통과 ════════"
    PASSED="$PASSED $name"
  else
    echo "════════ [$name] ⛔ 실패 (종료코드 $rc) ════════"
    FAILED="$FAILED $name"
  fi
done

echo ""
echo "──────── 묶음 결과 ────────"
echo "통과:${PASSED:- 없음}"
echo "실패:${FAILED:- 없음}"
if [ -n "$FAILED" ]; then
  echo "⛔ 위 «실패» 검사의 로그 구간([이름] 시작 ~ 실패)을 보라."
  exit 1
fi
exit 0
