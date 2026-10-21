#!/usr/bin/env bash
# 「쌓이는 파일」(friction·CHANGELOG 류)이 이 브랜치에서 항목을 잃었는지 본다 — CI 묶음 잡 `mr-checks` 의 `append-only-check` 검사(`ci-job-append-only-check.sh`)가 부른다.
#
# 왜 CI 에서도 봐야 하나: `check-append-only.py` 는 «올리기 전에 사람이 돌려라»로만 걸려 있었다(`CLAUDE.md` 킷동기 절).
#   그런데 그 검사기가 태어난 사고(2026-09-10 `!451`)의 원인이 **사람이 판정을 넘긴 것**이다 — 방어를 같은 층
#   (사람의 기억)에 두면 같은 자리에서 또 무너진다. `_reference/append-only.md` 는 「CI 는 커밋 전의 main 을
#   모른다」는 이유로 CI 잡을 «의도적으로» 안 만들었는데, **그 이유가 틀렸다**(아래).
#
# ★기준은 «merge base» 가 아니라 «대상 브랜치의 지금 tip» 이다 — 이 둘을 헷갈리면 검사가 통째로 헛돈다.
#   실사고 모양 = 「내가 사본을 받아 둔 뒤, 커밋하기 전에 남이 main 에 한 줄 넣었다」. 그 줄은 merge base 에
#   없으니 merge base 기준으로는 «잃은 것»이 아니다(조용히 통과). tip 기준이어야 잡힌다.
#   2026-09-16 실측(픽스처): merge base 기준 = **exit 0**(놓침) · tip 기준 = **exit 1**(잃은 줄 지목).
#   자기시험 `test-check-append-only-git.sh` 의 D·G 케이스가 이 차이를 고정한다.
#
# 한계(알고 쓴다): 파이프라인이 돈 «뒤» 머지 직전까지 사이에 남이 또 머지하면 그 줄은 못 본다.
#   그래서 이 잡은 사람 절차를 대체하지 않고 **겹친다**(사람 = 올리기 전 · 기계 = MR 에서).
#
# 사용: bash scripts/check-append-only-git.sh [대상ref]     (기본 origin/main)
# 종료: 0 = 잃은 항목 없음 · 1 = 잃었다 · 2 = 판정 불능(기준 ref 가 없다 — 통과로 치지 않는다)
set -u

REF="${1:-origin/main}"

# 검사 대상 — 「파일:보관파일」. 보관이 없으면 콜론 뒤를 비운다. **배포처는 이 목록만 고친다.**
PAIRS='docs/friction.md:docs/friction-보관.md
docs/friction-보관.md:'

# `command -v` 로 보지 마라 — Windows 스토어 바로가기 python3 은 «있다»로 보이고 실행하면 exit 49 다(배포처 bnsone).
python3 -c 'import sys' >/dev/null 2>&1 || { echo "⛔ 판정 불능 — python3 이 실행되지 않는다(없거나 Windows 스토어 바로가기). 파이썬을 설치하라."; exit 2; }

HERE=$(cd "$(dirname "$0")" && pwd) || exit 2
TOOL="$HERE/check-append-only.py"
[ -f "$TOOL" ] || { echo "⛔ 판정 불능 — 검사기가 없다: $TOOL"; exit 2; }

# ★repo 루트에서만 성립한다 — PAIRS 는 루트 기준 경로다. 하위 폴더에서 돌면 파일은 `-f` 로 «보이는데»
#   `git show <ref>:<경로>` 만 빗나가 **«신규»로 오판하고 «검사 0건 · OK»** 를 찍는다. 실패의 모양이 성공과 같아진다.
#   2026-09-16 실측: 킷 저장소의 `3-starter-kit/` 안에서 돌렸더니 friction 두 파일 모두 «신규» 건너뜀 + OK 였다.
PREFIX=$(git rev-parse --show-prefix 2>/dev/null) || {
  echo "⛔ 판정 불능 — git 저장소 안이 아니다."; exit 2; }
if [ -n "$PREFIX" ]; then
  echo "⛔ 판정 불능 — repo 루트가 아니라 '$PREFIX' 에서 돌았다(PAIRS 는 루트 기준 경로다)."
  echo "   ①repo 루트로 옮겨 다시 돌려라."
  echo "   ②킷처럼 이 스크립트가 하위 폴더에 놓인 곳이라면 여기서는 돌리는 것이 아니다 — 이 파일은 «배포처 repo 루트»(CI 묶음 잡 mr-checks 의 append-only-check 검사) 전용이고, 사람이 손으로 볼 때는 `scripts/check-append-only.py` 에 두 경로를 직접 준다(_reference/append-only.md)."
  exit 2
fi

# ★기준 ref 가 없으면 «통과»가 아니라 «판정 불능»이다(rules/verify.md §1 — 준비 실패를 합격으로 읽지 마라).
if ! git rev-parse --verify --quiet "$REF" >/dev/null; then
  echo "⛔ 판정 불능 — 기준 ref '$REF' 를 못 찾았다 (CI 면 GIT_DEPTH: 0 과 git fetch 를 확인하라)"
  exit 2
fi

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

RC=0; CHECKED=0; SKIPPED=0; OLDFAIL=0
echo "기준 ref = $REF ($(git rev-parse --short "$REF"))"

while IFS= read -r pair; do
  [ -n "$pair" ] || continue
  F="${pair%%:*}"
  MOVED="${pair#*:}"

  if [ ! -f "$F" ]; then
    # ★이 트리에 없는 이유가 둘이고, 하나는 통과·하나는 사고다. 갈라야 한다:
    #   ⑴이 파일이 «생기기 전»에서 갈라진 낡은 브랜치 — 통과(배포처에 실제로 그런 브랜치가 산다)
    #   ⑵있던 파일을 이 브랜치가 «지웠다» — 누적 파일 통째 삭제라 막아야 한다
    #   가르는 잣대 = 갈라진 지점(merge base)에 그 파일이 있었나.
    MB=$(git merge-base HEAD "$REF" 2>/dev/null || echo "")
    if [ -n "$MB" ] && git cat-file -e "$MB:$F" 2>/dev/null; then
      echo "════ $F"
      echo "⛔ 갈라진 지점에 있던 누적 파일이 이 트리에서 통째로 사라졌다 — 지우지 말고 보관 파일로 옮겨라."
      CHECKED=$((CHECKED + 1)); RC=1; continue
    fi
    SKIPPED=$((SKIPPED + 1)); echo "· 건너뜀 — 이 트리에 없음(이 파일이 생기기 전에서 갈라진 브랜치): $F"; continue
  fi
  # 대상 브랜치에 그 파일이 없다. 여기도 두 가지이고, 하나는 조용한 사고다:
  #   ⑴이 MR 이 «처음 만든» 파일(갈라진 지점에도 없다) → 잃을 것이 없으니 통과
  #   ⑵대상 브랜치가 그 파일을 «지웠거나 이름을 바꿨다»(갈라진 지점엔 있었다) → **판정 불능**
  #     조용히 통과시키면 이 브랜치가 그 파일에서 줄을 지워도 검사가 한 번도 안 돈다(2026-09-16 재현).
  if ! git show "$REF:$F" > "$TMP/base" 2>/dev/null; then
    MB=$(git merge-base HEAD "$REF" 2>/dev/null || echo "")
    if [ -n "$MB" ] && git cat-file -e "$MB:$F" 2>/dev/null; then
      echo "════ $F"
      echo "⛔ 판정 불능 — 갈라진 지점엔 있는데 $REF 에는 없다(대상 브랜치가 지웠거나 이름을 바꿨다)."
      echo "   ①먼저 $REF 최신본을 이 브랜치에 얹어라."
      echo "   ②그래도 없으면 이 스크립트 위 PAIRS 목록을 실물에 맞춰라."
      # ★순서를 바꾸지 마라 — «목록부터 고쳐라»가 먼저 오면 사람이 목록에서 그 파일을 빼
      #   **게이트를 스스로 끄고**, 지운 줄이 초록으로 지나간다(배포처 #285 가 재현했다).
      CHECKED=$((CHECKED + 1))
      [ "$RC" = 0 ] && RC=2
      continue
    fi
    SKIPPED=$((SKIPPED + 1)); echo "· 건너뜀 — $REF 에 아직 없음(신규): $F"; continue
  fi

  echo "════ $F"
  CHECKED=$((CHECKED + 1))
  if [ -n "$MOVED" ] && [ -f "$MOVED" ]; then
    python3 "$TOOL" "$TMP/base" "$F" --moved-to "$MOVED" || { RC=1; OLDFAIL=1; }
  else
    python3 "$TOOL" "$TMP/base" "$F" || { RC=1; OLDFAIL=1; }
  fi
done <<EOF
$PAIRS
EOF

# 새 마찰 폴더(`docs/friction/` — 항목 하나 = 파일 하나)도 같은 기준(대상 브랜치 tip)으로 본다. 옛 파일 검사와 «겹쳐서» 돈다.
if [ ! -d docs/friction ] && ! git cat-file -e "$REF:docs/friction" 2>/dev/null; then
  SKIPPED=$((SKIPPED + 1)); echo "· 건너뜀 — docs/friction/ 가 기준에도 이 트리에도 없음(아직 안 쓰는 repo)"
else
  echo "════ docs/friction/ (항목별 파일)"
  python3 "$HERE/check-friction-dir.py" "$REF"
  FRC=$?
  CHECKED=$((CHECKED + 1))
  if [ "$FRC" = 1 ]; then RC=1; elif [ "$FRC" != 0 ]; then [ "$RC" = 0 ] && RC=2; fi
fi

# ★«몇 건 돌았나»를 반드시 찍는다 — «0건 통과»와 «실제 통과»는 다른 사건이다(rules/verify.md §1).
echo "──── 검사 ${CHECKED}건 · 건너뜀 ${SKIPPED}건"
if [ "$RC" = 0 ]; then
  echo "사라진 항목 없음 — OK"
elif [ "$RC" = 2 ]; then
  # ★«못 쟀다»를 «통과»로 찍지 않는다 — 실패의 모양과 성공의 모양이 같아지면 아무도 안 본다.
  echo "⛔ 판정 불능 — 위 파일을 검사하지 못했다. 통과로 치지 않는다(rules/verify.md §1)."
else
  echo "⛔ 위 파일에서 항목이 사라졌다 — 기준을 다시 받아 편집을 다시 얹어라(_reference/append-only.md)."
  # 기준에 docs/friction/ 가 이미 있는데 옛 파일 검사가 막았다 = 옛 습관으로 옛 friction.md 에 더한 브랜치일 가능성이 크다 —
  # 로그의 «편집을 다시 얹어라» 만 따르면 같은 검사에 또 막힌다(배포처 bnsone 2026-10-22 MR 2건)
  if [ "$OLDFAIL" = 1 ] && git cat-file -e "$REF:docs/friction" 2>/dev/null; then
    echo "   ↳ 옛 docs/friction.md 에 새 줄을 더했다면: 옛 파일은 기준 판으로 되돌리고(git checkout $REF -- docs/friction.md),"
    echo "     더한 줄은 python3 scripts/friction.py add 로 docs/friction/ 에 옮겨라(docs/friction-규약.md «전환 중인 브랜치»)."
  fi
fi
exit $RC
