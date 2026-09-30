#!/usr/bin/env bash
# 테스트 변조 감지: src와 test(또는 CI설정)를 같은 MR에서 동시 수정 → 검토 필요 (CI 묶음 잡 `mr-warnings` — 경고형)
# 종전 `.gitlab-ci.yml` `tamper-check` 잡의 본문을 그대로 옮겼다.
# 필요: bash git (GIT_DEPTH: 0 — 얕은 클론이면 origin/main 과의 merge base 가 없어 `git diff origin/main...HEAD` 가 fatal)
# `set -eo pipefail` — 러너가 인라인 스크립트에 걸던 설정이다. 파일로 옮기면 따라오지 않아 여기서 건다.
set -eo pipefail
git fetch -q origin main
CH=$(git diff --name-only origin/main...HEAD)
echo "변경 파일:"; echo "$CH"
# 테스트 감지는 파일명 기준 — 테스트가 src 안에 코로케이션되는 스택(Vitest 등)에서도 걸리게 (bnsone 실측 2026-07-29: '^test/'만으로는 src/**/*.test.ts가 영원히 미매칭)
# ★소스·테스트·CI설정을 서로 다른 축으로 분류한다. 예전엔 '^src/ 매칭 && 테스트 매칭'이라
#   src/foo.test.ts 한 파일이 두 조건을 혼자 만족시켜 평범한 TDD MR마다 경고가 떴다
#   (오탐 실측 2026-07-29 · 파일럿 #72). 오탐이 반복되면 경고가 무시되어 진짜 변조를 놓친다.
#   판정 논리 정본 = 파일럿 scripts/tamper-check.sh (테스트가 붙어 있는 파일판).
TEST_RE='\.test\.|\.spec\.|(^|/)tests?/|(^|/)__tests__/'
CI_RE='(^|/)\.gitlab-ci\.yml$|(^|/)\.gitlab/'
TESTS=$(echo "$CH" | grep -E "$TEST_RE" || true)
CICONF=$(echo "$CH" | grep -E "$CI_RE" | grep -vE "$TEST_RE" || true)
# 소스 = 테스트가 아닌 src 파일. 스택별 루트 소스(server.js·middleware.ts 등)는 /scaffold 가 여기 추가한다.
SRCS=$(echo "$CH" | grep -E '^src/' | grep -vE "$TEST_RE" || true)
# ★수집 설정 — 소스도 테스트도 아닌 사각지대(2026-08-26 신설). include 를 줄이면 **테스트 파일을
#   한 줄도 안 고치고 전부 끌 수 있다**. 스택마다 이름이 다르니 /scaffold 가 이 목록을 치환한다.
CFG_RE='(^|/)(vitest\.config\.[a-z]+|vitest\.workspace\.[a-z]+|jest\.config\.[a-z]+|package\.json)$'
CFG=$(echo "$CH" | grep -E "$CFG_RE" || true)
# ★2026-08-26 개정 — 두 층으로 나눈다(오너 결정).
#   ⓘ알림(NOTE, 통과): '동시 수정' 조합. 이건 우리 표준 작업 방식이기도 해서 빨간불로 두면
#      상시 실패가 된다(bnsone 실측: 최근 23건 중 14건 실패 → 아무도 안 봄 = 진짜 변조도 놓침).
#   ⛔의심(SUSPECT, 실패): 테스트 무력화 신호. 이쪽이 훨씬 정확하고, 지금까진 '소스를 안 건드린
#      경우'에만 돌아서 소스와 함께 테스트를 끄는 형태를 아예 못 봤다 — 그 공백도 함께 메운다.
NOTE=0
SUSPECT=0
# ⓪수집 설정 변경 — 수집 범위·테스트 명령이 바뀌면 의심(버전 올림 같은 무관한 변경은 안 걸린다)
if [ -n "$CFG" ]; then
  CFGHIT=$(git --literal-pathspecs diff --no-renames --unified=0 origin/main...HEAD -- $CFG \
    | grep -E '^[-+]' | grep -vE '^(\+\+\+|---)' \
    | grep -E 'include|exclude|testMatch|testPathIgnorePatterns|setupFiles|coverage|threshold|"test"[[:space:]]*:' || true)
  if [ -n "$CFGHIT" ]; then
    echo "⛔ 테스트 수집 설정이 바뀌었다 — 수집 범위를 줄여 테스트를 통째로 끈 게 아닌지 검토"
    echo "$CFGHIT" | head -10
    SUSPECT=1
  fi
fi
if [ -n "$SRCS" ] && [ -n "$TESTS" ]; then
  echo "ⓘ 소스와 테스트 동시 수정(정상 작업일 수 있음 — 기록만)"
  echo "  소스:"; echo "$SRCS" | sed 's/^/    /'
  echo "  테스트:"; echo "$TESTS" | sed 's/^/    /'
  NOTE=1
fi
# CI설정은 테스트와 별개 축으로 센다 — 한 덩어리로 세면 CI만 고쳐도 '테스트 동시 수정'으로 오탐난다.
if [ -n "$CICONF" ] && [ -n "$TESTS" ]; then
  echo "ⓘ CI설정과 테스트 동시 수정(기록만) — 게이트를 무르게 하며 테스트를 고친 게 아닌지는 리뷰가 본다"
  NOTE=1
fi
if [ -n "$SRCS" ] && [ -n "$CICONF" ]; then
  echo "ⓘ 소스와 CI설정 동시 수정(기록만)"
  NOTE=1
fi
# ⛔무력화 감지 — 테스트 파일이 바뀌었으면 **항상** 본다.
#   ·skip/only/todo 추가 = 어떤 경우든 의심(테스트를 끄는 행위 자체)
#   ·줄 삭제 = 소스·CI를 안 건드린 '테스트만 변경'일 때만 의심(리팩터링 중 줄 삭제는 정상)
#   테스트 '추가·보강'은 조용히 통과시킨다. ※공백 든 파일명은 파일럿 scripts/tamper-check.sh 판이 안전하다.
if [ -n "$TESTS" ]; then
  DIFF=$(git --literal-pathspecs diff --no-renames --unified=0 origin/main...HEAD -- $TESTS)
  DEL=$(echo "$DIFF" | grep -E '^-' | grep -vE '^--- ' || true)
  # skipIf(true)·runIf(false) 포함 — 조건을 상수로 박아 끄는 우회(조건부 자체는 관용구라 제외)
  OFF=$(echo "$DIFF" | grep -E '^\+' | grep -vE '^\+\+\+ ' | grep -E '(^|[^A-Za-z0-9_])(it|test|describe)(\.[A-Za-z]+)*\.(skip|only|todo|failing)[[:space:]]*[(<`.]|(^|[^A-Za-z0-9_])x(it|test|describe)[[:space:]]*\(|\.(skipIf[[:space:]]*\([[:space:]]*true|runIf[[:space:]]*\([[:space:]]*false)' || true)
  # 테스트 케이스 '순감소' — 제목 수정처럼 선언 1줄을 지우고 1줄 추가하는 것까지 걸리면 또 상시 경고가
  # 된다. 그래서 삭제 선언 수 > 추가 선언 수일 때만 본다(파일을 test/ 밖으로 옮겨 없애는 은닉이 이 형태).
  CASE_RE='(^|[^A-Za-z0-9_])(it|test|describe)(\.[A-Za-z]+)*[[:space:]]*[(<`]'
  DEL_CASES=$(echo "$DIFF" | grep -E '^-' | grep -vE '^--- ' | grep -cE "$CASE_RE" || true)
  ADD_CASES=$(echo "$DIFF" | grep -E '^\+' | grep -vE '^\+\+\+ ' | grep -cE "$CASE_RE" || true)
  if [ -n "$OFF" ]; then
    echo "⛔ 테스트에 skip/only/todo 추가 — 테스트 무력화가 아닌지 검토"
    SUSPECT=1
  fi
  if [ "$DEL_CASES" -gt "$ADD_CASES" ]; then
    echo "⛔ 테스트 케이스가 순감소했다 — 무력화·은닉이 아닌지 검토 (선언 삭제 $DEL_CASES · 추가 $ADD_CASES)"
    SUSPECT=1
  elif [ -z "$SRCS" ] && [ -z "$CICONF" ] && [ -n "$DEL" ]; then
    # 케이스 수는 그대로인데 줄만 지워진 것 = 단언 삭제이거나 리팩터링. 파일 규칙으로는 못 가르므로
    # 알림으로 남긴다(실질 판정은 /done 리뷰). 실패로 두면 테스트 정리 때마다 빨간불이라 원위치다.
    echo "ⓘ 테스트만 변경됐고 줄 삭제가 있다(케이스 수는 유지 — 기록만)"
    NOTE=1
  fi
fi
if [ "$SUSPECT" = "1" ]; then exit 1; fi
if [ "$NOTE" = "1" ]; then echo "동시 수정 알림만 — 무력화 신호 없음 · OK"; else echo "변조 의심 조합 아님 — OK"; fi
