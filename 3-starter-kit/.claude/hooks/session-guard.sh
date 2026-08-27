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
#   ② PreToolUse   : **다른 폴더로 cd 해서** HEAD를 옮기는 명령(checkout/switch/pull/reset/merge)을 알린다.
#      남의 폴더에 cd 로 들어가는 세션은 그 폴더에서 SessionStart 를 겪지 않는다 — 재발 건이 정확히 이 경로다.
#      훅은 **세션의 project dir 것만 로드**되므로, 남의 repo 훅은 그 세션을 막지 못한다. 그래서 ②는 내 쪽에 있어야 한다.
#
# 규약: PreToolUse 는 **ask 아니면 무음**(check-push.sh 와 동일 — allow·deny 금지, 비정상 종료 금지).
#       SessionStart 는 평문 한 줄(컨텍스트로 들어간다).
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
  printf '%s' "$$"   # 최후 폴백 — 어차피 경고 전용이라 오탐이 나도 안전하다
}

# ── 죽은 항목 청소 + 살아있는 '남의' 항목만 표준출력으로 ──
live_others() { # $1=lock 경로  $2=내 pid
  [ -f "$1" ] || return 0
  local tmp="$1.tmp$$"; : > "$tmp" 2>/dev/null || return 0
  while IFS="$(printf '\t')" read -r pid br ts dir; do
    [ -z "${pid:-}" ] && continue
    kill -0 "$pid" 2>/dev/null || continue          # 끝난 세션 = 버린다
    printf '%s\t%s\t%s\t%s\n' "$pid" "${br:-?}" "${ts:-?}" "${dir:-?}" >> "$tmp"
    [ "$pid" = "$2" ] && continue
    printf '%s\t%s\t%s\t%s\n' "$pid" "${br:-?}" "${ts:-?}" "${dir:-?}"   # 남의 것만 보고
  done < "$1"
  mv -f "$tmp" "$1" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# ── repo 루트 찾기(아니면 빈 문자열) ──
repo_root() { git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null; }

MODE="${1:-check}"
MYPID=$(my_pid)

# ══════════════════ ① SessionStart — 등록 + 점유 경고 ══════════════════
if [ "$MODE" = "register" ]; then
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
    echo "   → 사용자에게 알리고 확인받아라. 계속하려면 별도 워크트리나 클론을 쓴다."
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
printf '%s' "$CMD" | grep -Eiq '(^|[;&|(]|\\n|\\r|\\t)[[:space:]]*git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(checkout|switch|pull|reset|merge|rebase)([[:space:]]|$|"|\\)' || exit 0

# 대상 디렉터리: `cd <경로>` 또는 `git -C <경로>` 가 있으면 그것, 없으면 현재 폴더(=내 project dir → 남의 것 아님)
TARGET=$(printf '%s' "$CMD" | sed -nE 's/.*(^|[;&|(]|\\n)[[:space:]]*cd[[:space:]]+"?([^"[:space:];&|]+)"?.*/\2/p' | tail -1)
[ -z "$TARGET" ] && TARGET=$(printf '%s' "$CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+"?([^"[:space:];&|]+)"?.*/\1/p' | tail -1)
[ -z "$TARGET" ] && exit 0
case "$TARGET" in "~"*) TARGET="$HOME${TARGET#\~}";; esac
[ -d "$TARGET" ] || exit 0

ROOT=$(repo_root "$TARGET"); [ -z "$ROOT" ] && exit 0
MYROOT=$(repo_root "${CLAUDE_PROJECT_DIR:-.}")
[ "$ROOT" = "$MYROOT" ] && exit 0        # 내 repo 면 ①이 담당한다

OTHERS=$(live_others "$ROOT/$LOCKREL" "$MYPID")
[ -z "$OTHERS" ] && exit 0

WHO=$(printf '%s' "$OTHERS" | head -1 | awk -F'\t' '{printf "pid %s 브랜치 %s 시작 %s", $1, $2, $3}')
# 사유문에 " 와 \ 를 쓰지 마라 — JSON 이 깨진다.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 남의 작업 폴더의 HEAD를 옮기려 한다: %s — 다른 세션이 점유 중(%s). 그 세션의 체크아웃이 발밑에서 바뀐다. 별도 워크트리나 GitLab 웹에서 하거나, 상대 세션에 먼저 확인하라."}}\n' "$ROOT" "$WHO"
exit 0
