#!/usr/bin/env bash
# check-deferred.sh 의 회귀 테스트 — git 픽스처로 «번호 없는 미룸»을 잡는지 고정한다.
# ★이 파일의 존재 이유 = C 다. 「범위 밖(후속): A(#1) · B」처럼 **한 줄에 카드 하나만 달고 나머지를 흘리는** 모양이
#   실제 사고(2026-09-17 bnsone)라, 줄 단위로 `#숫자` 를 찾는 잣대로 바꾸면 C 가 FAIL 해야 한다.
# ★픽스처는 반드시 임시 폴더에서 돈다 — 저장소 루트에서 `git init`·커밋이 새면 실사고다(2026-09-09).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/check-deferred.sh"
OK=0; FAIL=0

[ -f "$TOOL" ] || { echo "⛔ 검사기가 없다: $TOOL"; exit 1; }
command -v python3 >/dev/null 2>&1 || {
  echo "⛔ python3 이 없다 — 이 시험은 python3 이 있어야 성립한다(«건너뜀»이 아니라 실패다)."; exit 1; }

TMP="${TMPDIR:-/tmp}/cdef.$$"; mkdir -p "$TMP" || { echo "⛔ 임시 폴더를 못 만든다: $TMP"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
touch "$TMP/.w" 2>/dev/null || { echo "⛔ 임시 폴더에 못 쓴다 — 울타리 안에서는 여기서 돌리지 마라"; exit 1; }

N=0
# 픽스처: 번호 없는 옛 미룸 한 줄이 이미 main 에 있다(F 케이스용). origin/main 을 그 자리에 세운다.
setup() {
  N=$((N+1)); R="$TMP/r$N"
  mkdir -p "$R/docs/03_Requirement" "$R/docs/00_Guide" "$R/docs/adr" || return 1
  cd "$R" || return 1
  git init -q -b main . 2>/dev/null || return 1
  git config user.email t@t; git config user.name t
  printf '# 요약\n\n- 옛 줄: 정산은 후속 카드로 뺀다.\n' > docs/03_Requirement/_digest.md
  printf '# 요구\n\n- 원문\n' > docs/03_Requirement/Req.md
  git add docs >/dev/null; git commit -q -m base
  git update-ref refs/remotes/origin/main HEAD
}
add() { # $1=파일 $2=더할 줄 — 브랜치 커밋으로 남긴다
  ( cd "$R" || exit 9; printf '%s\n' "$2" >> "$1"; git add "$1" >/dev/null; git commit -q -m t ) || return 1
}
run() { ( cd "$R" || exit 9; bash "$TOOL" "$@" > "$TMP/out" 2>&1; echo $? ); }
runsub() { S="$1"; shift; ( cd "$R/$S" || exit 9; bash "$TOOL" "$@" > "$TMP/out" 2>&1; echo $? ); }
ck() { # $1=설명 $2=기대 exit $3=실제 exit
  if [ "$2" = "$3" ]; then OK=$((OK+1))
  else FAIL=$((FAIL+1)); echo "  ⛔ $1"; echo "     기대 exit: $2 / 실제: $3"; sed 's/^/       /' "$TMP/out" | head -8; fi
}
has() { # $1=설명 $2=출력에 있어야 할 문자열
  if grep -qF -- "$2" "$TMP/out"; then OK=$((OK+1)); else FAIL=$((FAIL+1)); echo "  ⛔ $1 — 출력에 '$2' 없음"; fi
}

echo "── A. 번호 없는 미룸을 더하면 잡는다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/03_Requirement/_digest.md "- 엑셀 내보내기는 별도 카드로 한다."
ck "A1 exit 1" "1" "$(run)"
has "A2 파일:줄 을 짚는다" "docs/03_Requirement/_digest.md:4:"

echo "── B. 번호를 달면 통과한다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/03_Requirement/_digest.md "- 엑셀 내보내기는 별도 카드(#42)로 한다."
ck "B1 exit 0" "0" "$(run)"

echo "── C. ★한 줄에 카드 하나만 달고 나머지를 흘리면 잡는다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/03_Requirement/_digest.md "- **범위 밖(후속)**: 자동 채움(A-03 — #280) · 의견(#279) · 목록 필터(기간·검색)."
ck "C1 exit 1" "1" "$(run)"
has "C2 빠진 조각을 짚는다" "목록 필터"

echo "── D. «카드 불요»는 사유가 있어야 인정한다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/adr/0001-x.md "- 로그 보관은 후속 작업 (카드 불요: 운영팀 몫이다)."
ck "D1 사유 있으면 exit 0" "0" "$(run)"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/adr/0001-x.md "- 로그 보관은 후속 작업 (카드 불요:)."
ck "D2 사유 없으면 exit 1" "1" "$(run)"

echo "── E. 기획자 원문·안내문·마찰 기록은 대상이 아니다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/03_Requirement/Req.md "- 정산은 후속 카드로 뺀다."
add docs/00_Guide/Guide.md "- 큰 일은 별도 카드로 나눠라."
add docs/friction.md "2026-09-17 /dev — 후속 카드로 뺐다"
ck "E1 exit 0" "0" "$(run)"
has "E2 대상 0개로 찍는다(조용한 통과가 아니다)" "파일 0개"

echo "── F. 옛 부채는 «더한 줄» 검사에선 안 막고, --all 에선 나온다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/03_Requirement/_digest.md "- 새 줄: 문구 정리."
ck "F1 diff 모드 exit 0" "0" "$(run)"
ck "F2 --all exit 1" "1" "$(run --all)"
has "F3 옛 줄을 짚는다" "_digest.md:3:"

echo "── G. 업무 용어의 «범위 밖»은 미룸이 아니다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/03_Requirement/_digest.md "- 조회 범위 밖 일정은 목록에 안 나온다."
ck "G1 exit 0" "0" "$(run)"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/03_Requirement/_digest.md "- 의견 수정은 이번 범위 밖이다."
ck "G2 «이번 범위 밖»은 exit 1" "1" "$(run)"

echo "── H. 못 재면 «판정 불능»(2)이다 — 통과가 아니다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
add docs/03_Requirement/_digest.md "- 엑셀은 별도 카드로."
ck "H1 하위 폴더에서 돌면 exit 2" "2" "$(runsub docs)"
ck "H2 기준 ref 가 없으면 exit 2" "2" "$(run origin/없는가지)"

echo "──── 결과: ${OK} OK / ${FAIL} FAIL"
[ "$FAIL" = 0 ]
