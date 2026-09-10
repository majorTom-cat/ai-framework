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
#   ③ SessionStart : 본 클론이 main 이고 깨끗하면 **main 최신으로 따라잡는다**(아래 catchup — 2026-09-10 신설).
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

# ── ③ 본 클론 main 따라잡기 (SessionStart) ──
# 왜: 세션은 «켠 폴더»의 CLAUDE.md·스킬·훅을 읽는다. 본 클론이 main 을 안 따라가면 main 에 들어간 수리가
#   새 세션에 안 닿아 **고친 결함이 되살아난다**(2026-09-10 bnsone 본 클론 50커밋 뒤처짐 — 그날의 /handoff 가 안 보였다).
#   규칙(CLAUDE.md «main 따라잡기는 AI 가 한다»)만으로는 안 됐다 — 여러 세션이 사람에게 수동 pull 을 권했다.
# 조건은 ② 의 «앞으로 감기» 면제와 **같다**(추적 변경 0 · 스테이지 0 · 미푸시 0) + **main 체크아웃일 때만**
#   (작업 브랜치·워크트리는 건드리지 않는다). `--ff-only` 라 갈라졌으면 아무것도 안 하고 멈춘다.
#   못 따라잡으면 **이유를 한 줄로 말한다** — 조용한 실패가 이 틈을 만들었다.
# ⚠️한계: CLAUDE.md 는 이 훅보다 먼저 읽혔을 수 있다 — 그 세션은 한 판 늦다(스킬·훅은 부를 때 읽혀 바로 새 판).
catchup() { # $1=repo 루트
  local R="$1" br behind ahead why=""
  br=$(git -C "$R" symbolic-ref --quiet --short HEAD 2>/dev/null) || return 0
  [ "$br" = "main" ] || return 0
  git -C "$R" remote get-url origin >/dev/null 2>&1 || return 0
  # 네트워크가 막혀도(VPN 꺼짐 등) 세션 시작을 붙잡지 않는다 — 비밀번호·로그인 창을 띄우지 않고, 느리면 끊는다.
  if ! GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
       git -C "$R" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 fetch -q origin main >/dev/null 2>&1; then
    echo "⚠️ 본 클론 따라잡기: origin 을 못 받아왔다(네트워크·VPN?) — main 이 뒤처져 있을 수 있다. 사용자에게 한 줄로 알려라."
    return 0
  fi
  behind=$(git -C "$R" rev-list --count HEAD..origin/main 2>/dev/null) || return 0
  [ "${behind:-0}" = "0" ] && return 0
  ahead=$(git -C "$R" rev-list --count origin/main..HEAD 2>/dev/null)
  git -C "$R" diff --quiet 2>/dev/null || why="저장 안 된 변경이 있다"
  git -C "$R" diff --cached --quiet 2>/dev/null || why="스테이지된 변경이 있다"
  [ "${ahead:-x}" = "0" ] || why="main 에 미푸시 커밋이 있다"
  if [ -z "$why" ] && git -C "$R" merge -q --ff-only origin/main >/dev/null 2>&1; then
    echo "📥 본 클론을 main 최신으로 따라잡았다(${behind}커밋) — 스킬·훅은 새 판이 적용된다. 이 세션의 CLAUDE.md 는 옛 판일 수 있다."
  else
    echo "⚠️ 본 클론이 main 보다 ${behind}커밋 뒤처졌는데 못 따라잡았다 — ${why:-앞으로 감기 실패(갈라졌거나 다른 git 작업이 잠금 중)}. 사용자에게 한 줄로 알려라."
  fi
}

MODE="${1:-check}"
MYPID=$(my_pid) || MYPID=""

# ══════════════════ ① SessionStart — 등록 + 점유 경고 (+ ③ 따라잡기) ══════════════════
if [ "$MODE" = "register" ]; then
  ROOT=$(repo_root "${CLAUDE_PROJECT_DIR:-.}")
  # ★따라잡기는 등록보다 «먼저», pid 와 무관하게 — pid 를 못 찾는 세션도 옛 규칙을 읽으면 안 된다.
  [ -n "$ROOT" ] && command -v git >/dev/null 2>&1 && catchup "$ROOT"
  if [ -z "$MYPID" ]; then
    echo "⚠️ 세션 pid를 찾지 못해 워킹트리 점유 등록을 건너뛴다 — 이 세션은 다른 세션에게 보이지 않는다(session-guard 한계 ㉡)."
    exit 0
  fi
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

# ★2026-09-10(2차) — «파일 되돌리기» 판정을 «점유»보다 «앞»으로 옮긴다.
#   왜: 저장 안 한 변경은 **혼자 쓰는 클론에서도** revert 로 못 되돌린다 — 이 킷이 겪은 실사고 2건
#   (2026-08-25 #120 J절 · 2026-08-26 #149)이 정확히 그 경우다. 옛 판은 «점유가 없으면 여기서 나가서»
#   그 둘을 못 막았고, 그래서 배포처가 `settings.local.json` **안에 인라인 훅**으로 따로 막고 있었다.
#   그 자리는 `_reference/asks.md` 도 `check-asks.sh` 도 못 보는 곳이라 아무도 못 찾았다 — 여기로 합친다.
# ★2026-09-10(3차) — «앞으로 감기»는 면제한다. 오너 결정(2026-09-09): 추적 변경 0 · 미푸시 0 이면
#   **사람을 시키지 말고 AI 가 스스로 당긴다.** 그 결정을 규칙에 적어 놓고 장치가 매번 물으면
#   규칙과 장치가 싸운다(워크트리 면제와 같은 뿌리 — 오너가 그 창을 세 번째로 찍어 보냈다).
#   잃을 것이 있나? **없다**: ①추적 변경 0 이라 버려질 편집이 없고 ②미푸시 0 이라 얹힐 커밋이 없다.
#   `--ff-only` 는 조건이 안 맞으면 **아무 일도 안 하고 멈춘다**(되감기·덮어쓰기를 못 한다).
#   ⚠️조건을 하나라도 못 재면 면제하지 않는다(모르는 상태를 통과시키지 않는다).
if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(merge|pull)[[:space:]]+([^;&|]*[[:space:]])?--ff-only([[:space:]]|$)' \
   && command -v git >/dev/null 2>&1; then
  FFCLEAN=1
  git -C "$ROOT" diff --quiet 2>/dev/null || FFCLEAN=""
  git -C "$ROOT" diff --cached --quiet 2>/dev/null || FFCLEAN=""
  # 어느 ref 로 감는가 — 명령에 적힌 `<remote>/<branch>` 를 쓰고, 없으면 설정된 upstream 을 쓴다.
  FFREF=$(printf '%s' "$CMD" | tr ' ' '\n' | grep -E '^[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+$' | head -1)
  [ -z "$FFREF" ] && FFREF=$(git -C "$ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  FFAHEAD=""
  [ -n "$FFREF" ] && FFAHEAD=$(git -C "$ROOT" rev-list --count "$FFREF..HEAD" 2>/dev/null)
  [ -n "$FFCLEAN" ] && [ "$FFAHEAD" = "0" ] && exit 0
fi

RESTORE=""
# ★`--` 가 checkout 뒤 «어디에» 있든 파일 되돌리기다 — `git checkout <브랜치> -- <경로>` 도 HEAD 를 안 옮긴다
#   (2026-09-10 실측: 실제 명령 뭉치 재생에서 이 형태가 「HEAD 이동」으로 잘못 세어졌다).
printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(checkout[[:space:]]([^;&|]*[[:space:]])?--[[:space:]]|restore[[:space:]])' && RESTORE=1
# `--` 없이 경로만 준 형태(`git checkout scripts/foo.cjs`)도 파일 되돌리기다 — 슬래시나 확장자로 가른다.
printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?checkout[[:space:]]+[^-][^[:space:]]*(/|\.[A-Za-z0-9]+)([[:space:]]|$)' && RESTORE=1

if [ -n "$RESTORE" ] && command -v git >/dev/null 2>&1; then
  # ★워크트리·스크래치패드에서는 묻지 않는다 — 거기가 «일부러 고쳤다 되돌리는» 작업의 정해진 자리다
  #   (rules/verify.md 3절이 그렇게 하라고 시킨다. 시킨 자리에서 매번 묻는 것은 규칙과 장치가 싸우는 것이다).
  #   2026-09-10 실측: 돌연변이 시험이 반복마다 창을 띄워 오너가 「모든 케이스 다 뜨는거같은데」라고 했다.
  #   가려내는 법 = 연결된 워크트리는 `--git-dir` 과 `--git-common-dir` 이 «다르다».
  GD=$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)
  GC=$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)
  [ -n "$GD" ] && [ "$GD" != "$GC" ] && exit 0

  # ★버릴 것이 없으면 묻지 마라 — 그 파일이 안 바뀌었으면 이 명령은 아무 일도 안 한다.
  #   「되돌릴 수 있나」의 답이 «버릴 게 없다 = 잃을 것도 없다»이므로 창을 세울 이유가 없다.
  RPATHS=$(printf '%s' "$CMD" | sed -nE 's/.*git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(checkout[[:space:]]+(--[[:space:]]+)?|restore[[:space:]]+)([^;&|]*)/\4/p' \
           | tr ' ' '\n' | grep -E '/|\.[A-Za-z0-9]+$' | grep -v '^-' | head -5)
  DIRTY=""
  if [ -n "$RPATHS" ]; then
    for f in $RPATHS; do
      git -C "$ROOT" diff --quiet -- "$f" 2>/dev/null || DIRTY=1
      git -C "$ROOT" diff --cached --quiet -- "$f" 2>/dev/null || DIRTY=1
    done
  else
    # 경로를 못 집었다(`git restore .` 등) → 트리 전체로 본다. ★추적 안 하는 파일은 세지 않는다 —
    #   `git status --porcelain` 은 그것까지 세어 «건드리지도 않는 파일»로 거짓 창을 만든다(2026-09-10 실측).
    git -C "$ROOT" diff --quiet 2>/dev/null || DIRTY=1
    git -C "$ROOT" diff --cached --quiet 2>/dev/null || DIRTY=1
  fi
  [ -z "$DIRTY" ] && exit 0
fi

OTHERS=$(live_others "$ROOT/$LOCKREL" "$MYPID")
# pid 를 못 찾았을 때(MYPID 빈 문자열) 는 pid 비교가 아무것도 못 거른다 — 내 project dir 로 등록된 항목을 빼서
# 자기 점유를 '남의 세션'으로 오경고하지 않게 한다(2026-08-27 리뷰 지적 ㉢. 게이트의 1순위는 정상 작업에 침묵).
if [ -z "$MYPID" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  OTHERS=$(printf '%s' "$OTHERS" | awk -F'\t' -v me="$CLAUDE_PROJECT_DIR" '$4 != me')
fi
# ★HEAD 이동은 «점유»가 있을 때만 묻는다. 파일 되돌리기는 위에서 이미 판정이 끝났으므로 여기서 안 나간다.
[ -z "$OTHERS" ] && [ -z "$RESTORE" ] && exit 0

WHO=$(printf '%s' "$OTHERS" | head -1 | awk -F'\t' '{printf "pid %s 브랜치 %s 시작 %s", $1, $2, $3}')
# ★보간되는 값도 JSON 을 깨뜨린다 — 고정 문구만 조심해선 부족하다(2026-08-27 리뷰).
#   경로·브랜치명에 " 나 \ 가 있으면 JSON 이 깨지고 훅 판정이 **통째로 버려진다**(= 이 파일이 막으려던 그 무음).
#   경고문에 정확한 글자가 필요한 게 아니므로 **위험 글자는 '로 바꿔** 흘린다(escape 보다 단순·확실).
sanitize() { printf '%s' "$1" | tr '"\\' "''" | tr -d '\000-\037'; }

if [ -n "$RESTORE" ]; then
  # ★문구는 «사실»이어야 한다 — 점유가 없으면 점유 이야기를 하지 마라(틀린 문구는 옆의 진짜 창까지 무력화한다).
  EXTRA=""
  [ -n "$OTHERS" ] && EXTRA=" 게다가 이 클론을 다른 세션이 쓰는 중이다($(sanitize "$WHO")) — 버리는 것이 그 세션의 편집일 수 있다."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 이 파일의 «저장 안 된 변경»을 버린다(HEAD 는 안 옮긴다): %s — **revert 커밋으로 못 되돌린다**(실사고 2건: 2026-08-25 #120 J절 · 2026-08-26 #149).%s 돌연변이 시험처럼 «일부러 고쳤다 되돌리는» 작업은 워크트리·스크래치패드에서 해라 — 거기서는 이 창이 안 뜬다(rules/verify.md 3절). 👤 사람이 볼 것: 이 창은 «아니오»가 기본입니다. AI 에게 「워크트리에서 하라」고 한마디만 하시면 됩니다."}}\n' "$(sanitize "$ROOT")" "$EXTRA"
elif [ "$ROOT" = "$MYROOT" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 이 클론을 다른 세션이 쓰는 중인데 HEAD를 옮기려 한다: %s — 점유 중(%s). 한쪽의 checkout이 다른 쪽 커밋을 남의 브랜치에 얹는다(2026-08-13 실사고). 별도 워크트리·클론을 쓰거나, 그 세션이 끝났는지 확인하라. 👤 사람이 볼 것: 이 창은 «아니오»가 기본입니다. AI 에게 「워크트리에서 하라」고 하시면 됩니다. (단순히 최신으로 따라잡으려던 것이고 저장 안 된 변경·미푸시 커밋이 둘 다 없으면 「--ff-only 로 하라」로도 됩니다 — 셋이 다 맞아야 이 창이 안 뜹니다.)"}}\n' "$(sanitize "$ROOT")" "$(sanitize "$WHO")"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ 남의 작업 폴더의 HEAD를 옮기려 한다: %s — 다른 세션이 점유 중(%s). 그 세션의 체크아웃이 발밑에서 바뀐다. 별도 워크트리나 GitLab 웹에서 하거나, 상대 세션에 먼저 확인하라. 👤 사람이 볼 것: 이 창은 «아니오»가 기본입니다. AI 에게 「그 폴더 말고 워크트리에서 하라」고 하시면 됩니다."}}\n' "$(sanitize "$ROOT")" "$(sanitize "$WHO")"
fi
