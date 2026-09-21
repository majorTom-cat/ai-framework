#!/usr/bin/env bash
# collect-planner-questions.sh 의 회귀 테스트.
# ★이 파일의 존재 이유 = B·D 다. B = «풀린 질문을 또 보내지 않는다», D = «식별자는 경계로 찾는다»(`C-1` 이 `C-13` 줄에 걸리면
#   후보가 부풀어 아무도 안 본다 — bnsone 실측). 둘 중 하나를 되돌리면 여기가 FAIL 해야 한다.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/collect-planner-questions.sh"
OK=0; FAIL=0

[ -f "$TOOL" ] || { echo "⛔ 검사기가 없다: $TOOL"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "⛔ python3 이 없다 — «건너뜀»이 아니라 실패다."; exit 1; }

TMP="${TMPDIR:-/tmp}/cpq.$$"; mkdir -p "$TMP" || { echo "⛔ 임시 폴더를 못 만든다: $TMP"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
touch "$TMP/.w" 2>/dev/null || { echo "⛔ 임시 폴더에 못 쓴다"; exit 1; }

R="$TMP/r"
mkdir -p "$R/docs/04_Business" || exit 1
( cd "$R" || exit 9
  git init -q -b main . 2>/dev/null || exit 9
  git config user.email t@t; git config user.name t
  cat > docs/04_Business/_digest.md <<'EOF'
# 요약

## 확정된 것
- 확정 항목은 질문이 아니다.

## 미해결·질문
- **W-06 참조인 알림 문구** — 기획 확인 대상.
  ①세부 줄도 따라온다.

### 결재선 관련
- **C-1 공통 배지** — 규격 없음.
- **해소** 결재선 표시(→ 원문 §2).
- ✅ 이미 맞춘 것.
- ~~취소된 질문~~

## 근거
- 근거 줄은 질문이 아니다.
EOF
  cat > docs/04_Business/Design.md <<'EOF'
# 업무 설계
| W-06 | 참조인 | 2026-09-10 정정: 알림 문구 확정 |
| C-13 | 미확정자 알림 | 확인 상태 반영 |
EOF
  git add docs >/dev/null; git commit -q -m base ) || { echo "⛔ 픽스처 실패"; exit 1; }

run() { ( cd "$R" || exit 9; bash "$TOOL" "$@" > "$TMP/out" 2>&1; echo $? ); }
ck() { if [ "$2" = "$3" ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); echo "  ⛔ $1 — 기대 $2 / 실제 $3"; sed 's/^/     /' "$TMP/out" | head -8; fi; }
has() { if grep -qF -- "$2" "$TMP/out"; then OK=$((OK+1)); else FAIL=$((FAIL+1)); echo "  ⛔ $1 — 출력에 '$2' 없음"; fi; }
hasnt() { if grep -qF -- "$2" "$TMP/out"; then FAIL=$((FAIL+1)); echo "  ⛔ $1 — 출력에 '$2' 가 있다"; else OK=$((OK+1)); fi; }

echo "── A. 묶음은 «질문» 절의 안 풀린 항목만 모은다"
ck "A1 exit 0" "0" "$(run)"
has "A2 열린 항목" "W-06 참조인 알림 문구"
has "A3 들여쓴 세부 줄도 따라온다" "①세부 줄도 따라온다"
has "A4 건수" "미회신 2건"
has "A7 ★불릿 위 제목도 싣는다(홀로 읽히게)" "**결재선 관련**"
hasnt "A5 다른 절은 안 싣는다" "확정 항목은 질문이 아니다"
hasnt "A6 다음 절에서 끝난다" "근거 줄은 질문이 아니다"

echo "── B. ★풀린 표시가 있는 항목은 빠진다"
hasnt "B1 해소" "결재선 표시"
hasnt "B2 ✅" "이미 맞춘 것"
hasnt "B3 취소선" "취소된 질문"

echo "── C. --stale 은 원문의 정정·확정 줄과 식별자가 겹치는 항목을 낸다"
ck "C1 후보가 있으면 exit 1" "1" "$(run --stale)"
has "C2 W-06 후보" "[W-06]"

echo "── D. ★식별자는 경계로 찾는다 — C-1 이 C-13 줄에 걸리면 안 된다"
hasnt "D1 C-1 은 후보가 아니다" "[C-1]"

echo "── E. 루트가 아니면 판정 불능"
( cd "$R/docs" || exit 9; bash "$TOOL" > "$TMP/out" 2>&1; echo $? > "$TMP/rc" )
ck "E1 exit 2" "2" "$(cat "$TMP/rc")"

echo "──── 결과: ${OK} OK / ${FAIL} FAIL"
[ "$FAIL" = 0 ]
