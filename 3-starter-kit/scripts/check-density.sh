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

  # ★한글은 3바이트다 — awk 의 length 는 바이트를 세므로 UTF-8 연속바이트(0x80-0xBF)를 빼고 글자를 센다.
  #   그대로 두면 한국어 규칙 문서에 상한이 **3배 엄하게** 걸려, 지킬 수 없는 줄이 "옛 초과"로 쌓인다(맥 실측 8줄 → 0줄).
  #   LC_ALL=C 고정: 멀티바이트를 문자로 세는 awk(gawk)와 바이트로 세는 awk(macOS·busybox)가 갈리면
  #   같은 파일이 환경마다 다른 판정을 받는다. `[\200-\277]` 정규식은 busybox 가 거부하므로 index 로 센다.
  local all; all=$(LC_ALL=C awk -v m="$maxcol" '
    function ulen(s,  n,i,k){n=length(s);k=0;for(i=1;i<=n;i++)if(index(CONT,substr(s,i,1))==0)k++;return k}
    BEGIN{for(i=128;i<192;i++)CONT=CONT sprintf("%c",i)}
    {L=ulen($0); if(L>m) print NR"\t"L}' "$f")
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
# rules/ 도 같은 상한 — CLAUDE.md 에서 "옮겨 놓는" 목적지가 검사 밖이면 감량이 이동으로 위장된다
# (2026-08-19 bnsone 감사 실측: rules 에 300자 초과 11줄·최장 582자가 아무 게이트도 안 거치고 쌓여 있었다).
for r in .claude/rules/*.md; do check "$r" 0 500; done

# digest 신선도 — 원본이 digest보다 새로우면 알림(차단 아님. /docs 갱신 리마인드 — 2026-08-15 stale 패턴 차용)
for d in docs/[0-9][0-9]_*/_digest.md; do
  [ -f "$d" ] || continue
  newer=$(find "$(dirname "$d")" -maxdepth 1 -name "*.md" ! -name "_digest.md" -newer "$d" 2>/dev/null | head -3)
  [ -n "$newer" ] && echo "ℹ️  $d : 원본이 digest보다 새로움 — /docs로 digest 갱신 검토 ($(echo "$newer" | tr '\n' ' '))"
done

if [ "$FAIL" = 0 ]; then echo "밀도 OK — 이번에 건드린 줄은 모두 상한 이내"; fi
exit "$FAIL"
