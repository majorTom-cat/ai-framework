#!/usr/bin/env bash
# check-append-only-git.sh 의 회귀 테스트 — git 픽스처로 «기준을 어디로 잡나»를 고정한다.
# ★이 파일의 존재 이유 = D 와 G 다. 둘은 **같은 픽스처**인데 기준 ref 만 다르다:
#   D(tip 기준) = exit 1 로 잡고 · G(merge base 기준) = exit 0 으로 **놓친다**.
#   즉 G 는 «잣대를 갈아 끼우면 검사가 죽는다»를 보여주는 돌연변이다 — 이게 초록이면 D 의 초록은 의미가 없다.
# ★픽스처는 반드시 임시 폴더에서 돈다 — 저장소 루트에서 `git init`·커밋이 새면 실사고다(2026-09-09).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/check-append-only-git.sh"
OK=0; FAIL=0

[ -f "$TOOL" ] || { echo "⛔ 검사기가 없다: $TOOL"; exit 1; }
command -v python3 >/dev/null 2>&1 || {
  echo "⛔ python3 이 없다 — 이 시험은 python3 이 있어야 성립한다(«건너뜀»이 아니라 실패다)."
  echo "   CI 라면 그 잡의 이미지에 python3 를 깔아라(킷 self-tests = alpine: \`apk add python3\`)."
  exit 1; }

TMP="${TMPDIR:-/tmp}/caog.$$"; mkdir -p "$TMP" || { echo "⛔ 임시 폴더를 못 만든다: $TMP"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
touch "$TMP/.w" 2>/dev/null || { echo "⛔ 임시 폴더에 못 쓴다 — 울타리 안에서는 여기서 돌리지 마라"; exit 1; }

N=0
# 픽스처: docs/friction.md 에 항목 2개 · refs/remotes/origin/main 을 그 자리에 세운다.
# ★`git init` 이 저장소 루트에 새지 않도록 **반드시 `cd … || return`** 으로 감싼다.
setup() {
  N=$((N+1)); R="$TMP/r$N"
  mkdir -p "$R/docs" || return 1
  cd "$R" || return 1
  git init -q -b main . 2>/dev/null || return 1
  git config user.email t@t; git config user.name t
  printf '# 마찰\n\n2026-09-01 /dev — 가\n2026-09-02 /fix — 나\n' > docs/friction.md
  git add docs/friction.md >/dev/null; git commit -q -m base
  git update-ref refs/remotes/origin/main HEAD
}
run() { ( cd "$R" || exit 9; bash "$TOOL" "$@" > "$TMP/out" 2>&1; echo $? ); }
ck() { # $1=설명 $2=기대 exit $3=실제 exit
  if [ "$2" = "$3" ]; then OK=$((OK+1))
  else FAIL=$((FAIL+1)); echo "  ⛔ $1"; echo "     기대 exit: $2 / 실제: $3"; sed 's/^/       /' "$TMP/out" | head -8; fi
}

echo "── A. 항목을 지우면 잡는다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
( cd "$R" || exit; printf '# 마찰\n\n2026-09-02 /fix — 나\n' > docs/friction.md )
ck "A1 삭제는 exit 1" "1" "$(run)"

echo "── B. 항목을 더하기만 하면 통과한다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
( cd "$R" || exit; printf '# 마찰\n\n2026-09-03 /dev — 새 줄\n2026-09-01 /dev — 가\n2026-09-02 /fix — 나\n' > docs/friction.md )
ck "B1 추가만 하면 exit 0" "0" "$(run)"

echo "── C. 보관 파일로 «옮긴» 것은 통과한다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
( cd "$R" || exit
  printf '# 마찰\n\n2026-09-02 /fix — 나\n' > docs/friction.md
  printf '# 보관\n\n2026-09-01 /dev — 가\n' > docs/friction-보관.md )
ck "C1 보관으로 옮기면 exit 0" "0" "$(run)"

echo "── D. ★실사고 모양 — 옛 사본을 갈아치우는 사이 남이 main 에 한 줄 넣었다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
( cd "$R" || exit
  BASE=$(git rev-parse HEAD)
  # 남이 main 에 한 줄 추가(= origin/main 이 앞서간다)
  printf '# 마찰\n\n2026-09-03 /fix — 남의 줄\n2026-09-01 /dev — 가\n2026-09-02 /fix — 나\n' > docs/friction.md
  git add docs/friction.md >/dev/null; git commit -q -m "남의 줄"
  git update-ref refs/remotes/origin/main HEAD
  # 나는 옛 사본을 편집해 내 가지에 통째로 올린다(API update = 갈아치우기)
  git checkout -q -b mine "$BASE"
  printf '# 마찰\n\n2026-09-01 /dev — 가(고침)\n2026-09-02 /fix — 나\n' > docs/friction.md
  git add docs/friction.md >/dev/null; git commit -q -m "내 편집" )
ck "D1 tip 기준이면 남의 줄이 사라진 것을 잡는다 (exit 1)" "1" "$(run)"
grep -q "남의 줄" "$TMP/out" || { FAIL=$((FAIL+1)); echo "  ⛔ D2 잃은 줄을 지목하지 못했다"; }
D_R="$R"   # G 에서 같은 픽스처를 재사용한다

echo "── G. ★돌연변이 — 같은 픽스처에 기준을 «merge base» 로 주면 **놓친다**"
# 이 케이스가 exit 1 을 내면 D 의 초록은 «기준이 tip 이라서»가 아니라 다른 이유였다는 뜻이다.
R="$D_R"
MB=$( cd "$R" && git merge-base HEAD origin/main )
ck "G1 merge base 기준이면 통과해 버린다 (exit 0 = 잣대가 살아 있다는 증명)" "0" "$(run "$MB")"

echo "── E. 기준 ref 가 없으면 «통과»가 아니라 «판정 불능»이다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
ck "E1 없는 ref 는 exit 2" "2" "$(run origin/없는가지)"

echo "── F. 대상 파일이 하나도 없는 스택이면 통과하되 «검사 0건»을 찍는다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
( cd "$R" || exit
  git rm -q docs/friction.md; git commit -q -m "누적 파일 없는 스택"
  git update-ref refs/remotes/origin/main HEAD )   # 대상 브랜치에도 없다 = 이 스택은 그 파일을 안 쓴다
ck "F1 대상 없음은 exit 0" "0" "$(run)"
grep -q "검사 0건" "$TMP/out" || { FAIL=$((FAIL+1)); echo "  ⛔ F2 «검사 0건»을 안 찍었다 — 0건 통과와 실제 통과가 구분되지 않는다"; }

echo "── I. ★보관 파일이 «생기기 전»에서 갈라진 낡은 브랜치는 통과한다"
# 배포처에 실제로 그런 브랜치가 살아 있다(2026-09-16 bnsone 실측 2개). 무조건 ⛔ 면 통째로 막힌다.
setup || { echo "⛔ 픽스처 실패"; exit 1; }
( cd "$R" || exit
  BASE=$(git rev-parse HEAD)
  printf '# 보관\n\n2026-08-01 /dev — 옛 줄\n' > docs/friction-보관.md
  git add docs/friction-보관.md >/dev/null; git commit -q -m "보관 파일 신설"
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b old "$BASE" )               # 보관 파일이 생기기 «전»에서 갈라진 가지
ck "I1 낡은 브랜치는 exit 0" "0" "$(run)"

echo "── J. ★그러나 «있던 파일을 지운» 것은 막는다 (I 와 같은 모양인데 반대 판정)"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
( cd "$R" || exit
  printf '# 보관\n\n2026-08-01 /dev — 옛 줄\n' > docs/friction-보관.md
  git add docs/friction-보관.md >/dev/null; git commit -q -m "보관 파일 신설"
  git update-ref refs/remotes/origin/main HEAD
  git rm -q "docs/friction-보관.md"; git commit -q -m "통째 삭제" )   # 갈라진 지점엔 있었다
ck "J1 누적 파일 삭제는 exit 1" "1" "$(run)"

echo "── H. 보관 파일 «자신»에서 줄이 사라져도 잡는다"
setup || { echo "⛔ 픽스처 실패"; exit 1; }
( cd "$R" || exit
  printf '# 보관\n\n2026-08-01 /dev — 옛 줄 하나\n2026-08-02 /fix — 옛 줄 둘\n' > docs/friction-보관.md
  git add docs/friction-보관.md >/dev/null; git commit -q -m "보관 파일 추가"
  git update-ref refs/remotes/origin/main HEAD
  printf '# 보관\n\n2026-08-02 /fix — 옛 줄 둘\n' > docs/friction-보관.md )
ck "H1 보관 파일의 삭제도 exit 1" "1" "$(run)"

cd "$HERE" || exit 1
echo "────────  $OK OK / $FAIL FAIL"
[ "$FAIL" = 0 ] || exit 1
