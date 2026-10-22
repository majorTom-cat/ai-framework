#!/usr/bin/env bash
# friction.py(마찰 기록 도구) 회귀 테스트 — `bash scripts/test-friction.sh`
# 왜 있나: 등록·조회·세기·닫기·보관이 «옛 한 파일 + 새 폴더 혼합» 에서 맞게 도는지 건수로 센다. /todo 0-c 의 «막힘 N / 안 닫힌 M» 이 이 도구의 count 다.
# 시험할 도구를 바꾸려면(유효성 증명용): FRICTION_TOOL=/경로/가짜.py bash scripts/test-friction.sh
set -u
TOOL="${FRICTION_TOOL:-$(cd "$(dirname "$0")" && pwd)/friction.py}"
[ -f "$TOOL" ] || { echo "⛔ 도구가 없다: $TOOL — 테스트 실패가 아니라 미배포다."; exit 1; }
python3 -c 'import sys' >/dev/null 2>&1 || { echo "⛔ python3 이 실행되지 않는다 — 검증 불능(합격 아님)."; exit 1; }
D=$(mktemp -d) || { echo "⛔ 임시폴더를 못 만들었다 — 검증 불능."; exit 1; }
cd "$D" || { echo "⛔ 임시폴더로 못 들어갔다 — 검증 불능."; exit 1; }
mkdir -p docs scripts
# 도구를 임시 repo 의 scripts/ 에 복사해 부른다 — 기본 root 가 «스크립트가 든 repo» 라(#813) 원본을 부르면 진짜 repo 기록을 고친다
cp "$TOOL" scripts/friction.py || { echo "⛔ 도구를 임시 repo 로 못 옮겼다 — 검증 불능."; exit 1; }
pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }
T() { python3 "$D/scripts/friction.py" "$@"; }
TODAY=$(python3 -c 'import datetime;print(datetime.date.today().isoformat())')

# ── 옛 파일 표본: 안 닫힌 2(그중 막힘 1) · 닫힌 1 · 토큰 신설일(2026-08-31) 이전 안 닫힌 1 + 옛 보관 1
cat > docs/friction.md <<'EOF'
# 마찰 로그

## 지금 살아 있는 것
2026-10-10 [막힘] /dev — 옛 막힘 줄
2026-10-11 /done — 옛 안 닫힌 줄
2026-10-05 /fix — 옛 닫힌 줄 [닫힘:#7]
2026-08-01 /dev — 토큰 이전 줄(세지 않는다)
> 인용문은 항목이 아니다
EOF
printf '%s\n' '2026-09-01 /dev — 옛 보관 줄 [닫힘:구기록]' > docs/friction-보관.md

# 경로가 아예 없으면 «0건» 이 아니라 판정 불능(2)
mkdir -p "$D/빈" && T --root "$D/빈" count >/dev/null 2>&1; [ "$?" = 2 ] && ok || no "기록 경로가 없는데 판정 불능(2)이 아니다"
# --root 없이도 같다 — 기록 없는 repo 에 든 도구를 기록 있는 폴더(여기)에서 불러도 «0건» 이 아니라 판정 불능(2)
mkdir -p "$D/빈repo/scripts" && cp "$TOOL" "$D/빈repo/scripts/friction.py"
python3 "$D/빈repo/scripts/friction.py" count >/dev/null 2>&1; [ "$?" = 2 ] && ok || no "기록 없는 repo 의 도구를 --root 없이 불렀는데 판정 불능(2)이 아니다(셸 작업 폴더를 읽었다)"
# 대조군: 새 폴더가 없어도 옛 파일만으로 센다
OUT=$(T count); case "$OUT" in "막힘 1건 / 안 닫힌 줄 2건 — 가장 오래된 2026-10-10"*) ok;; *) no "옛 파일만 count: $OUT";; esac

# ── add
P=$(T add --card 776 "/dev — 새 줄"); RC=$?
[ "$RC" = 0 ] && ok || no "add 실패 RC=$RC"
BN=$(basename "$P")
case "$BN" in "$TODAY"-776-??????.md) ok;; *) no "파일 이름 형식: $BN";; esac
[ "$(cat "$P")" = "$TODAY /dev — 새 줄" ] && ok || no "날짜 자동 접두가 안 붙었다: $(cat "$P")"
P2=$(T add "2026-10-20 [막힘] /done — 날짜 지정 막힘 줄")
case "$(basename "$P2")" in 2026-10-20-0-??????.md) ok;; *) no "날짜 지정·카드 없음 이름: $(basename "$P2")";; esac
T add "여러
줄" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "줄바꿈 든 입력을 받았다"
T add --card abc "x" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "숫자 아닌 카드번호를 받았다"
T add "" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "빈 입력을 받았다"
# 여러 번 등록해도 ID 가 안 겹친다
for i in 1 2 3 4 5 6 7 8 9 10; do T add "2026-10-21 /todo — 연속 $i" >/dev/null; done
IDS=$(ls docs/friction | sed -E 's/.*-([a-z0-9]{6})\.md/\1/' | sort | uniq -d | wc -l | tr -d ' ')
[ "$IDS" = 0 ] && ok || no "고유 6자리가 겹쳤다"
[ "$(ls docs/friction | wc -l | tr -d ' ')" = 12 ] && ok || no "파일 수가 12가 아니다"

# ── list: 옛 + 새 혼합, 필터
OUT=$(T list 2>/dev/null)
case "$OUT" in *"옛 | 2026-10-10 [막힘]"*) ok;; *) no "list 에 옛 줄이 없다";; esac
case "$OUT" in *"새:"*"새 줄"*) ok;; *) no "list 에 새 줄이 없다";; esac
case "$OUT" in *"옛보관 |"*) ok;; *) no "list 에 옛 보관이 없다";; esac
OUT=$(T list --blocked 2>/dev/null); N=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
[ "$N" = 2 ] && ok || no "막힘 필터가 2건(옛1+새1)이 아니다: $N"
OUT=$(T list --closed 2>/dev/null); N=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
[ "$N" = 2 ] && ok || no "닫힘 필터가 2건(옛 닫힘 1+옛 보관 1)이 아니다: $N"
T list --엉뚱 >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "모르는 필터를 받았다"

# ── count: 옛(2/막힘1) + 새(12/막힘1) = 안 닫힌 14 · 막힘 2 · 가장 오래된 2026-10-10
OUT=$(T count); case "$OUT" in "막힘 2건 / 안 닫힌 줄 14건 — 가장 오래된 2026-10-10"*) ok;; *) no "혼합 count: $OUT";; esac

# ── close
ID=$(basename "$P" .md | sed -E 's/.*-//')
T close "$ID" "#776" >/dev/null; RC=$?
[ "$RC" = 0 ] && ok || no "close 실패 RC=$RC"
[ "$(cat "$P")" = "$TODAY /dev — 새 줄 [닫힘:#776]" ] && ok || no "닫힘이 줄 끝에 안 붙었다: $(cat "$P")"
T close "$ID" "#1" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "이미 닫힌 줄을 또 닫았다"
T close "zzzzzz" "#1" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "없는 ID 를 닫았다"
T close "$(basename "$P2" .md | sed -E 's/.*-//')" "a b" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "공백 든 닫힘 값을 받았다"
T close "$(basename "$P2" .md | sed -E 's/.*-//')" "x]" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "] 든 닫힘 값을 받았다"
OUT=$(T count); case "$OUT" in "막힘 2건 / 안 닫힌 줄 13건"*) ok;; *) no "닫은 뒤 count: $OUT";; esac

# ── archive: 닫힌 파일만, 최신 N개 남기고 보관/ 으로(삭제 아님)
for i in 1 2 3 4 5 6 7; do
  Q=$(T add "2026-10-0$i /todo — 닫힐 줄 $i"); T close "$(basename "$Q" .md | sed -E 's/.*-//')" "#$i" >/dev/null
done
BEFORE=$(ls docs/friction | grep -c '\.md$')
T archive --keep 3 >/dev/null
[ "$(find docs/friction/보관 -name '*.md' | wc -l | tr -d ' ')" = 5 ] && ok || no "보관으로 5개가 안 갔다: $(find docs/friction/보관 -name '*.md' | wc -l)"
[ "$(find docs/friction/보관 -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -ge 1 ] && ok || no "보관이 월별 하위 폴더로 안 갔다"
ls docs/friction/보관 | grep -qE '^[0-9]{4}-[0-9]{2}$' && ok || no "보관 하위 폴더 이름이 YYYY-MM 이 아니다: $(ls docs/friction/보관)"
AFTER=$(ls docs/friction | grep -c '\.md$')
[ $((BEFORE - AFTER)) = 5 ] && ok || no "열린 쪽에서 5개가 안 줄었다"
# 보관 뒤에도 총량 불변(삭제 아님)
TOTAL=$(( $(ls docs/friction | grep -c '\.md$') + $(find docs/friction/보관 -name '*.md' | wc -l | tr -d ' ') ))
[ "$TOTAL" = "$BEFORE" ] && ok || no "보관하며 파일 수가 줄었다(삭제됨): $TOTAL != $BEFORE"
# 안 닫힌 파일은 안 움직인다
[ "$(find docs/friction/보관 -name '*.md' -exec grep -L '닫힘' {} + | wc -l | tr -d ' ')" = 0 ] && ok || no "안 닫힌 파일이 보관으로 갔다"
OUT=$(T count); case "$OUT" in "막힘 2건 / 안 닫힌 줄 13건"*) ok;; *) no "보관 뒤 count 가 달라졌다: $OUT";; esac
T list --closed 2>/dev/null | grep -q '새보관:' && ok || no "list --closed 에 월별 보관 파일이 안 보인다"
T archive --keep 3 | grep -q '옮길 닫힌 파일 없음' && ok || no "두 번째 archive 가 «없음» 을 안 알렸다"
T 엉뚱 >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "모르는 명령을 받았다"

# ── 옛 friction.md 의 열린 줄 닫기: 제자리 편집, 다른 줄은 바이트 그대로
cp docs/friction.md "$D/legacy.before"
T close "/done — 옛 안 닫힌 줄" "#9" >/dev/null; RC=$?
[ "$RC" = 0 ] && ok || no "옛 줄 닫기 실패 RC=$RC"
grep -q '^2026-10-11 /done — 옛 안 닫힌 줄 \[닫힘:#9\]$' docs/friction.md && ok || no "옛 줄 끝에 닫힘이 안 붙었다: $(grep '옛 안 닫힌' docs/friction.md)"
[ "$(diff "$D/legacy.before" docs/friction.md | grep -c '^[<>]')" = 2 ] && ok || no "옛 줄 닫기가 다른 줄까지 바꿨다"
T close "/done — 옛 안 닫힌 줄" "#9" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "이미 닫은 옛 줄을 또 닫았다"
T close "옛 막힘" "#9" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "12자 미만 문구로 옛 줄을 닫았다"
T close "2026-10-1" "#9" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "여러 줄에 맞는 짧은 문구로 닫았다"
T close "그런 문구는 어디에도 없다 정말로" "#9" >/dev/null 2>&1; [ "$?" = 1 ] && ok || no "없는 문구로 닫았다"

# ── count 의 보관 안내: 닫힌 파일이 열린 쪽에 20개 넘게 쌓이면 한 줄 더
OUT=$(T count); case "$OUT" in *"보관하라"*) no "닫힌 파일이 적은데 보관 안내가 떴다: $OUT";; *) ok;; esac
for i in $(seq 1 22); do
  Q=$(T add "2026-10-15 /todo — 쌓인 닫힌 줄 $i"); T close "$(basename "$Q" .md | sed -E 's/.*-//')" "#$i" >/dev/null
done
OUT=$(T count); case "$OUT" in *"닫힌 파일 "*"개가 열린 쪽에 쌓였다"*"archive"*) ok;; *) no "닫힌 파일 22개인데 보관 안내가 없다: $OUT";; esac

# ── 다른 폴더에서 호출(#813): --root 없으면 셸 작업 폴더가 아니라 «스크립트가 든 repo» 를 쓴다
#    미끼 폴더 = 본 클론 역할(자기 docs/friction/ 이 있다), $D = 워크트리 역할(도구가 든 repo)
mkdir -p "$D/미끼/docs/friction"
cd "$D/미끼" || { echo "⛔ 미끼 폴더로 못 들어갔다 — 검증 불능."; exit 1; }
BEFORE=$(ls "$D/docs/friction" | grep -c '\.md$')
P3=$(T add --card 813 "/fix — 다른 폴더에서 부른 줄"); RC=$?
[ "$RC" = 0 ] && ok || no "다른 폴더에서 add 실패 RC=$RC"
[ "$(ls "$D/미끼/docs/friction" | wc -l | tr -d ' ')" = 0 ] && ok || no "다른 폴더에서 부르니 셸 작업 폴더(미끼)에 썼다: $(ls "$D/미끼/docs/friction")"
[ "$(ls "$D/docs/friction" | grep -c '\.md$')" = $((BEFORE + 1)) ] && ok || no "다른 폴더에서 부른 add 가 도구의 repo 에 안 들어갔다"
T close "$(basename "$P3" .md | sed -E 's/.*-//')" "#813" >/dev/null; RC=$?
[ "$RC" = 0 ] && grep -q '\[닫힘:#813\]$' "$D/docs/friction/$(basename "$P3")" && ok || no "다른 폴더에서 close 가 도구의 repo 파일을 못 닫았다 RC=$RC"
OUT=$(T count); case "$OUT" in "막힘 2건 / 안 닫힌 줄 12건"*) ok;; *) no "다른 폴더에서 count 가 도구의 repo 를 안 셌다: $OUT";; esac
# 링크로 불러도 링크가 놓인 쪽(미끼)이 아니라 실물이 든 repo
mkdir -p "$D/미끼/scripts" && ln -s "$D/scripts/friction.py" "$D/미끼/scripts/friction.py"
python3 "$D/미끼/scripts/friction.py" add "/fix — 링크로 부른 줄" >/dev/null; RC=$?
[ "$RC" = 0 ] && [ "$(ls "$D/미끼/docs/friction" | wc -l | tr -d ' ')" = 0 ] && grep -lq '링크로 부른 줄' "$D"/docs/friction/*.md && ok || no "링크로 부르니 실물의 repo 가 아닌 곳에 썼다 RC=$RC"
# --root 를 주면 종전대로 그 폴더
T --root "$D/미끼" add "/fix — 미끼에 쓰라고 지정한 줄" >/dev/null; RC=$?
[ "$RC" = 0 ] && [ "$(ls "$D/미끼/docs/friction" | wc -l | tr -d ' ')" = 1 ] && ok || no "--root 로 지정한 폴더에 안 썼다 RC=$RC"
OUT=$(T --root "$D/미끼" count); case "$OUT" in "막힘 0건 / 안 닫힌 줄 1건"*) ok;; *) no "--root 지정 count: $OUT";; esac

# ── 도움말·옵션 오타(bnsone #816): `add --help` 가 «--help» 라는 기록 파일을 만들면 안 된다
BEFORE=$(ls "$D/docs/friction" | wc -l | tr -d ' ')
OUT=$(T add --help 2>&1); RC=$?
[ "$RC" = 0 ] && case "$OUT" in *"사용 ("*) ok;; *) no "add --help 가 사용법을 안 보였다 RC=$RC: $OUT";; esac
OUT=$(T --help 2>&1); RC=$?
[ "$RC" = 0 ] && ok || no "--help 종료 코드가 0 이 아니다 RC=$RC"
OUT=$(T add "--help-ish 오타" 2>&1); RC=$?
[ "$RC" = 1 ] && ok || no "옵션 모양으로 시작하는 줄을 기록했다 RC=$RC"
[ "$(ls "$D/docs/friction" | wc -l | tr -d ' ')" = "$BEFORE" ] && ok || no "도움말·옵션 오타가 기록 파일을 만들었다"

cd / && rm -r "$D"
echo "통과 $pass / 실패 $fail"
[ "$fail" -eq 0 ] && [ "$pass" -ge 57 ]
