#!/bin/bash
# 킷 → 배포처 «아직 안 간 킷 커밋»을 센다.
#
# ★왜 이 잣대인가: 두 곳의 «글»을 대조하면 배포처의 의도된 현지화(스택 경로·사내 표현)까지
#   차이로 잡혀 매번 수백 줄이 나온다(2026-09-16 실측: 파일 30개·307줄, 그중 거의 전부가 현지화).
#   그래서 글을 안 보고 **«마지막으로 넘긴 킷 커밋 이후 프레임워크 파일을 바꾼 킷 커밋»**만 센다.
#   기준점 = 배포처 커밋 메시지 규약 `킷동기: <킷 커밋해시>`(CLAUDE.md '작업 절차').
#
# 사용: bash scripts/check-kit-sync.sh <배포처 클론 경로>
# 종료: 0 = 안 간 커밋 없음 · 1 = 있음(목록 출력) · 2 = 판정 불능(«없다»가 아니다 — rules/verify.md §1)
set -u

DEP="${1:-}"
if [ -z "$DEP" ]; then
  echo "⛔ 배포처 클론 경로가 필요하다: bash scripts/check-kit-sync.sh <경로>" >&2
  exit 2
fi
if [ ! -d "$DEP/.git" ]; then
  echo "⛔ 판정 불능 — git 저장소가 아니다: $DEP" >&2
  exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 2
KIT_DIR=$(dirname "$SCRIPT_DIR")
REPO=$(git -C "$KIT_DIR" rev-parse --show-toplevel 2>/dev/null) || {
  echo "⛔ 판정 불능 — 킷이 git 저장소 안에 없다: $KIT_DIR" >&2; exit 2; }
# ★접두어는 문자열을 깎지 말고 git 에게 물어라 — macOS 임시폴더는 `/var` 와 `/private/var` 로
#   같은 곳이 두 이름이라 문자열 비교가 조용히 빗나간다(2026-09-16 이 시험 B 가 잡았다).
PREFIX=$(git -C "$KIT_DIR" rev-parse --show-prefix 2>/dev/null)
PREFIX=${PREFIX%/}                        # 빈 값 = 킷이 저장소 루트(배포된 판)

# 프레임워크 정본 = 그대로 복사되는 것들(AI-CONTEXT.md §3). 문서·CLAUDE.md 는 값이 repo 마다 달라 제외한다.
FRAMEWORK=(".claude/skills" ".claude/rules" ".claude/hooks" ".claude/workflows" "scripts" "_reference")
PATHSPEC=()
for p in "${FRAMEWORK[@]}"; do
  if [ -n "$PREFIX" ]; then PATHSPEC+=("$PREFIX/$p"); else PATHSPEC+=("$p"); fi
done

# ★제목(%s)이 아니라 «본문 전체»(%B)를 봐라 — 배포처의 실제 모양은 머지 커밋이고 표시는 본문에 있다.
# ★그리고 실물 규약은 들쭉날쭉하다 — 해시 없이 「(킷 8커밋)」처럼 적은 것이 섞인다(2026-09-16 실측).
#   그래서 최신 표시부터 거슬러 «킷에 실재하는 해시»를 찾고, 최신 것이 아니었으면 그 사실을 말한다.
# ★배포처는 «작업 폴더»가 아니라 «서버»를 봐라 — 남의 클론은 낡아 있기 마련이라 그대로 세면
#   이미 머지된 것을 «안 갔다»고 보고한다(2026-09-16 실측: 머지 직후에 3건으로 나왔다. 실제 1건).
#   HEAD 를 옮기지 않는 조회라 남의 세션에 영향이 없다. [[commit-is-not-deployed]]
DEPREF="${2:-}"
if [ -z "$DEPREF" ]; then
  git -C "$DEP" fetch origin --quiet 2>/dev/null
  if git -C "$DEP" rev-parse --verify -q origin/main >/dev/null; then DEPREF="origin/main"; else DEPREF="HEAD"; fi
fi
echo "배포처 기준 ref = $DEPREF"
MARKS=$(git -C "$DEP" log -n 20 --grep '^킷동기:' --format='%H' "$DEPREF" 2>/dev/null)
if [ -z "$MARKS" ]; then
  echo "⛔ 판정 불능 — 배포처에 «킷동기:» 커밋이 없다(한 번도 안 넘겼거나 규약을 안 썼다): $DEP" >&2
  exit 2
fi

BASE=""; SKIPPED=0; NEWEST=1
for m in $MARKS; do
  for h in $(git -C "$DEP" log -n1 --format='%B' "$m" | grep '^킷동기:' | grep -oE '[0-9a-f]{7,40}'); do
    if git -C "$REPO" cat-file -e "${h}^{commit}" 2>/dev/null; then BASE="$h"; break; fi
  done
  [ -n "$BASE" ] && break
  SKIPPED=$((SKIPPED+1)); NEWEST=0
done

if [ -z "$BASE" ]; then
  echo "⛔ 판정 불능 — «킷동기:» 표시 $(printf '%s\n' "$MARKS" | grep -c .) 개 어디에도 이 킷에 있는 해시가 없다." >&2
  echo "   다른 저장소이거나 아직 안 받았다 — 먼저 git fetch 한 뒤 다시 돌려라." >&2
  exit 2
fi
if [ "$NEWEST" -eq 0 ]; then
  echo "⚠️ 최신 «킷동기» 표시 $SKIPPED 개에 해시가 없어 그 앞 것을 기준으로 잡았다 — 실제 부채는 아래보다 적을 수 있다."
fi

# ★킷 전용 도구는 배포처에 갈 이유가 없다 — 빼지 않으면 영원히 «안 간 커밋»으로 남아 소음이 된다.
#   (이 검사기 자신과 그 시험. 배포처엔 킷 저장소가 없어 돌려도 «판정 불능»이다.)
SCRIPTS_DIR="scripts"; [ -n "$PREFIX" ] && SCRIPTS_DIR="$PREFIX/scripts"
KIT_ONLY=(":(exclude)$SCRIPTS_DIR/check-kit-sync.sh" ":(exclude)$SCRIPTS_DIR/test-check-kit-sync.sh")
LIST=$(git -C "$REPO" log --format='%h %s' "$BASE..HEAD" -- "${PATHSPEC[@]}" "${KIT_ONLY[@]}")
N=$(printf '%s\n' "$LIST" | grep -c . )

echo "기준점 = 배포처가 마지막으로 넘긴 킷 커밋 $BASE"
echo "대상   = ${FRAMEWORK[*]}"
if [ "$N" -eq 0 ]; then
  echo "킷 동기 OK — 그 뒤로 배포처에 넘길 킷 변경이 없다"
  exit 0
fi

echo "⛔ 아직 안 간 킷 커밋 $N 건:"
printf '%s\n' "$LIST" | head -20
[ "$N" -gt 20 ] && echo "   … 20건에서 잘랐다(전체 $N 건)"
exit 1
