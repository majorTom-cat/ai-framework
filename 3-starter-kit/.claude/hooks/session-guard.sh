#!/usr/bin/env bash
# 워킹트리 점유 감지 훅 — 같은 클론을 두 세션이 동시에 쓰는 것을 **경고**한다(차단하지 않는다).
#
# 왜 있나: CLAUDE.md '같은 클론에 세션 둘 금지'는 **규칙만 있고 감지 장치가 없었다.**
#   2026-08-13 실사고 2건(한 세션의 커밋이 다른 세션 작업에 섞임 · 카드가 엉뚱한 MR에 실림) → 그때 규칙 신설.
#   2026-08-27 **재발**: 킷 세션이 bnsone 클론의 HEAD를 하루에 6회 이동했다(그쪽 세션이 작업 중).
#   피해 0이었지만 그건 상대가 커밋 전에 상태를 재확인해서지 장치가 막아서가 아니다. 14일 만에 같은 구멍.
#
# ★두 조각이 필요하다 — ①만으로는 재발 건을 못 잡는다:
#   ① SessionStart : 이 클론을 이미 다른 살아있는 세션이 점유 중이면 알린다.
#   ② PreToolUse   : **다른 폴더로 cd 해서**(또는 `git -C` 로) HEAD를 옮기는 명령(checkout/switch/pull/reset/merge/rebase)을 알린다.
#      남의 폴더에 cd 로 들어가는 세션은 그 폴더에서 SessionStart 를 겪지 않는다 — 재발 건이 정확히 이 경로다.
#      훅은 **세션의 project dir 것만 로드**되므로, 남의 repo 훅은 그 세션을 막지 못한다. 그래서 ②는 내 쪽에 있어야 한다.
#
# 규약: PreToolUse 는 **ask 아니면 무음**(check-push.sh 와 동일 — allow·deny 금지, 비정상 종료 금지).
#       SessionStart 는 평문 한 줄(컨텍스트로 들어간다).
#
# ⚠️ **한계 — "장치가 있으니 이제 안전하다"고 읽지 마라**(bnsone 리뷰 지적, 2026-08-27):
#   ㉠ 경고는 **점유한 쪽이 잠금에 등록돼 있어야** 뜬다. 등록은 SessionStart·PreCompact 에서만 일어나므로
#      **이 훅이 깔리기 전에 시작된 세션은 잠금에 없다** → 그 세션이 점유 중이어도 ②는 무음이다.
#      양쪽 세션이 모두 이 훅 배포 이후에 시작돼야 온전히 작동한다.
#   ㉡ 세션 pid 를 못 찾으면(=CLAUDE_PID 없고 조상에도 claude 없음) **등록을 건너뛰고 그 사실을 말한다.**
#      옛 판(2026-08-27 초안)은 `$$`(훅 서브셸)로 등록했는데, 그건 즉시 죽어 다음 읽기에서 청소되므로
#      **그 세션이 조용히 미등록 상태**가 됐다 — 안전 실패지만 보이지 않는 실패라 더 나쁘다.
#   즉 이 훅은 **보조 장치**다. 1차 방어는 여전히 CLAUDE.md 규칙("남의 클론에서 HEAD 옮기지 마라")이다.
# 잠금 파일: <repo>/.claude/.session-lock — `pid \t 브랜치 \t 시각 \t 세션 project dir` (gitignore 대상).
# 세션 식별: $CLAUDE_PID(= claude 프로세스 pid, `kill -0`으로 생존 확인). 없으면 조상에서 claude 를 찾아 폴백.

set -u
LOCKREL=".claude/.session-lock"

# ── 내 세션 pid ──
my_pid() {
  if [ -n "${CLAUDE_PID:-}" ] && kill -0 "${CLAUDE_PID}" 2>/dev/null; then printf '%s' "$CLAUDE_PID"; return; fi
  local p; p=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')
  local i=0
  while [ -n "$p" ] && [ "$p" != "1" ] && [ "$i" -lt 6 ]; do
    case "$(ps -o comm= -p "$p" 2>/dev/null)" in *claude*) printf '%s' "$p"; return;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); i=$((i+1))
  done
  return 1   # 못 찾음 — 등록은 건너뛰고 그 사실을 말한다(위 한계 ㉡). `$$` 로 등록하면 조용히 미등록이 된다.
}

# ── 죽은 항목 청소 + 살아있는 '남의' 항목만 표준출력으로 ──
live_others() { # $1=lock 경로  $2=내 pid
  # ★청소(쓰기)가 안 되더라도 **읽기는 반드시 한다** — 남의 repo 의 잠금은 이쪽에 쓰기 권한이 없을 수 있는데,
  #   옛 판은 tmp 생성 실패에 return 0 이라 «점유 중인데 무음»이 됐다(2026-08-27 리뷰 지적).
  [ -f "$1" ] || return 0
  local tmp="$1.tmp$$"; local can_clean=1
  : > "$tmp" 2>/dev/null || can_clean=""
  while IFS="$(printf '\t')" read -r pid br ts dir; do
    [ -z "${pid:-}" ] && continue
    kill -0 "$pid" 2>/dev/null || continue          # 끝난 세션 = 버린다
    [ -n "$can_clean" ] && printf '%s\t%s\t%s\t%s\n' "$pid" "${br:-?}" "${ts:-?}" "${dir:-?}" >> "$tmp"
    [ "$pid" = "$2" ] && continue
    printf '%s\t%s\t%s\t%s\n' "$pid" "${br:-?}" "${ts:-?}" "${dir:-?}"   # 남의 것만 보고
  done < "$1"
  [ -n "$can_clean" ] && { mv -f "$tmp" "$1" 2>/dev/null || rm -f "$tmp" 2>/dev/null; }
  return 0
}

# ── repo 루트 찾기(아니면 빈 문자열) ──
repo_root() { git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null; }

MODE="${1:-check}"
MYPID=$(my_pid) || MYPID=""

# ══════════════════ ① SessionStart — 등록 + 점유 경고 ══════════════════
if [ "$MODE" = "register" ]; then
  if [ -z "$MYPID" ]; then
    echo "⚠️ 세션 pid를 찾지 못해 워킹트리 점유 등록을 건너뛴다 — 이 세션은 다른 세션에게 보이지 않는다(session-guard 한계 ㉡)."
    exit 0
  fi
  ROOT=$(repo_root "${CLAUDE_PROJECT_DIR:-.}") || exit 0
  [ -z "$ROOT" ] && exit 0
  LOCK="$ROOT/$LOCKREL"
  mkdir -p "$(dirname "$LOCK")" 2>/dev/null || exit 0
  OTHERS=$(live_others "$LOCK" "$MYPID")
  BR=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
  grep -v "^$MYPID	" "$LOCK" > "$LOCK.self$$" 2>/dev/null || : > "$LOCK.self$$"
  printf '%s\t%s\t%s\t%s\n' "$MYPID" "$BR" "$(date '+%Y-%m-%d %H:%M')" "${CLAUDE_PROJECT_DIR:-?}" >> "$LOCK.self$$"
  mv -f "$LOCK.self$$" "$LOCK" 2>/dev/null || rm -f "$LOCK.self$$" 2>/dev/null
  if [ -n "$OTHERS" ]; then
    echo "⚠️ 이 클론을 다른 세션이 이미 쓰고 있다 — CLAUDE.md '같은 클론에 세션 둘 금지' 위반 상태다."
    printf '%s\n' "$OTHERS" | while IFS="$(printf '\t')" read -r p b t d; do
      echo "   · pid $p · 브랜치 $b · 시작 $t"
    done
    echo "   → 사용자에게 **한 줄로 알린 뒤 하던 일(브리핑·조회)을 계속하라** — 조회는 남의 세션에 영향이 없다."
    echo "     확인은 여기가 아니라 **HEAD 를 옮기기 직전**에 받는다(②가 그 자리에서 묻는다). 별도 워크트리·클론 권장."
  fi
  exit 0
fi

# ══════════════════ ② PreToolUse — 남의 폴더 HEAD 이동 감지 ══════════════════
INPUT=$(cat 2>/dev/null || true)
# check-push.sh 와 동일한 추출 방식(닫는 따옴표에서 끊고, 형식이 어긋나면 옛 방식 폴백 — 무음화 방지)
CMD=$(printf '%s' "$INPUT" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p')
[ -z "$CMD" ] && CMD=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)/\1/p')
[ -z "$CMD" ] && exit 0

# HEAD 를 옮기는 git 명령인가 (명령 경계 기준 — check-push.sh 와 같은 이유로 \n·\r·\t 포함)
printf '%s' "$CMD" | grep -Eiq '(^|[;&|(]|\\n|\\r|\\t)[[:space:]]*git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(checkout|switch|pull|reset|merge|rebase|restore)([[:space:]]|$|"|\\)' || exit 0
# ★`restore` 는 2026-09-10 에 넣었다 — `git checkout -- <경로>` 와 «완전히 같은 일»(저장 안 된 변경 버리기)인데
#   목록에 없어 통째로 무음이었다. 자기시험이 잡았다(그 전엔 35 OK 로 초록이었다).

# 대상 디렉터리: `git -C <경로>` 가 있으면 **그것이 우선**, 없으면 `cd <경로>`, 그것도 없으면 현재 폴더(=내 project dir → 남의 것 아님)
# ★순서 주의: `cd A && git -C B checkout` 은 HEAD 가 **B** 에서 움직인다. cd 를 먼저 보면 A 를 보고 B 를 놓친다(2026-08-27 리뷰 지적).
TARGET=$(printf '%s' "$CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+"?([^"[:space:];&|]+)"?.*/\1/p' | tail -1)
# ★cd 폴백은 **그 git 명령 앞쪽**에서 찾는다 — 뒤에 붙은 cd 까지 세면 판정이 뒤집힌다:
#   `cd 남의폴더 && git checkout main && cd 내폴더` 가 '내 repo'로 읽혀 무음이 됐다(2026-08-27 리뷰 지적).
if [ -z "$TARGET" ]; then
  HEAD_CMD=$(printf '%s' "$CMD" | sed -E 's/(git[[:space:]]+(checkout|switch|pull|reset|merge|rebase|restore)([[:space:]]|$)).*/\1/')
  TARGET=$(printf '%s' "$HEAD_CMD" | sed -nE 's/.*(^|[;&|(]|\\n)[[:space:]]*cd[[:space:]]+"?([^"[:space:];&|]+)"?.*/\2/p' | tail -1)
fi
MYROOT=$(repo_root "${CLAUDE_PROJECT_DIR:-.}")
# ★대상 경로가 없다(= 그냥 `git checkout`) → **내 클론**이다. 옛 판은 여기서 «①이 담당한다»며 나갔는데,
#   2026-08-31 개정으로 ①은 «정보 한 줄»이 됐다(세션 시작의 정지가 정보량 0이라 오너 지적) —
#   그러면 «같은 클론 두 세션»(2026-08-13 실사고)의 확인 지점이 **어디에도 남지 않는다.**
#   규칙이 «HEAD 이동 직전에 확인받아라»라고 말하는 이상 장치도 거기 있어야 한다. 점유가 없으면 여전히 무음.
if [ -z "$TARGET" ]; then
  ROOT="$MYROOT"
else
  case "$TARGET" in "~"*) TARGET="$HOME${TARGET#\~}";; esac
  [ -d "$TARGET" ] || exit 0
  ROOT=$(repo_root "$TARGET")
fi
[ -z "$ROOT" ] && exit 0

OTHERS=$(live_others "$ROOT/$LOCKREL" "$MYPID")
# pid 를 못 찾았을 때(MYPID 빈 문자열) 는 pid 비교가 아무것도 못 거른다 — 내 project dir 로 등록된 항목을 빼서
# 자기 점유를 '남의 세션'으로 오경고하지 않게 한다(2026-08-27 리뷰 지적 ㉢. 게이트의 1순위는 정상 작업에 침묵).
if [ -z "$MYPID" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  OTHERS=$(printf '%s' "$OTHERS" | awk -F'\t' -v me="$CLAUDE_PROJECT_DIR" '$4 != me')
fi
[ -z "$OTHERS" ] && exit 0

WHO=$(printf '%s' "$OTHERS" | head -1 | awk -F'\t' '{printf "pid %s 브랜치 %s 시작 %s", $1, $2, $3}')
# ★보간되는 값도 JSON 을 깨뜨린다 — 고정 문구만 조심해선 부족하다(2026-08-27 리뷰).
#   경로·브랜치명에 " 나 \ 가 있으면 JSON 이 깨지고 훅 판정이 **통째로 버려진다**(= 이 파일이 막으려던 그 무음).
#   경고문에 정확한 글자가 필요한 게 아니므로 **위험 글자는 '로 바꿔** 흘린다(escape 보다 단순·확실).
sanitize() { printf '%s' "$1" | tr '"\\' "''" | tr -d '\000-\037'; }

# ★2026-09-10 — «HEAD 이동»과 «파일 되돌리기»를 가른다. 둘 다 물어야 하지만 **문구가 달라야 한다.**
#   오너가 찍어 보낸 창은 `git checkout -- scripts/foo.cjs`(돌연변이 시험)였는데 문구는 「HEAD를 옮기려 한다」였다 —
#   그 명령은 HEAD 를 **안 옮긴다.** 틀린 문구는 창을 도장찍기로 만든다(사람이 「또 그 소리」로 읽고 누른다).
#   되돌릴 수 있나? 파일 되돌리기도 **아니오**다(미저장 변경은 revert 로 못 되돌린다) — 그래서 ask 는 유지한다.
RESTORE=""
printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(checkout[[:space:]]+--[[:space:]]|restore[[:space:]])' && RESTORE=1
# `--` 없이 경로만 준 형태(`git checkout scripts/foo.cjs`)도 파일 되돌리기다 — 슬래시나 확장자로 가른다.
printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?checkout[[:space:]]+[^-][^[:space:]]*(/|\.[A-Za-z0-9]+)([[:space:]]|$)' && RESTORE=1

# ★버릴 것이 없으면 묻지 마라 — `git checkout -- <경로>` 는 그 파일이 안 바뀌었으면 아무 일도 안 한다.
#   「되돌릴 수 있나」의 답이 «버릴 게 없다 = 잃을 것도 없다»이므로 창을 세울 이유가 없다.
if [ -n "$RESTORE" ]; then
  RPATHS=$(printf '%s' "$CMD" | sed -nE 's/.*git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(checkout[[:space:]]+(--[[:space:]]+)?|restore[[:space:]]+)([^;&|]*)/\4/p' \
           | tr ' ' '\n' | grep -E '/|\.[A-Za-z0-9]+$' | grep -v '^-' | head -5)
  if [ -n "$RPATHS" ] && command -v git >/dev/null 2>&1; then
    DIRTY=""
    for f in $RPATHS; do
      git -C "$ROOT" diff --quiet -- "$f" 2>/dev/null || DIRTY=1
      git -C "$ROOT" diff --cached --quiet -- "$f" 2>/dev/null || DIRTY=1
    done
    [ -z "$DIRTY" ] && exit 0        # 바뀐 게 없다 = 무해 → 무음
  fi
fi

if [ -n "$RESTORE" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 이 파일의 «저장 안 된 변경»을 버린다(HEAD 는 안 옮긴다): %s — 이 클론을 다른 세션이 쓰는 중이다(%s). 버리는 것이 그 세션의 편집이면 **revert 로 못 되돌린다.** 돌연변이 시험처럼 «일부러 고쳤다 되돌리는» 작업은 이 클론이 아니라 워크트리·스크래치패드에서 해라(rules/verify.md 3절)."}}\n' "$(sanitize "$ROOT")" "$(sanitize "$WHO")"
elif [ "$ROOT" = "$MYROOT" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 이 클론을 다른 세션이 쓰는 중인데 HEAD를 옮기려 한다: %s — 점유 중(%s). 한쪽의 checkout이 다른 쪽 커밋을 남의 브랜치에 얹는다(2026-08-13 실사고). 별도 워크트리·클론을 쓰거나, 그 세션이 끝났는지 확인하라."}}\n' "$(sanitize "$ROOT")" "$(sanitize "$WHO")"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 남의 작업 폴더의 HEAD를 옮기려 한다: %s — 다른 세션이 점유 중(%s). 그 세션의 체크아웃이 발밑에서 바뀐다. 별도 워크트리나 GitLab 웹에서 하거나, 상대 세션에 먼저 확인하라."}}\n' "$(sanitize "$ROOT")" "$(sanitize "$WHO")"
fi
exit 0
