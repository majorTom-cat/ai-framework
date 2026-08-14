#!/usr/bin/env bash
# 밀도 검사 — 규칙 문서가 자기 밀도 규약을 스스로 지키는지 기계로 강제한다.
# 근거·경위: _reference/density.md. 이 스크립트가 "추가만 하고 안 줄인다"의 발동지점이다.
# 로컬: bash scripts/check-density.sh   ·   CI: density-check 잡이 MR에서 실행.
#
# ★막는 것은 "이번에 건드린 줄"뿐이다(2026-08-06). 예전부터 있던 긴 줄은 세어서 알리되 막지 않는다.
#   이유: 옛 빚으로 막으면 무관한 MR이 전부 빨개지고, 그러면 새 빚이 생겨도 구분이 안 돼 아무도 안 본다.
#   옛 줄은 그 줄을 고칠 일이 생겼을 때 갚는다 — 규칙 본문을 억지로 _reference/로 옮기지 마라
#   (분할은 총량을 줄이지 않고, 옮긴 규칙을 실제로 찾아 읽는지 실증 전엔 지키게 만들지도 못한다).
set -u
FAIL=0

# 비교 기준(base) 정하기 — 못 정하면 전수 검사로 떨어진다(빈 diff를 "변경 없음"으로 오독하지 않기 위함).
BASE=""
if [ -n "${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}" ]; then
  BASE="$CI_MERGE_REQUEST_DIFF_BASE_SHA"
elif git rev-parse --git-dir >/dev/null 2>&1; then
  for ref in "origin/${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-main}" origin/main main; do
    if git rev-parse --verify -q "$ref" >/dev/null 2>&1; then
      BASE=$(git merge-base HEAD "$ref" 2>/dev/null) && [ -n "$BASE" ] && break
    fi
  done
fi
if [ -n "$BASE" ] && ! git cat-file -e "$BASE" 2>/dev/null; then BASE=""; fi

# 이번에 추가·수정된 줄 번호만 뽑는다. base가 없으면 빈 값(=전수 검사 신호).
changed_lines() {
  [ -n "$BASE" ] || return 0
  git diff -U0 "$BASE" -- "$1" 2>/dev/null |
    awk '/^@@/ { if (match($0, /\+[0-9]+(,[0-9]+)?/)) {
                   split(substr($0, RSTART+1, RLENGTH-1), a, ",")
                   n = (a[2] == "" ? 1 : a[2])
                   for (i = 0; i < n; i++) print a[1] + i
                 } }'
}

# 대상: 경로  최대줄수(0=검사안함)  줄당최대글자
check() {
  local f="$1" maxlines="$2" maxcol="$3"
  [ -f "$f" ] || return 0

  local lines; lines=$(wc -l <"$f")
  if [ "$maxlines" -gt 0 ] && [ "$lines" -gt "$maxlines" ]; then
    echo "⛔ $f : $lines 줄 (상한 $maxlines) — 규칙을 _reference/로 옮기거나 훅/CI로 전환하라"
    FAIL=1
  fi

  local all; all=$(awk -v m="$maxcol" 'length>m{print NR"\t"length}' "$f")
  [ -n "$all" ] || return 0

  local touched; touched=$(changed_lines "$f")
  if [ -z "$BASE" ]; then
    echo "⛔ $f : 줄당 $maxcol 자 초과(비교 기준을 못 정해 전수 검사) —"
    echo "$all" | awk -F'\t' '{print "     "$1": "$2"자"}'
    echo "     → 규칙은 짧게 남기고 근거(날짜·경위·수치)는 _reference/로. 실측 예외는 지우지 말고 옮긴다."
    FAIL=1
    return 0
  fi

  # 이번에 건드린 줄 중 초과분 = 막는다. 나머지 = 세어서 알리기만.
  local new old
  new=$(echo "$all" | awk -F'\t' -v t="$(echo "$touched" | tr '\n' ' ')" '
        BEGIN{split(t,x," "); for(i in x) T[x[i]]=1} $1 in T {print "     "$1": "$2"자"}')
  old=$(echo "$all" | awk -F'\t' -v t="$(echo "$touched" | tr '\n' ' ')" '
        BEGIN{split(t,x," "); for(i in x) T[x[i]]=1} !($1 in T)' | wc -l | tr -d ' ')

  if [ -n "$new" ]; then
    echo "⛔ $f : 이번에 건드린 줄이 $maxcol 자를 넘는다 —"
    echo "$new"
    echo "     → 규칙은 짧게 남기고 근거(날짜·경위·수치)는 _reference/로. 실측 예외는 지우지 말고 옮긴다."
    FAIL=1
  fi
  if [ "$old" -gt 0 ]; then
    echo "ℹ️  $f : 예전부터 $maxcol 자를 넘던 줄 $old 개 — 이번엔 막지 않는다(그 줄을 고칠 때 갚아라)"
  fi
}

check "CLAUDE.md" 200 300
# 보조 파일(함정.md 등)도 같은 상한 — 본문에서 옮긴 내용이 밀도 회피처가 되는 것을 막는다(2026-08-15 확장).
for s in .claude/skills/*/*.md; do check "$s" 0 500; done

if [ "$FAIL" = 0 ]; then echo "밀도 OK — 이번에 건드린 줄은 모두 상한 이내"; fi
exit "$FAIL"
