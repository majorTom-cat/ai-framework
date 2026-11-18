#!/usr/bin/env bash
# todo-handoff-check.cjs(인계 메모 카드 대조기) 회귀 테스트 — `bash scripts/test-todo-handoff-check.sh`
# 왜 있나: /todo 가 인계 메모의 카드를 선택지에 올리기 전에 «지금 닫혔나»를 기계로 가르는지 센다 — 닫힘을 놓치면 닫힌 카드를 사람에게 또 묻는다.
# 시험할 도구를 바꾸려면(유효성 증명용): HANDOFF_TOOL=/경로/가짜.cjs bash scripts/test-todo-handoff-check.sh
set -u
TOOL="${HANDOFF_TOOL:-$(cd "$(dirname "$0")" && pwd)/todo-handoff-check.cjs}"
[ -f "$TOOL" ] || { echo "⛔ 도구가 없다: $TOOL — 테스트 실패가 아니라 미배포다."; exit 1; }
node -e '0' >/dev/null 2>&1 || { echo "⛔ node 가 실행되지 않는다 — 검증 불능(합격 아님)."; exit 1; }
D=$(mktemp -d) || { echo "⛔ 임시폴더를 못 만들었다 — 검증 불능."; exit 1; }
cd "$D" || { echo "⛔ 임시폴더로 못 들어갔다 — 검증 불능."; exit 1; }
pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }
run() { TODO_HANDOFF_FAKE="$D/fake.json" node "$TOOL" "$@"; }

cat > fake.json <<'EOF'
{"754": {"state":"closed","closed_at":"2026-11-18T08:34:00Z","title":"닫힌 카드","labels":["셀프완료"]},
 "1281": {"state":"opened","labels":["진행중"],"title":"열린 카드"},
 "99": {"state":"opened","labels":[],"title":"절 밖 카드"},
 "500": "fail"}
EOF

cat > local.md <<'EOF'
# 로컬 메모
## 🔴 세션 시작 시
- ⓐ #754 대기 — 둘 중 정하기, 사용자는 아직 답 안 함
- ⓑ #1281 진행중 · MR !2088 · 색 &#123; 와 #fff 는 번호가 아니다 · 같은 #754 두 번
## 작업 요령
- #99 는 인계 절 밖이라 안 센다
EOF

# 대조군: 닫힘 1 · 열림 1 · 실패 0 → 0
OUT=$(run local.md); RC=$?
[ "$RC" = 0 ] && ok || no "전부 조회됐는데 종료 코드 $RC"
case "$OUT" in *"요약: 열림 1 · 닫힘 1 · 조회실패 0"*) ok;; *) no "요약이 틀림: $OUT";; esac
printf '%s\n' "$OUT" | grep -q $'^#754\t닫힘\t2026-11-18' && ok || no "닫힌 #754 를 닫힘으로 못 냄: $OUT"
printf '%s\n' "$OUT" | grep -q $'^#1281\t열림\t진행중' && ok || no "열린 #1281 라벨을 못 냄: $OUT"
printf '%s\n' "$OUT" | grep -q '^#99' && no "인계 절 밖 #99 를 셌다" || ok
printf '%s\n' "$OUT" | grep -q '^#2088\|^#123\|^#fff' && no "MR·엔티티·색상을 카드로 셌다" || ok
[ "$(printf '%s\n' "$OUT" | grep -c '^#754')" = 1 ] && ok || no "같은 번호를 두 번 조회했다"

# 조회실패는 «닫힌 것 없음» 이 아니다 → 2
printf '%s\n' '## 🔴 인계' '- #500 확인' '- #1281' > fail.md
OUT=$(run fail.md); RC=$?
[ "$RC" = 2 ] && ok || no "조회실패가 있는데 종료 코드 $RC(2 여야)"
printf '%s\n' "$OUT" | grep -q $'^#500\t조회실패' && ok || no "조회실패 줄이 없다: $OUT"

# 인계 절이 없으면 0 + 한 줄
printf '%s\n' '# 메모' '- #754 옛 줄' > none.md
OUT=$(run none.md); RC=$?
[ "$RC" = 0 ] && ok || no "인계 절 없음인데 종료 코드 $RC"
case "$OUT" in *"인계 절(## 🔴) 없음"*) ok;; *) no "인계 절 없음 문구가 없다: $OUT";; esac

# 파일이 없으면 판정 불능 2
run "$D/없는파일.md" >/dev/null 2>&1; [ "$?" = 2 ] && ok || no "파일이 없는데 판정 불능(2)이 아니다"

cd / && rm -r "$D"
echo "통과 $pass / 실패 $fail"
[ "$fail" = 0 ] && [ "$pass" -gt 0 ]
