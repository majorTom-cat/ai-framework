#!/usr/bin/env bash
# 킷이 세우는 «확인 창»의 수가 _reference/asks.md 의 전수 표와 같은지 대조한다. 다르면 exit 1.
#
# 왜: 창은 자동 모드보다 위라 **모든 세션·모든 모드에 정지를 영구히 세운다.** 그런데 지금까지
#     «창이 몇 개인지» 아무도 안 셌고, 오너가 창을 찍어 보낼 때마다 하나씩 고쳤다(2026-09-10 지적).
#     표를 정본으로 두고 기계가 대조하면 «몰래 늘어난 창»이 CI 에서 걸린다.
# ★차단형이다(exit 1) — 경고만 내는 검사기는 방어선이 아니다(2026-09-09 실측: exit 0 검사기가
#   한도 초과 스킬을 통과시켰다).
set -u
# ★ASKS_ROOT 는 자기시험용 픽스처 뿌리다(check-skill-size.sh 의 SKILL_ROOT 와 같은 관례) —
#   없으면 이 스크립트가 놓인 repo 루트를 본다.
ROOT="${ASKS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TABLE="$ROOT/_reference/asks.md"
HOOKS="$ROOT/.claude/hooks"

[ -f "$TABLE" ] || { echo "⛔ 전수 표가 없다: _reference/asks.md"; exit 1; }
[ -d "$HOOKS" ] || { echo "⛔ 훅 폴더가 없다: .claude/hooks"; exit 1; }

# 훅이 실제로 낼 수 있는 ask 수
ACTUAL=$(grep -rho 'permissionDecision":"ask"' "$HOOKS" 2>/dev/null | grep -c . || true)
# 표의 항목 수 = 「| ① |」 형태의 줄
EXPECTED=$(grep -cE '^\| *[①②③④⑤⑥⑦⑧⑨⑩] *\|' "$TABLE" || true)

if [ "$ACTUAL" -ne "$EXPECTED" ]; then
  echo "⛔ 확인 창의 수가 전수 표와 다르다 — 훅 $ACTUAL 개 / 표 $EXPECTED 줄"
  echo "   창을 더했으면 _reference/asks.md 표에 줄을 더하고, 그 줄의 «되돌릴 수 있나» 칸을 채워라."
  echo "   창을 없앴으면 표에서도 지우고 «없앤 것» 절에 사유를 남겨라."
  echo "   기준 = revert 커밋 하나로 원상복구되나? «예»면 창을 세우지 마라(오너 결정 2026-09-09)."
  exit 1
fi

# 표에 «되돌릴 수 있나» 칸이 빈 줄이 있으면 판정을 안 한 것이다
BLANK=$(grep -E '^\| *[①②③④⑤⑥⑦⑧⑨⑩] *\|' "$TABLE" | awk -F'|' '{ if ($5 ~ /^[[:space:]]*$/) print }' | grep -c . || true)
if [ "$BLANK" -ne 0 ]; then
  echo "⛔ 전수 표에 «되돌릴 수 있나» 판정이 빈 줄 $BLANK 개 — 기준을 안 대본 창이다"
  exit 1
fi

echo "확인 창 OK — 훅 $ACTUAL 개가 전수 표와 일치하고, 전부 «되돌릴 수 있나» 판정이 있다"
