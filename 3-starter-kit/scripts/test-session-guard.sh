#!/usr/bin/env bash
# session-guard 훅 회귀 테스트 — `bash scripts/test-session-guard.sh`
# 왜 있나: 이 훅은 **경고 전용**이라 조용히 죽어도 아무도 모른다(무음 = 통과처럼 보인다).
#   check-push.sh 와 같은 규약을 지키는지(ask 아니면 무음·비정상 종료 금지)와,
#   ①SessionStart 점유 감지 ②남의 폴더 HEAD 이동 감지가 실제로 켜지는지를 케이스로 고정한다.
# ★격리 저장소에서 돌린다 — 현재 체크아웃 상태에 좌우되면 브랜치마다 결과가 달라진다
#   (test-check-push.sh 가 그걸로 브랜치 42/47 vs main 47/47 을 낸 실측이 있다).
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/session-guard.sh"
# ★훅 파일 자체가 없으면 전 케이스가 exit 127 로 무더기 FAIL 이 된다 — "검사가 깨졌다"로 오독된다.
#   미배포는 테스트 실패가 아니라 배포 문제다. 그렇게 말하고 끝낸다.
[ -f "$HOOK" ] || { echo "⛔ 훅이 없다: $HOOK"; echo "   이 저장소엔 session-guard 훅이 아직 배포되지 않았다 — 테스트 실패가 아니라 미배포다."; echo "   킷의 .claude/hooks/session-guard.sh 를 이 저장소에 복사한 뒤 다시 돌려라."; exit 1; }
pass=0; fail=0
command -v git >/dev/null 2>&1 || { echo "⛔ git 이 없다 — 이 회귀 테스트는 git 이 있어야 성립한다"; exit 1; }
TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT
[ -d "$TMPROOT" ] && touch "$TMPROOT/.w" 2>/dev/null || { echo "⛔ 임시 폴더를 못 만들거나 못 쓴다: $TMPROOT"; echo "   울타리(샌드박스) 안에서는 TMPDIR 이 막힐 수 있다 — 이 시험은 여기서 돌리지 마라."; exit 1; }
TAB=$(printf '\t')

mkrepo() { # $1=이름 → repo 경로
  R="$TMPROOT/$1"; mkdir -p "$R/.claude"; ( cd "$R" || exit 1
    git init -q -b main . && git config user.email t@example.com && git config user.name t
    echo x > README.md && git add -A && git commit -qm base ) >/dev/null 2>&1
  printf '%s' "$R"
}
MINE=$(mkrepo mine); OTHER=$(mkrepo other)

# 살아있는 '남의 세션'을 흉내낸다 — 오래 자는 프로세스의 pid 를 남의 클론 lock 에 심는다.
sleep 300 & GHOST=$!
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$OTHER" > "$OTHER/.claude/.session-lock"
# 죽은 세션 항목도 하나 — 청소돼야 한다
printf '%s\t%s\t%s\t%s\n' "999999" "dead/x" "2020-01-01 00:00" "$OTHER" >> "$OTHER/.claude/.session-lock"

tn() { # $1=없어야 할 조각  $2=명령 — 창은 뜨되 «거짓 약속»은 없어야 한다
  OUT=$(CLAUDE_PROJECT_DIR="$MINE" printf '{"tool_input":{"command":"%s"}}' "$2" \
        | CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" 2>/dev/null)
  if [ -z "$OUT" ]; then echo "FAIL(창이 안 뜸): $2"; fail=$((fail+1)); return; fi
  if printf '%s' "$OUT" | grep -q "$1"; then echo "FAIL(거짓 약속 문구 '$1'): $2"; fail=$((fail+1)); else pass=$((pass+1)); fi
}
t() { # $1=ASK|SILENT  $2=기대 조각(-면 무시)  $3=명령
  OUT=$(CLAUDE_PROJECT_DIR="$MINE" printf '{"tool_input":{"command":"%s"}}' "$3" \
        | CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" 2>/dev/null); RC=$?
  if [ "$RC" -ne 0 ]; then echo "FAIL(exit $RC): $3"; fail=$((fail+1)); return; fi
  case "$OUT" in *'"permissionDecision":"allow"'*|*'"permissionDecision":"deny"'*)
    echo "FAIL(철칙 위반 — ask 아님): $3"; fail=$((fail+1)); return;; esac
  if [ "$1" = SILENT ]; then
    [ -z "$OUT" ] && { pass=$((pass+1)); return; }
    echo "FAIL(뜨면 안 되는데 뜸): $3 → $OUT"; fail=$((fail+1)); return
  fi
  if printf '%s' "$OUT" | grep -q "$2"; then pass=$((pass+1)); else
    echo "FAIL(안 뜸/딴 판정 — 기대 '$2'): $3 → ${OUT:-무음}"; fail=$((fail+1)); fi
}

echo "── A. 남의 폴더 HEAD 이동 — 알려야 한다"
t ASK '남의 작업 폴더' "cd $OTHER \&\& git checkout main"
t ASK '남의 작업 폴더' "cd $OTHER \&\& git switch -c feature/y"
t ASK '남의 작업 폴더' "cd $OTHER \&\& git pull origin main"
t ASK '남의 작업 폴더' "git -C $OTHER reset --hard origin/main"
t ASK '남의 작업 폴더' "cd $OTHER \&\& git rebase origin/main"
# ★`cd A && git -C B` — HEAD 는 B 에서 움직인다. 대상 판정이 cd 를 먼저 보던 시절엔 이걸 놓쳤다(2026-08-27 리뷰).
t ASK '남의 작업 폴더' "cd $MINE \&\& git -C $OTHER checkout main"
# ★뒤에 붙은 cd 가 판정을 뒤집으면 안 된다 — 실제 대상은 checkout 앞의 cd 다(2026-08-27 리뷰).
t ASK '남의 작업 폴더' "cd $OTHER \&\& git checkout main \&\& cd $MINE"

echo "── B. 조용해야 하는 것"
t SILENT - "cd $MINE \&\& git checkout main"                 # 내 클론 + 점유 없음 = 무음 (점유가 있으면 G절)
t SILENT - "cd $OTHER \&\& git log --oneline -5"             # HEAD 안 옮김
t SILENT - "cd $OTHER \&\& git status"                       # 〃
t SILENT - "cd $OTHER \&\& npm test"                         # git 아님
t SILENT - "echo git checkout main"                          # 명령 경계 밖(인자)
t SILENT - "cd $OTHER \&\& git -C $MINE checkout main"      # 뒤집힌 짝 — 실제 대상은 내 repo

echo "── C. 점유가 없으면 조용 (죽은 항목만 남은 경우)"
printf '%s\t%s\t%s\t%s\n' "999998" "dead/y" "2020-01-01 00:00" "$OTHER" > "$OTHER/.claude/.session-lock"
t SILENT - "cd $OTHER \&\& git checkout main"
[ -s "$OTHER/.claude/.session-lock" ] && { echo "FAIL(죽은 항목이 안 치워짐)"; fail=$((fail+1)); } || pass=$((pass+1))
# 되돌려 놓는다
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$OTHER" > "$OTHER/.claude/.session-lock"

echo "── D. SessionStart 등록·점유 경고"
# ★세션 pid 를 **환경에 기대지 않는다** — CI 컨테이너엔 claude 프로세스도 CLAUDE_PID 도 없어서
#   등록이 «한계 ㉡»(조용히 건너뜀)으로 떨어지고, D절 전체가 환경 탓으로 빨개진다(alpine 실측 4 FAIL).
#   살아 있는 pid 를 직접 심어 «등록이 되는 경로»를 어디서나 같게 만든다.
sleep 300 & SESS=$!
export CLAUDE_PID="$SESS"
OUT=$(CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" register 2>/dev/null); RC=$?
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && pass=$((pass+1)) || { echo "FAIL(빈 클론 첫 세션은 조용해야: rc=$RC out=$OUT)"; fail=$((fail+1)); }
[ -s "$MINE/.claude/.session-lock" ] && pass=$((pass+1)) || { echo "FAIL(등록이 안 됨)"; fail=$((fail+1)); }
# 남의 세션이 이미 있는 클론에서 시작하면 경고
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$MINE" >> "$MINE/.claude/.session-lock"
OUT=$(CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" register 2>/dev/null); RC=$?
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '다른 세션'; } && pass=$((pass+1)) || { echo "FAIL(점유 경고 안 뜸): ${OUT:-무음}"; fail=$((fail+1)); }
# 재진입(같은 세션이 SessionStart 를 또 겪음 — compact 등)에 중복 등록되지 않는다
N1=$(grep -c . "$MINE/.claude/.session-lock"); CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" register >/dev/null 2>&1
N2=$(grep -c . "$MINE/.claude/.session-lock")
[ "$N1" = "$N2" ] && pass=$((pass+1)) || { echo "FAIL(재진입에 중복 등록: $N1 → $N2)"; fail=$((fail+1)); }

# claude 조상이 있는 환경인가 — 없으면 조상 폴백은 성립할 수 없다(CI 컨테이너가 그렇다).
has_claude_ancestor() {
  local p i; p=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' '); i=0
  while [ -n "$p" ] && [ "$p" != "1" ] && [ "$i" -lt 6 ]; do
    case "$(ps -o comm= -p "$p" 2>/dev/null)" in *claude*) return 0;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); i=$((i+1))
  done; return 1
}
rm -f "$MINE/.claude/.session-lock"
OUT=$(env -u CLAUDE_PID CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" register 2>/dev/null); RC=$?
if has_claude_ancestor; then
  echo "── D2. CLAUDE_PID 없어도 조상 폴백으로 등록된다"
  { [ "$RC" -eq 0 ] && [ -s "$MINE/.claude/.session-lock" ]; } && pass=$((pass+1)) || { echo "FAIL(조상 폴백 등록 실패: rc=$RC)"; fail=$((fail+1)); }
  # 등록된 pid 가 살아있어야 한다(죽은 $$ 로 등록하면 다음 읽기에 사라진다 — 한계 ㉡의 옛 결함)
  RP=$(awk -F'\t' 'NR==1{print $1}' "$MINE/.claude/.session-lock")
  kill -0 "$RP" 2>/dev/null && pass=$((pass+1)) || { echo "FAIL(등록 pid $RP 가 이미 죽음 — 조용히 미등록이 된다)"; fail=$((fail+1)); }
else
  # ★여기서 «건너뜀»이 아니라 **다른 것을 검사한다** — pid 를 못 찾으면 훅은 «건너뛴다고 말해야» 한다(한계 ㉡).
  #   조용한 미등록이 옛 결함이었으므로, 이 환경에서는 그 말이 나오는지가 정확히 볼 것이다.
  echo "── D2. (claude 조상 없는 환경) pid 미확인이면 '건너뛴다'고 말해야 한다"
  { [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '건너뛴다'; } && pass=$((pass+1)) || { echo "FAIL(조용한 미등록 — 말해야 한다): rc=$RC out=${OUT:-무음}"; fail=$((fail+1)); }
  [ ! -s "$MINE/.claude/.session-lock" ] && pass=$((pass+1)) || { echo "FAIL(못 찾은 pid로 등록해 버렸다)"; fail=$((fail+1)); }
fi

echo "── C2. 잠금 폴더가 쓰기 불가여도 점유는 보고한다(청소만 못 할 뿐)"
chmod a-w "$OTHER/.claude" 2>/dev/null
t ASK '남의 작업 폴더' "cd $OTHER \&\& git checkout main"
chmod u+w "$OTHER/.claude" 2>/dev/null

echo "── F. 경고문에 들어가는 값이 JSON 을 깨뜨리지 않는다"
# ★git 은 브랜치명에 따옴표를 허용한다(실측: `feat"quote` 생성됨). 옛 판은 그 값을 그대로 보간해
#   **깨진 JSON** 을 내보냈고, 그러면 훅 판정이 통째로 버려진다 — 이 파일이 막으려던 바로 그 무음이다.
#   파서 없이 확인한다: 위험 글자가 '로 바뀌어 나오고, 원래 따옴표는 출력에 없어야 한다.
printf '%s\t%s\t%s\t%s\n' "$GHOST" 'feat"quote' "2026-01-01 00:00" "$OTHER" > "$OTHER/.claude/.session-lock"
OUT=$(printf '{"tool_input":{"command":"%s"}}' "cd $OTHER \&\& git checkout main" \
      | CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" 2>/dev/null)
case "$OUT" in
  *"feat'quote"*) pass=$((pass+1));;
  *) echo "FAIL(위험 글자가 안 걸러짐/무음): ${OUT:-무음}"; fail=$((fail+1));;
esac
case "$OUT" in
  *'feat"quote'*) echo "FAIL(원래 따옴표가 그대로 나가 JSON 이 깨진다)"; fail=$((fail+1));;
  *) pass=$((pass+1));;
esac
# 잠금을 원래대로
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$OTHER" > "$OTHER/.claude/.session-lock"

echo "── E. 이상 입력 (fail-silent)"
OUT=$(printf '' | bash "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(빈 입력)"; fail=$((fail+1)); }
OUT=$(printf 'not json' | bash "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(비 JSON)"; fail=$((fail+1)); }
OUT=$(printf '{"tool_input":{"command":"cd /nope/nope && git checkout main"}}' | CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(없는 경로)"; fail=$((fail+1)); }

echo "── G. 내 클론을 다른 세션이 쓰는 중이면 HEAD 이동에 확인을 받는다 (2026-08-31 신설)"
# ★왜 생겼나: ①SessionStart 경고를 «정보 한 줄»로 낮췄다(세션 시작의 정지가 정보량 0 — 오너 지적).
#   그러면 «같은 클론 두 세션»(2026-08-13 실사고)의 확인 지점이 여기밖에 없다.
#   옛 판은 대상이 내 repo 면 «①이 담당한다»며 무조건 나갔으므로 **이 절은 옛 훅에서 전부 FAIL 한다**
#   (= 회귀 케이스가 유효하다는 증거. 초록만 보고 넘어가면 안 된다 — 2026-08-28 함정).
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$OTHER" > "$MINE/.claude/.session-lock"
t ASK '이 클론을 다른 세션이' "cd $MINE \&\& git checkout main"
t ASK '이 클론을 다른 세션이' "git checkout -b feature/z"      # cd 도 -C 도 없다 = 내 클론
t ASK '이 클론을 다른 세션이' "git -C $MINE pull origin main"
t ASK '이 클론을 다른 세션이' "git reset --hard origin/main"
# ★«👤 사람이 볼 것» 문구는 사실이어야 한다(2026-09-10 !470 리뷰: 「--ff-only 로 하라고 하면 이 창이 안 뜬다」가
#   checkout·reset 에도 떴고, 더러운 트리·미푸시에선 --ff-only 로 쳐도 다시 떴다 — 면제 조건은 셋이다).
t ASK '셋이 다 맞아야' "cd $MINE \&\& git checkout main"
tn '하시면 이 창이 안 뜹니다' "cd $MINE \&\& git checkout main"
t SILENT - "git log --oneline -5"                              # HEAD 를 안 옮긴다
t SILENT - "git status"                                        # 〃
echo "── H. «HEAD 이동»과 «파일 되돌리기»를 가른다 (2026-09-10 — 오너가 찍어 보낸 창의 문구가 틀렸다)"
# `git checkout -- <경로>` 는 HEAD 를 **안 옮긴다**. 그런데도 「HEAD를 옮기려 한다」로 물었다.
# 틀린 문구는 창을 도장찍기로 만든다 — 그래서 «묻느냐»만이 아니라 «무엇이라 묻느냐»를 검사한다.
printf 'x\n' > "$MINE/mutant.cjs"; git -C "$MINE" add mutant.cjs >/dev/null 2>&1
git -C "$MINE" -c user.email=t@t -c user.name=t commit -qm "fixture" >/dev/null 2>&1
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$OTHER" > "$MINE/.claude/.session-lock"
printf 'MUTANT\n' > "$MINE/mutant.cjs"                          # 버릴 것이 «있는» 상태
t ASK '저장 안 된 변경' "cd $MINE \&\& git checkout -- mutant.cjs"
t ASK '저장 안 된 변경' "git -C $MINE restore mutant.cjs"
t ASK '저장 안 된 변경' "cd $MINE \&\& git checkout mutant.cjs"  # `--` 없이 경로만
git -C "$MINE" checkout -- mutant.cjs 2>/dev/null                # 되돌려 «버릴 것이 없는» 상태로
t SILENT - "cd $MINE \&\& git checkout -- mutant.cjs"            # 무해 = 아예 안 묻는다
printf 'MUTANT\n' > "$MINE/mutant.cjs"
t ASK '저장 안 된 변경' "cd $MINE \&\& git checkout main -- mutant.cjs"  # 브랜치에서 «파일만» 꺼내오는 형태도 HEAD 를 안 옮긴다
git -C "$MINE" checkout -- mutant.cjs 2>/dev/null
t ASK 'HEAD를 옮기려' "cd $MINE \&\& git checkout main"          # 브랜치 이동은 여전히 옛 문구
# 점유가 사라지면(죽은 항목만) 다시 조용해진다 — 정상 작업에 침묵이 게이트의 1순위다
printf '%s\t%s\t%s\t%s\n' "999997" "dead/z" "2020-01-01 00:00" "$OTHER" > "$MINE/.claude/.session-lock"
t SILENT - "cd $MINE \&\& git checkout main"
rm -f "$MINE/.claude/.session-lock"
t SILENT - "git checkout main"                                 # 잠금 파일 자체가 없어도 조용

echo "── I. «파일 되돌리기»는 점유와 상관없이 판정한다 (2026-09-10 2차 — 배포처가 설정 파일 안에 숨겨 두고 있던 몫)"
# 왜: 저장 안 한 변경은 «혼자 쓰는 클론»에서도 revert 로 못 되돌린다(실사고 2건). 옛 판은 점유가 없으면
#     그냥 나가서 그 둘을 못 막았고, 그래서 배포처가 settings.local.json 안에 인라인 훅을 따로 두고 있었다.
rm -f "$MINE/.claude/.session-lock"                              # 점유 없음 = 혼자 쓰는 클론
printf 'MUTANT\n' > "$MINE/mutant.cjs"                           # 버릴 것이 있는 상태
t ASK '저장 안 된 변경' "cd $MINE && git checkout -- mutant.cjs"
t ASK '저장 안 된 변경' "cd $MINE && git restore mutant.cjs"
# ★문구가 «사실»이어야 한다 — 점유가 없는데 점유 이야기를 하면 그 창은 거짓말이다
OUT=$(CLAUDE_PROJECT_DIR="$MINE" printf '{"tool_input":{"command":"cd %s && git checkout -- mutant.cjs"}}' "$MINE" \
      | CLAUDE_PROJECT_DIR="$MINE" bash "$HOOK" 2>/dev/null)
if printf '%s' "$OUT" | grep -q '다른 세션이 쓰는 중'; then
  echo "FAIL(점유가 없는데 점유를 말한다)"; fail=$((fail+1)); else pass=$((pass+1)); fi
git -C "$MINE" checkout -- mutant.cjs 2>/dev/null
t SILENT - "cd $MINE && git checkout -- mutant.cjs"              # 버릴 게 없으면 여전히 무음
t SILENT - "cd $MINE && git checkout main"                       # 점유가 없으면 가지 이동은 무음(그대로)

echo "── J. ★워크트리에서는 안 묻는다 — 규칙이 «거기서 하라»고 시킨 자리다"
# 2026-09-10 실측: 돌연변이 시험이 반복마다 창을 띄워 오너가 「모든 케이스 다 뜨는거같은데」라고 했다.
WT="$TMPROOT/wt"
git -C "$MINE" worktree add -q -b wtbranch "$WT" >/dev/null 2>&1
if [ -d "$WT" ]; then
  printf 'MUTANT\n' > "$WT/mutant.cjs"
  t SILENT - "cd $WT && git checkout -- mutant.cjs"
  t SILENT - "cd $WT && git restore mutant.cjs"
  # 같은 조건인데 본 폴더면 여전히 묻는다 — 면제가 «워크트리라서»인지 «그냥 안 물어서»인지 가른다
  printf 'MUTANT\n' > "$MINE/mutant.cjs"
  t ASK '저장 안 된 변경' "cd $MINE && git checkout -- mutant.cjs"
  git -C "$MINE" checkout -- mutant.cjs 2>/dev/null
else
  echo "  ⚠️ 워크트리를 못 만들었다 — J절을 못 돌렸다(건너뜀이 아니라 실패로 센다)"; fail=$((fail+1))
fi

echo "── K. «앞으로 감기»는 면제한다 (2026-09-10 3차 — 오너가 이 창을 세 번째로 찍어 보냈다)"
# 오너 결정(2026-09-09): 추적 변경 0 · 미푸시 0 이면 사람을 시키지 말고 AI 가 당긴다.
# 그 결정을 규칙에 적어 놓고 장치가 매번 물으면 규칙과 장치가 싸운다.
UP=$(mkrepo up)                                                  # «원격» 역할
( cd "$UP" && echo more >> README.md && git add -A && git commit -qm ahead ) >/dev/null 2>&1
FFR="$TMPROOT/ff"; git clone -q "$UP" "$FFR" >/dev/null 2>&1; mkdir -p "$FFR/.claude"
printf '%s\t%s\t%s\t%s\n' "$GHOST" "feature/x" "2026-01-01 00:00" "$OTHER" > "$FFR/.claude/.session-lock"
( cd "$UP" && echo yet >> README.md && git add -A && git commit -qm ahead2 ) >/dev/null 2>&1
git -C "$FFR" fetch -q origin >/dev/null 2>&1
if [ -d "$FFR" ]; then
  t SILENT - "cd $FFR && git merge --ff-only origin/main"        # 깨끗하고 안 앞서 있다 → 무음
  t SILENT - "cd $FFR && git pull --ff-only origin main"         # pull 형태도 같다
  echo dirty >> "$FFR/README.md"                                 # ★추적 변경이 생기면 다시 묻는다
  t ASK 'HEAD를 옮기려' "cd $FFR && git merge --ff-only origin/main"
  git -C "$FFR" checkout -- README.md 2>/dev/null
  ( cd "$FFR" && echo mine >> README.md && git add -A && git commit -qm local ) >/dev/null 2>&1
  t ASK 'HEAD를 옮기려' "cd $FFR && git merge --ff-only origin/main"   # ★미푸시가 있으면 다시 묻는다
  t ASK 'HEAD를 옮기려' "cd $FFR && git merge origin/main"             # ★--ff-only 가 아니면 면제 아님
else
  echo "  ⚠️ 앞으로 감기 픽스처를 못 만들었다 — K절을 못 돌렸다(실패로 센다)"; fail=$((fail+1))
fi

echo "── L. 세션 시작에 본 클론을 main 최신으로 따라잡는다 (2026-09-10 — 본 클론 50커밋 뒤처짐)"
# 왜: 세션은 켠 폴더의 규칙을 읽는다. 본 클론이 뒤처지면 main 에 들어간 수리가 새 세션에 안 닿는다.
# ★옛 훅(따라잡기 없음)에서는 L1·L2·L3 이 FAIL 한다 — 초록만 보고 넘어가지 마라.
reg() { CLAUDE_PROJECT_DIR="$1" bash "$HOOK" register 2>/dev/null; }
up_ahead() { ( cd "$UP" || exit 1; echo "$1" >> README.md && git add -A && git commit -qm "$1" ) >/dev/null 2>&1; }
CU="$TMPROOT/cu"; git clone -q "$UP" "$CU" >/dev/null 2>&1
if [ -d "$CU" ]; then
  mkdir -p "$CU/.claude"
  up_ahead l1; OUT=$(reg "$CU")
  { [ "$(git -C "$CU" rev-parse HEAD)" = "$(git -C "$UP" rev-parse HEAD)" ] && printf '%s' "$OUT" | grep -q '따라잡았다'; } \
    && pass=$((pass+1)) || { echo "FAIL(L1 깨끗한 main 인데 안 따라잡음): ${OUT:-무음}"; fail=$((fail+1)); }
  up_ahead l2; echo dirty >> "$CU/README.md"                      # 추적 변경 → 건드리지 않고 이유를 말한다
  H0=$(git -C "$CU" rev-parse HEAD); OUT=$(reg "$CU")
  { [ "$(git -C "$CU" rev-parse HEAD)" = "$H0" ] && printf '%s' "$OUT" | grep -q '저장 안 된 변경'; } \
    && pass=$((pass+1)) || { echo "FAIL(L2 더러운 트리를 감았거나 이유가 없다): ${OUT:-무음}"; fail=$((fail+1)); }
  git -C "$CU" checkout -q -- README.md
  ( cd "$CU" || exit 1; echo mine > mine.txt && git add mine.txt && git commit -qm mine ) >/dev/null 2>&1   # 미푸시 커밋
  H0=$(git -C "$CU" rev-parse HEAD); OUT=$(reg "$CU")
  { [ "$(git -C "$CU" rev-parse HEAD)" = "$H0" ] && printf '%s' "$OUT" | grep -q '미푸시'; } \
    && pass=$((pass+1)) || { echo "FAIL(L3 미푸시 커밋 위로 감았거나 이유가 없다): ${OUT:-무음}"; fail=$((fail+1)); }
  git -C "$CU" checkout -q -b feat/l                               # 작업 브랜치 → 아무것도 안 하고 말도 안 한다
  up_ahead l3; H0=$(git -C "$CU" rev-parse HEAD); OUT=$(reg "$CU")
  { [ "$(git -C "$CU" rev-parse HEAD)" = "$H0" ] && [ -z "$OUT" ]; } \
    && pass=$((pass+1)) || { echo "FAIL(L4 작업 브랜치를 건드렸거나 떠든다): ${OUT:-무음}"; fail=$((fail+1)); }
else
  echo "  ⚠️ 따라잡기 픽스처를 못 만들었다 — L절을 못 돌렸다(실패로 센다)"; fail=$((fail+1))
fi

kill "$GHOST" 2>/dev/null; kill "${SESS:-}" 2>/dev/null
echo "──────── $pass OK / $fail FAIL"
[ "$fail" -eq 0 ] || exit 1
