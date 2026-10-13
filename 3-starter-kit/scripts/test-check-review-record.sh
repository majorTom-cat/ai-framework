#!/bin/bash
# check-review-record.sh 자기시험 — 스크래치패드로 옮긴 뒤 절대경로로 돌려라(저장소 루트에서 돌리지 마라)
HERE="$(cd "$(dirname "$0")" && pwd)"
C="$HERE/check-review-record.sh"
T="$(mktemp -d)" || exit 1
cd "$T" || exit 1
pass=0; fail=0
t() { # 이름 기대코드 본문
  printf '%s\n' "$3" > "$T/b.md"
  bash "$C" "$T/b.md" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1 (기대 $2 실제 $rc)"; fi
}
FULL='방식 단일 · 리뷰어 1 · 소요 약 2.6분 · 토큰 약 12.3만 · 재현된 결함 0건 · 결함 위치 해당 없음'
t A1-전부-있음 0 "$FULL"
t A2-미제공도-통과 0 '방식 단일 · 리뷰어 1 · 소요 미제공 · 토큰 미제공 · 확정 미제공 · 결함 위치 미제공'
t B1-토큰-빠짐 1 '방식 단일 · 리뷰어 1 · 소요 약 2분 · 재현된 결함 0건 · 결함 위치 해당 없음'
t B2-결함위치-빠짐 1 '방식 단일 · 리뷰어 1 · 소요 약 2분 · 토큰 약 1만 · 재현된 결함 0건'
t B3-라벨만-있고-값-없음 1 '방식 단일 · 리뷰어 1 · 소요 약 2분 · 토큰 · 재현된 결함 0건 · 결함 위치 대상'
t B4-리뷰기록-통째로-없음 1 '머지됨. 시험 통과.'
rm -f "$T/b.md"
bash "$C" "$T/없는파일.md" >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL C1-점검불능 (기대 2 실제 $rc)"; fi
echo "통과 $pass / 실패 $fail"
rm -rf "$T"
[ "$fail" -eq 0 ]
