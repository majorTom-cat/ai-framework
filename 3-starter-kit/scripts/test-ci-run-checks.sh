#!/usr/bin/env bash
# `scripts/ci-run-checks.sh`(가벼운 검사 묶음 실행기) 자기시험. CI `self-tests` 가 자동으로 줍는다.
#
# 이 실행기가 지켜야 하는 성질 넷 — 하나라도 깨지면 «묶었더니 검사가 조용히 빠졌다»가 된다:
#   ① 하나가 실패해도 **뒤 검사를 끝까지 돈다**(앞에서 멈추면 뒤 결과를 다음 파이프라인에서야 본다)
#   ② 하나라도 실패하면 종료 1 + 요약에 **그 이름**이 찍힌다
#   ③ 없는 이름·빈 인자는 종료 2 이고 **아무것도 안 돈다**(오타 하나로 검사가 빠지는 것을 막는다)
#   ④ 검사마다 작업 폴더(CHECK_WORK)가 따로다(같은 이름 중간 파일의 교차 오염 방지)
# 그리고 배선 대조 ⑤: `.gitlab-ci.yml` 이 부르는 이름 ↔ `scripts/ci-job-*.sh` 실물이 1:1 이고, 차단형·경고형 묶음이 안 섞인다
#   (실물은 있는데 어느 묶음도 안 부르면 그 검사는 **한 번도 안 돈다** — 잡을 지울 때 가장 흔한 사고다).
# ⑥ 잡 본문 파일은 `set -eo pipefail` 로 시작한다 — 인라인 CI 본문을 파일로 옮기면 러너가 걸던 그 설정이 빠진다.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
RUNNER="$ROOT/scripts/ci-run-checks.sh"
CI_YML="${1:-$ROOT/.gitlab-ci.yml}"   # 인자 = 대조할 CI 파일(돌연변이 시험용). 없으면 저장소의 것

# 묶음 잡의 차단 여부 — 새 묶음을 만들면 여기 한쪽에 넣어라(안 넣으면 ⑤가 빨개진다).
BLOCKING_JOBS="mr-checks repo-guards"
WARNING_JOBS="mr-warnings"

OK=0; FAIL=0
pass() { OK=$((OK+1)); }
fail() { FAIL=$((FAIL+1)); echo "  ⛔ FAIL: $1"; }

[ -f "$RUNNER" ] || { echo "⛔ 대상이 없다: $RUNNER"; exit 1; }
[ -f "$CI_YML" ] || { echo "⛔ CI 파일이 없다: $CI_YML — 판정 불능"; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts"
cp "$RUNNER" "$T/scripts/ci-run-checks.sh"
MARK="$T/marks"; mkdir -p "$MARK"

mk() { # mk <이름> <본문>
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/scripts/ci-job-$1.sh"
}
mk ok1   "touch '$MARK/ok1'; exit 0"
mk ok2   "touch '$MARK/ok2'; exit 0"
mk bad   "touch '$MARK/bad'; echo 깨짐; exit 3"
mk writer "echo x > \"\$CHECK_WORK/changed.txt\"; echo \"\$CHECK_WORK\" > '$MARK/writer-work'"
mk reader "echo \"\$CHECK_WORK\" > '$MARK/reader-work'; [ ! -e \"\$CHECK_WORK/changed.txt\" ] || { echo 앞 검사의 파일이 보인다; exit 1; }"
mk earlyexit "exit 0; touch '$MARK/never'"

run() { rm -f "$MARK"/*; OUT=$(bash "$T/scripts/ci-run-checks.sh" "$@" 2>&1); RC=$?; }

echo "── ① 실패 뒤에도 끝까지 돈다 · ② 실패 이름이 요약에"
run ok1 bad ok2
[ "$RC" = 1 ] && pass || fail "실패가 있는데 종료코드 $RC (기대 1)"
[ -e "$MARK/ok2" ] && pass || fail "실패 뒤 검사(ok2)가 안 돌았다 — 앞에서 멈췄다"
printf '%s\n' "$OUT" | grep -q '^실패: bad$' && pass || fail "요약 «실패:» 줄에 bad 만 정확히 찍혀야 한다"
printf '%s\n' "$OUT" | grep -q '^통과: ok1 ok2$' && pass || fail "요약 «통과:» 줄이 ok1 ok2 여야 한다"

echo "── 전부 통과면 0"
run ok1 ok2
[ "$RC" = 0 ] && pass || fail "전부 통과인데 종료코드 $RC"
printf '%s\n' "$OUT" | grep -q '^실패: 없음$' && pass || fail "전부 통과인데 «실패: 없음» 이 없다"

echo "── 앞 실패가 뒤 통과에 덮이면 안 된다 · 마지막만 실패해도 1"
run bad ok1
[ "$RC" = 1 ] && pass || fail "앞 실패가 뒤 통과에 덮였다(종료코드 $RC)"
run ok1 bad
[ "$RC" = 1 ] && pass || fail "마지막 실패인데 종료코드 $RC"

echo "── ③ 없는 이름·빈 인자는 2 이고 아무것도 안 돈다"
run ok1 없는검사 ok2
[ "$RC" = 2 ] && pass || fail "없는 이름인데 종료코드 $RC (기대 2)"
[ ! -e "$MARK/ok1" ] && pass || fail "없는 이름이 섞였는데 앞 검사가 돌았다 — 사전 확인이 없다"
run
[ "$RC" = 2 ] && pass || fail "인자 없음인데 종료코드 $RC (기대 2)"

echo "── 검사 안의 exit 가 실행기를 끝내지 않는다"
run earlyexit ok1
[ "$RC" = 0 ] && [ -e "$MARK/ok1" ] && pass || fail "검사 안 exit 가 실행기를 멈췄다(rc=$RC)"

echo "── ④ 검사마다 작업 폴더가 따로이고 끝나면 지워진다"
run writer reader
[ "$RC" = 0 ] && pass || fail "뒤 검사가 앞 검사의 중간 파일을 봤다(교차 오염): $OUT"
W=$(cat "$MARK/writer-work" 2>/dev/null)
[ -n "$W" ] && [ ! -e "$W" ] && pass || fail "작업 폴더(${W})가 안 지워졌다"
# 폴더가 «다른가»를 따로 단언한다 — 지우기만 믿으면, 한 폴더를 같이 쓰다 지우기가 빠지는 날 교차 오염이 된다.
R=$(cat "$MARK/reader-work" 2>/dev/null)
[ -n "$R" ] && [ "$W" != "$R" ] && pass || fail "두 검사가 같은 작업 폴더(${W})를 받았다"

echo "── ⑤ 배선 대조: .gitlab-ci.yml 이 부르는 이름 ↔ scripts/ci-job-*.sh 실물 · 차단형/경고형 분리"
# «글자가 있나»가 아니라 **script 줄 그 모양 그대로**를 본다 — 줄을 주석으로 막거나 뒤에 `|| true` 를 붙여도
#   글자는 남는다. 줄 전체가 `    - bash scripts/ci-run-checks.sh 이름…` 이어야 센다.
CALL_RE='^    - bash scripts/ci-run-checks\.sh( [a-z0-9-]+)+$'
CALLED=$(grep -aE "$CALL_RE" "$CI_YML" | sed 's/^    - bash scripts\/ci-run-checks\.sh //' | tr ' ' '\n' | sed '/^$/d' | sort)
LOOSE=$(grep -ac 'ci-run-checks\.sh [a-z]' "$CI_YML" || true)
STRICT=$(grep -acE "$CALL_RE" "$CI_YML" || true)
[ "$LOOSE" = "$STRICT" ] && pass || fail "ci-run-checks.sh 를 부르는 줄 ${LOOSE}개 중 정식 모양은 ${STRICT}개다 — 주석 처리됐거나 뒤에 무언가(|| true 등) 붙었다"
# 묶음 잡 블록: `이름:` 줄부터 다음 최상위 줄 전까지(주석 줄 제외)
# 블록 끝 = 0열의 «주석 아닌» 줄. 0열 주석에서 끊으면 그 뒤의 `allow_failure: true` 를 못 봐 차단형이 경고가 돼도 초록이다.
job_block() { awk -v j="$1:" '$0==j{f=1;next} f&&/^[^ #]/{exit} f' "$CI_YML" | grep -v '^[[:space:]]*#'; }
# 러너를 부르는 잡은 전부 BLOCKING_JOBS·WARNING_JOBS 중 한쪽에 분류돼 있어야 한다
BUNDLES=$(awk '/^[a-z][a-z0-9-]*:$/{j=substr($0,1,length($0)-1)} /^    - bash scripts\/ci-run-checks\.sh/{print j}' "$CI_YML" | sort -u)
[ -n "$BUNDLES" ] && pass || fail "러너를 부르는 잡을 하나도 못 찾았다 — 파싱이 깨졌다"
for job in $BUNDLES; do
  case " $BLOCKING_JOBS $WARNING_JOBS " in *" $job "*) pass ;; *) fail "묶음 잡 $job 이 차단형·경고형 어느 목록에도 없다(이 시험 머리에 분류해라)" ;; esac
done
for job in $BLOCKING_JOBS; do
  B=$(job_block "$job")
  [ -n "$B" ] && pass || fail "차단형 묶음 $job 을 CI 에서 못 찾았다"
  printf '%s\n' "$B" | grep -q 'allow_failure' && fail "차단형 묶음 $job 에 allow_failure 가 있다 — 안의 검사가 통째로 경고가 된다" || pass
done
for job in $WARNING_JOBS; do
  B=$(job_block "$job")
  [ -n "$B" ] && pass || fail "경고형 묶음 $job 을 CI 에서 못 찾았다"
  printf '%s\n' "$B" | grep -qE '^  allow_failure: true$' && pass || fail "경고형 묶음 $job 에 allow_failure: true 가 없다 — 경고 검사가 머지를 막는다"
done
EXIST=$(cd "$ROOT/scripts" && ls ci-job-*.sh 2>/dev/null | sed 's/^ci-job-//; s/\.sh$//' | sort)
NC=$(printf '%s\n' "$CALLED" | grep -c . || true)
[ "$NC" -ge 7 ] && pass || fail "CI 가 부르는 검사 이름을 ${NC}개밖에 못 읽었다 — 파싱이 깨졌거나 검사가 빠졌다(묶기 당시 7개)"
DUP=$(printf '%s\n' "$CALLED" | uniq -d)
[ -z "$DUP" ] && pass || fail "같은 검사를 두 묶음이 부른다: $DUP"
for n in $CALLED; do
  printf '%s\n' "$EXIST" | grep -qx "$n" && pass || fail "CI 가 부르는 $n 의 scripts/ci-job-$n.sh 가 없다(그 잡이 exit 2 로 죽는다)"
done
for n in $EXIST; do
  printf '%s\n' "$CALLED" | grep -qx "$n" && pass || fail "scripts/ci-job-$n.sh 를 어느 묶음도 안 부른다 — 이 검사는 한 번도 안 돈다"
done

echo "── ⑥ 잡 본문은 set -eo pipefail 로 시작한다"
for n in $EXIST; do
  head -12 "$ROOT/scripts/ci-job-$n.sh" | grep -qx 'set -eo pipefail' && pass || fail "scripts/ci-job-$n.sh 머리에 set -eo pipefail 이 없다 — 중간 명령이 실패해도 끝까지 가서 초록이 된다"
done

echo "────────  $OK OK / $FAIL FAIL"
[ "$FAIL" -eq 0 ]
