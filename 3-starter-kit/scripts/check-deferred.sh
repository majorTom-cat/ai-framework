#!/usr/bin/env bash
# «미룬 일»이 카드 번호 없이 문장으로만 남았는지 본다 — CI 잡 `deferred-check` 가 부른다.
#
# 왜: «후속 카드로»·«범위 밖»·«STEP N 에서 정한다»는 문장은 **그 자리에서 할 일을 치우는 효과**만 있고,
#   카드가 실제로 생겼는지는 아무도 안 본다. 2026-09-17 bnsone 1차 요구 전수 대조 실측: 예고만 되고 안 생긴
#   카드 11건 · 분해안 미발행 5건 · «범위 밖»으로 뺀 1차 기능 3개가 추적 0 이었다.
#
# 판정: 미룸 문구가 든 줄을, 문구 «뒤»를 ` · `(앞뒤 공백 있는 가운뎃점)·`;` 로 나눠 **조각마다** `#숫자` 가 있어야 한다.
#   한 줄에 카드 하나만 달고 나머지를 흘리는 모양(「범위 밖: A(#280) · B(#279) · C」)이 실제 사고라 줄 단위로는 못 잡는다.
#   카드가 필요 없는 미룸이면 그 조각에 `(카드 불요: 사유)` 를 적는다 — 사유 없는 표시는 인정하지 않는다.
#
# 대상 = docs/ 중 «우리가 쓰는 문서»뿐: `_` 로 시작하는 파일(digest·STEP_INDEX) · 06 이후 STEP · adr · 그 밖 docs 바로 밑 파일.
#   빼는 것 = 기획자 원문(`docs/0[0-5]_*/` 의 `_` 아닌 파일 — 우리가 못 고친다) · 00_Guide(일반 안내문) · inbox · friction 류(기록).
#
# 사용: bash scripts/check-deferred.sh [기준ref]      이 브랜치가 «더한 줄»만 본다(기본 origin/main 과의 갈라진 지점)
#       bash scripts/check-deferred.sh --all          대상 파일 «전체»를 본다(주기 점검용 — 옛 부채가 다 나온다)
# 종료: 0 = 없음 · 1 = 번호 없는 미룸이 있다 · 2 = 판정 불능
set -u

MODE=diff; REF=origin/main
case "${1:-}" in
  --all) MODE=all ;;
  "") ;;
  *) REF="$1" ;;
esac

PREFIX=$(git rev-parse --show-prefix 2>/dev/null) || { echo "⛔ 판정 불능 — git 저장소 안이 아니다."; exit 2; }
if [ -n "$PREFIX" ]; then
  echo "⛔ 판정 불능 — repo 루트가 아니라 '$PREFIX' 에서 돌았다(대상 경로는 루트 기준이다). 루트로 옮겨 다시 돌려라."
  exit 2
fi

# 대상 경로 판정 — 표준입력으로 경로를 받아 대상만 내보낸다.
filter_paths() {
  grep -E '^docs/.*\.md$' \
    | grep -vE '^docs/(00_Guide|inbox)/' \
    | grep -vE '(^|/)friction[^/]*\.md$' \
    | grep -vE '^docs/0[0-5]_[^/]+/(.*/)?[^_/][^/]*$'
}

# 미룸 문구. 넓게 잡을수록 거짓양성이 늘어 사람이 표시를 남발한다 — 실제로 «할 일을 치운» 모양만 둔다.
#   ⚠️맨 «범위 밖»은 넣지 않는다 — 업무 용어(「조회 범위 밖 일정」·「범위 밖은 목록에 안 나온다」)와 겹친다(bnsone 실측).
#   «이번 일에서 뺐다»는 모양만 잡는다: 「범위 밖(후속)」「범위 밖(2차)」「이번 범위 밖」「범위 밖으로 뺀다」.
PAT='후속 ?(카드|과제|작업|MR)|\(후속\)|별도 ?(카드|과제)|범위 밖\**\s*\((후속|[0-9]+차|차기)|이번 (카드 )?범위 밖|범위 밖으로 (뺀|미룬|둔)|나중에 (카드|처리)|착수 직전 ?ADR|STEP ?[0-9]+ ?(에서|로) (정한다|결정|처리|다룬다|미룬다)'

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

if [ "$MODE" = all ]; then
  git -c core.quotepath=false ls-files docs | filter_paths > "$TMP/files"
  : > "$TMP/lines"
  while IFS= read -r f; do
    grep -nE "$PAT" "$f" 2>/dev/null | sed "s|^|$f:|" >> "$TMP/lines"
  done < "$TMP/files"
  echo "대상 = 파일 전체 ($(wc -l < "$TMP/files" | tr -d ' ')개)"
else
  if ! git rev-parse --verify --quiet "$REF" >/dev/null; then
    echo "⛔ 판정 불능 — 기준 ref '$REF' 를 못 찾았다 (CI 면 GIT_DEPTH: 0 과 git fetch 를 확인하라)"; exit 2
  fi
  MB=$(git merge-base HEAD "$REF" 2>/dev/null) || { echo "⛔ 판정 불능 — '$REF' 와 갈라진 지점을 못 찾았다."; exit 2; }
  git -c core.quotepath=false diff --name-only --diff-filter=AM "$MB" HEAD -- docs | filter_paths > "$TMP/files"
  : > "$TMP/lines"
  while IFS= read -r f; do
    # 더한 줄만(+) — 줄 번호는 새 판 기준
    git -c core.quotepath=false diff -U0 "$MB" HEAD -- "$f" | awk -v F="$f" '
      /^@@/ { split($3, a, ","); n = substr(a[1], 2) + 0; next }
      /^\+\+\+/ { next }
      /^\+/ { print F ":" n ":" substr($0, 2); n++ }
    ' | grep -E "^[^:]+:[0-9]+:.*($PAT)" >> "$TMP/lines" || true
  done < "$TMP/files"
  echo "대상 = 이 브랜치가 더한 줄 (기준 $REF · 갈라진 지점 $(git rev-parse --short "$MB") · 파일 $(wc -l < "$TMP/files" | tr -d ' ')개)"
fi

# 조각 판정 — 문구가 처음 나온 자리부터 뒤를 나눈다.
python3 - "$TMP/lines" "$PAT" > "$TMP/bad" <<'PY' || exit 2
import re, sys
path, pat = sys.argv[1], sys.argv[2]
rx = re.compile(pat)
card = re.compile(r'#\d+')
waive = re.compile(r'\(카드 불요:\s*[^\s)]')  # 사유가 비면(`(카드 불요:)`) 인정하지 않는다
for raw in open(path, encoding='utf-8'):
    raw = raw.rstrip('\n')
    f, n, text = raw.split(':', 2)
    m = rx.search(text)
    if not m:
        continue
    tail = text[m.start():]
    parts = [p for p in re.split(r' · |;', tail) if p.strip()]
    missing = [p.strip() for p in parts if not card.search(p) and not waive.search(p)]
    if missing:
        frag = missing[0]
        if len(frag) > 80:
            frag = frag[:80] + '…'
        print(f'{f}:{n}: {frag}')
PY

CNT=$(wc -l < "$TMP/bad" | tr -d ' ')
SEEN=$(wc -l < "$TMP/lines" | tr -d ' ')
echo "──── 미룸 문구 ${SEEN}줄 검사 · 번호 없는 조각이 든 줄 ${CNT}줄"
if [ "$CNT" = 0 ]; then
  echo "번호 없는 미룸 없음 — OK"
  exit 0
fi
cat "$TMP/bad"
echo "⛔ 위 줄은 «미룬다»고만 적고 카드 번호가 없다. 조각마다 ①카드를 만들어 #번호를 달거나 ②카드가 필요 없으면 '(카드 불요: 사유)' 를 적어라."
echo "   왜: 번호 없는 미룸은 아무도 다시 안 본다(2026-09-17 bnsone 실측 19건 추적 0)."
exit 1
