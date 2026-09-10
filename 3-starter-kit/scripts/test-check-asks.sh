#!/usr/bin/env bash
# check-asks.sh 의 회귀 테스트 — 「기대를 뒤집으면 FAIL 이 나는가」로 잣대를 증명한다.
# ★왜 필요한가: 이 검사기는 «창이 몰래 늘어나는 것»을 막는 유일한 방어선인데, 검사기 자신이
#   깨지면 그 방어가 **무음으로** 사라진다(2026-09-10 실측: test-check-push.sh 가 사유 문구만
#   봐서 창을 알림으로 바꿔도 56/56 초록이었다). 그래서 «잡는다»는 것을 여기서 실제로 보인다.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHK="$HERE/check-asks.sh"
TMP="$(mktemp -d)" || { echo "⛔ 임시 폴더를 못 만들었다(울타리?) — 저장소에 픽스처를 떨어뜨리지 않으려고 여기서 멈춘다"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
OK=0; FAIL=0

hooks() { # $1 = 창 개수 — 훅이 낼 수 있는 ask 를 그 수만큼 만든다
  rm -rf "$TMP/.claude"; mkdir -p "$TMP/.claude/hooks"
  i=0; while [ "$i" -lt "$1" ]; do
    printf 'printf %s\n' "'{\"hookSpecificOutput\":{\"permissionDecision\":\"ask\"}}'" >> "$TMP/.claude/hooks/guard.sh"
    i=$((i+1))
  done
  [ "$1" = 0 ] && : > "$TMP/.claude/hooks/guard.sh"
}
table() { # stdin = 표 본문
  mkdir -p "$TMP/_reference"; cat > "$TMP/_reference/asks.md"
}
# ★HOME 도 픽스처로 돌린다 — 검사기가 `$HOME/.claude/settings.json` 까지 보므로,
#   안 돌리면 «시험 결과가 그 맥의 개인 설정에 따라 달라진다»(재현 안 되는 시험은 시험이 아니다).
run() { ASKS_ROOT="$TMP" HOME="$TMP" bash "$CHK" 2>&1; }
code() { ASKS_ROOT="$TMP" HOME="$TMP" bash "$CHK" >/dev/null 2>&1; echo $?; }

ck() { # $1=설명 $2=기대문구 $3=출력
  if printf '%s' "$3" | grep -q "$2"; then OK=$((OK+1))
  else FAIL=$((FAIL+1)); echo "  ⛔ $1"; echo "     기대: $2"; echo "     실제: $(printf '%s' "$3" | head -3)"; fi
}
ckcode() { # $1=설명 $2=기대코드 $3=실제코드
  if [ "$2" = "$3" ]; then OK=$((OK+1))
  else FAIL=$((FAIL+1)); echo "  ⛔ $1 — 기대 종료코드 $2 / 실제 $3"; fi
}

GOOD='# 전수 표
| # | 창 | 언제 | revert 하나로 되돌아가나 | 판정 |
|---|---|---|---|---|
| ① | 하나 | 항상 | **아니오** | 유지 |
| ② | 둘 | 항상 | **아니오** | 유지 |
| ③ | 셋 | 항상 | **아니오** | 유지 |
'

echo "── A. 표와 훅이 같으면 통과한다"
hooks 3; printf '%s' "$GOOD" | table
ck     "A1 통과 문구" "확인 창 OK" "$(run)"
ckcode "A2 종료코드 0" 0 "$(code)"

echo "── B. ★창을 몰래 더하면 잡는다 (이 파일의 존재 이유)"
hooks 4; printf '%s' "$GOOD" | table
OUT="$(run)"
ck     "B1 수가 다르다고 말한다" "확인 창의 수가 전수 표와 다르다" "$OUT"
ck     "B2 양쪽 수를 찍는다" "훅 4 개 / 표 3 줄" "$OUT"
ckcode "B3 차단형이다(종료코드 1)" 1 "$(code)"

echo "── C. 반대로 표만 늘어도 잡는다 — 없앤 창을 표에서 안 지운 경우"
hooks 2; printf '%s' "$GOOD" | table
ckcode "C1 종료코드 1" 1 "$(code)"

echo "── D. «되돌릴 수 있나» 칸이 비면 잡는다 — 기준을 안 대본 창이다"
hooks 3
printf '%s' '# 전수 표
| # | 창 | 언제 | revert 하나로 되돌아가나 | 판정 |
|---|---|---|---|---|
| ① | 하나 | 항상 | **아니오** | 유지 |
| ② | 둘 | 항상 |  | 유지 |
| ③ | 셋 | 항상 | **아니오** | 유지 |
' | table
OUT="$(run)"
ck     "D1 빈 판정을 말한다" "빈 줄 1 개" "$OUT"
ckcode "D2 종료코드 1" 1 "$(code)"

echo "── E. 표나 훅이 아예 없으면 «없다»고 말하고 막는다 (파일 부재 = 초록 은 이 repo 의 단골 실패다)"
hooks 3; rm -f "$TMP/_reference/asks.md"
ck     "E1 표 부재를 말한다" "전수 표가 없다" "$(run)"
ckcode "E2 종료코드 1" 1 "$(code)"
printf '%s' "$GOOD" | table; rm -rf "$TMP/.claude"
ck     "E3 훅 폴더 부재를 말한다" "훅 폴더가 없다" "$(run)"
ckcode "E4 종료코드 1" 1 "$(code)"

echo "── G. ★설정 파일 «안»에 숨은 창도 잡는다 (2026-09-10 — 오너가 받던 거짓 창이 거기 있었다)"
hooks 3; printf '%s' "$GOOD" | table
mkdir -p "$TMP/.claude"
# ★픽스처는 «실물 모양»이어야 한다 — 설정 파일 안의 훅 명령은 JSON 문자열이라
#   따옴표가 \" 로 이스케이프된다. 처음엔 이스케이프 없는 모양으로 써서 시험이 통과해 버렸고,
#   그 잣대는 정작 실물 파일에서 0을 냈다(2026-09-10 — 그 자리에서 잡았다).
cat > "$TMP/.claude/settings.local.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "hooks": [
  { "command": "printf '{\"hookSpecificOutput\":{\"permissionDecision\":\"ask\"}}'" }
] } ] } }
JSON
OUT="$(run)"
ck     "G1 설정 파일 안의 창을 말한다" "설정 파일 «안에» 직접 적힌 확인 창이 있다" "$OUT"
ck     "G2 어느 파일인지 지목한다" "settings.local.json" "$OUT"
ckcode "G3 차단한다" 1 "$(code)"
rm -f "$TMP/.claude/settings.local.json"
ckcode "G4 없애면 다시 통과" 0 "$(code)"

echo "── F. 이 repo 실물에서도 통과한다 (픽스처만 맞추고 실물이 어긋나면 의미가 없다)"
REAL="$(cd "$HERE/.." && pwd)"
if [ -f "$REAL/_reference/asks.md" ] && [ -d "$REAL/.claude/hooks" ]; then
  bash "$CHK" >/dev/null 2>&1
  ckcode "F1 실물 종료코드 0" 0 "$?"
else
  echo "  (이 repo 엔 표·훅이 없다 — 건너뛴다)"
fi

echo "────────  $OK OK / $FAIL FAIL"
[ "$FAIL" = 0 ] || exit 1
