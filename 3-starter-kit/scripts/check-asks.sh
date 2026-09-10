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

# ★★★2026-09-10 — 여기까지가 «`.claude/hooks/` 안의 창»이다. 그런데 **창은 거기에만 있는 게 아니다.**
#   설정 파일(`settings.json`·`settings.local.json`)의 `hooks` 항목에는 **명령이 통째로 인라인**으로 들어갈 수
#   있고, 거기 적힌 `permissionDecision:ask` 도 똑같이 모든 세션을 세운다. 위 대조는 그 창을 **한 개도 못 본다.**
#   실측: 오너가 「automode 인데 또 떴다」며 보낸 창의 정체가 바로 그것이었다 — bnsone 작업 폴더의
#   `settings.local.json` 에 인라인 훅 하나가 `git status --porcelain`(추적 안 하는 파일까지 센다)로 물어
#   `?? .agents/` 두 줄 때문에 «건드리지도 않는 파일»을 이유로 창을 세우고 있었다.
#   ⇒ 「전수 표」라고 적어 놓고 전수가 아니었다. **세는 곳을 늘린다.**
LOCAL_HITS=""
for f in "$ROOT/.claude/settings.json" "$ROOT/.claude/settings.local.json" "$HOME/.claude/settings.json"; do
  [ -f "$f" ] || continue
  # ★잣대가 «실물 줄 모양»과 달라 0이 나온 것을 그 자리에서 잡았다(2026-09-10):
  #   설정 파일 안의 훅 명령은 **JSON 문자열**이라 따옴표가 `\"` 로 이스케이프된다 —
  #   `permissionDecision"` 로 찾으면 실물에서 **한 건도 안 걸린다.** `\\?` 로 둘 다 받는다.
  n=$(grep -Eo 'permissionDecision\\?"[[:space:]]*:[[:space:]]*\\?"ask' "$f" 2>/dev/null | grep -c . || true)
  [ "$n" -gt 0 ] && LOCAL_HITS="${LOCAL_HITS}${f}: ${n}개
"
done
if [ -n "$LOCAL_HITS" ]; then
  echo "⛔ 설정 파일 «안에» 직접 적힌 확인 창이 있다 — 전수 표가 못 보는 자리다"
  printf '%s' "$LOCAL_HITS" | sed 's/^/   /'
  echo "   훅 파일(.claude/hooks/**)로 옮기고 _reference/asks.md 표에 줄을 더하거나, 기준에 안 맞으면 지워라."
  echo "   기준 = revert 커밋 하나로 원상복구되나? «예»면 창을 세우지 마라."
  echo "   ★이 창들도 «자동 모드보다 위»라 모드로는 못 건너뛴다 — 목록에 없으면 아무도 못 찾는다."
  exit 1
fi

echo "확인 창 OK — 훅 $ACTUAL 개가 전수 표와 일치하고, 전부 «되돌릴 수 있나» 판정이 있다"
echo "  (설정 파일 안의 인라인 창도 함께 봤다 — 0개)"
