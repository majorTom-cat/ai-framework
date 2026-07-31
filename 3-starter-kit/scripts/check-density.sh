#!/usr/bin/env bash
# 밀도 검사 — 규칙 문서가 자기 밀도 규약을 스스로 지키는지 기계로 강제한다.
# 근거·경위: _reference/density.md. 이 스크립트가 "추가만 하고 안 줄인다"의 발동지점이다.
# 로컬: bash scripts/check-density.sh   ·   CI: density-check 잡이 MR에서 실행.
set -u
FAIL=0

# 대상: 경로  최대줄수(0=검사안함)  줄당최대글자
check() {
  local f="$1" maxlines="$2" maxcol="$3"
  [ -f "$f" ] || return 0
  local lines; lines=$(wc -l <"$f")
  if [ "$maxlines" -gt 0 ] && [ "$lines" -gt "$maxlines" ]; then
    echo "⛔ $f : $lines 줄 (상한 $maxlines) — 규칙을 _reference/로 옮기거나 훅/CI로 전환하라"
    FAIL=1
  fi
  local over; over=$(awk -v m="$maxcol" 'length>m{print NR": "length"자"}' "$f")
  if [ -n "$over" ]; then
    echo "⛔ $f : 줄당 $maxcol 자 초과 —"
    echo "$over" | sed 's/^/     /'
    echo "     → 규칙은 짧게 남기고 근거(날짜·경위·수치)는 _reference/로. 실측 예외는 지우지 말고 옮긴다."
    FAIL=1
  fi
}

check "CLAUDE.md" 200 300
for s in .claude/skills/*/SKILL.md; do check "$s" 0 500; done

if [ "$FAIL" = 0 ]; then echo "밀도 OK — 모든 규칙 문서가 상한 이내"; fi
exit "$FAIL"
