#!/usr/bin/env bash
# session-title 훅 회귀 테스트 — `bash scripts/test-session-title.sh`
# 왜 있나: 이 훅은 «스스로 죽으면 무음(통과)»이라 죽어도 아무도 모른다. 그래서 «제목이 붙는다»와 «안 붙어야 할 때 안 붙는다» 양쪽을 건수로 센다.
# 시험할 훅을 바꾸려면(유효성 증명용): SESSION_TITLE_HOOK=/경로/가짜.cjs bash scripts/test-session-title.sh
set -u
HOOK="${SESSION_TITLE_HOOK:-$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/session-title.cjs}"
[ -f "$HOOK" ] || { echo "⛔ 훅이 없다: $HOOK — 테스트 실패가 아니라 미배포다."; exit 1; }
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 검증 불능(합격 아님)."; exit 1; }
# Orca 터미널 안에서 돌려도 시험하는 사람의 실제 탭 이름을 건드리지 않게 — Orca 변수는 비우고 시작한다(아래 Orca 시험만 가짜 orca 로 따로 건다).
unset ORCA_TERMINAL_HANDLE ORCA_CLI_BIN_DIR
pass=0; fail=0

run() { # $1=prompt $2=session_title(없으면 빈 문자열이면 키 생략)
  node -e 'const i={prompt:process.argv[1]};if(process.argv[2])i.session_title=process.argv[2];process.stdout.on("error",()=>{});process.stdout.write(JSON.stringify(i))' "$1" "$2" \
    | node "$HOOK" 2>/dev/null
}
t() { # $1=기대 제목(-면 «붙이지 않음») $2=prompt $3=기존 제목
  local cur="${3:-}"
  OUT=$(run "$2" "$cur"); RC=$?
  if [ "$RC" -ne 0 ]; then echo "FAIL(exit $RC): [$2] [$cur]"; fail=$((fail+1)); return; fi
  if [ "$1" = - ]; then
    [ -z "$OUT" ] && { pass=$((pass+1)); return; }
    echo "FAIL(붙이면 안 되는데 붙임): [$2] [$cur] → $OUT"; fail=$((fail+1)); return
  fi
  case "$OUT" in *'"hookEventName":"UserPromptSubmit"'*'"sessionTitle":"'"$1"'"'*) pass=$((pass+1));;
    *) echo "FAIL(기대 제목 $1): [$2] [$cur] → ${OUT:-빈 출력}"; fail=$((fail+1));; esac
}

t "dev 660"  '/dev 660'
t "fix 661"  '/fix 661'
t "done 660" '/done 660'
t "dev 12"   '/dev #12'
t "dev 660"  '  /dev 660 추가 설명'
t "dev 660"  '<command-message>dev</command-message><command-name>/dev</command-name><command-args>660</command-args>'
t -          '/todo'
t -          '/dev'
t -          '/dev 이슈'
t -          '/devx 660'
t -          '그냥 말'
t -          '/inspect 660'
# 번호 있는 명령은 어떤 제목이든 덮어쓴다(직접 지은 제목·Orca 자동 제목 «1 3» 포함)
t "dev 660"  '/dev 660' '근태 연차 화면'
t "dev 680"  '/dev 680' '1 3'
# 번호 없는 명령은 사람이 지은 제목을 건드리지 않는다
t -          '/todo' '근태 연차 화면'
# 우리가 붙인 제목: 같은 카드면 처음 제목 유지, 카드가 다르면 갱신
t -          '/done 660' 'dev 660'
t "dev 700"  '/dev 700'  'done 660'
# 읽을 수 없는 입력은 조용히 통과(exit 0, 출력 없음)
OUT=$(printf 'not json' | node "$HOOK" 2>/dev/null); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then pass=$((pass+1)); else echo "FAIL(깨진 입력): exit $RC → $OUT"; fail=$((fail+1)); fi

# --- Orca 탭 이름(2026-10-16): 상단 탭 바는 Claude 세션 제목이 아니라 Orca 자동 이름(«Todo»·«Dev 600»)을 쓴다 → 훅이 `orca terminal rename` 으로 직접 지은 이름을 건다.
# 가짜 orca 가 받은 인자를 파일에 적는다. 떼어 낸 자식이라 기다리며 읽는다(건수가 아니라 «무엇을 물었나»를 단언).
FAKE=$(mktemp -d) || { echo "⛔ 임시 폴더 실패 — 검증 불능"; exit 1; }
trap 'rm -rf "$FAKE"' EXIT
LOG="$FAKE/calls.log"
printf '%s\n' '#!/bin/sh' "printf '%s|' \"\$@\" >> \"$LOG\"" > "$FAKE/orca"; chmod +x "$FAKE/orca"
waitlog() { local i=0; while [ ! -s "$LOG" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done; }
orca_t() { # $1=기대 호출 인자(-면 «호출 없음») $2=prompt $3=기존 제목 $4=핸들(비우면 변수 없음)
  rm -f "$LOG"
  if [ -n "${4:-}" ]; then
    node -e 'const i={prompt:process.argv[1]};if(process.argv[2])i.session_title=process.argv[2];process.stdout.write(JSON.stringify(i))' "$2" "${3:-}" \
      | ORCA_TERMINAL_HANDLE="$4" ORCA_CLI_BIN_DIR="$FAKE" node "$HOOK" >/dev/null 2>&1
  else
    node -e 'const i={prompt:process.argv[1]};if(process.argv[2])i.session_title=process.argv[2];process.stdout.write(JSON.stringify(i))' "$2" "${3:-}" \
      | ORCA_CLI_BIN_DIR="$FAKE" node "$HOOK" >/dev/null 2>&1
  fi
  if [ "$1" = - ]; then
    sleep 0.5
    [ ! -e "$LOG" ] && { pass=$((pass+1)); return; }
    echo "FAIL(Orca 호출하면 안 되는데 호출): [$2] handle=[${4:-}] → $(cat "$LOG")"; fail=$((fail+1)); return
  fi
  waitlog
  GOT=$(cat "$LOG" 2>/dev/null)
  [ "$GOT" = "$1" ] && { pass=$((pass+1)); return; }
  echo "FAIL(Orca 호출 인자): [$2] 기대 [$1] 실제 [${GOT:-호출 없음}]"; fail=$((fail+1))
}
orca_t 'terminal|rename|--terminal|term_x|--title|dev 660|'  '/dev 660'  ''          term_x
orca_t 'terminal|rename|--terminal|term_x|--title|dev 660|'  '/done 660' 'dev 660'   term_x   # 같은 카드의 뒤 명령 — 세션 제목은 안 건드려도 탭 이름은 다시 맞춘다(첫 시도가 실패했어도 복구)
orca_t 'terminal|rename|--terminal|term_x|--title|dev 700|'  '/dev 700'  'done 660'  term_x
orca_t -                                                      '/dev 660'  ''          ''        # Orca 밖(변수 없음) — 호출 안 함
orca_t -                                                      '/todo'     ''          term_x    # 번호 없는 명령 — 호출 안 함
# orca 실행 파일이 없어도 Claude 세션 제목은 그대로 붙고 exit 0
EMPTY=$(mktemp -d)
OUT=$(node -e 'process.stdout.write(JSON.stringify({prompt:"/dev 660"}))' | ORCA_TERMINAL_HANDLE=term_x ORCA_CLI_BIN_DIR="$EMPTY" node "$HOOK" 2>/dev/null); RC=$?
rm -rf "$EMPTY"
case "$OUT" in *'"sessionTitle":"dev 660"'*) [ "$RC" -eq 0 ] && pass=$((pass+1)) || { echo "FAIL(orca 없음 — exit $RC)"; fail=$((fail+1)); };;
  *) echo "FAIL(orca 없음 — 세션 제목이 사라짐): exit $RC → ${OUT:-빈 출력}"; fail=$((fail+1));; esac

# 훅은 느린 orca 를 기다리지 않고(spawnSync 로 바뀌면 2초 이상 — 경과는 정수 초라 1 이하면 통과), 훅이 끝난 뒤에도 자식은 일을 마친다
SLOW="$FAKE/slow"; mkdir -p "$SLOW"
printf '%s\n' '#!/bin/sh' 'sleep 2' "printf x > \"$FAKE/slow.done\"" > "$SLOW/orca"; chmod +x "$SLOW/orca"
START=$SECONDS
node -e 'process.stdout.write(JSON.stringify({prompt:"/dev 660"}))' | ORCA_TERMINAL_HANDLE=term_x ORCA_CLI_BIN_DIR="$SLOW" node "$HOOK" >/dev/null 2>&1
ELAPSED=$((SECONDS-START))
if [ "$ELAPSED" -le 1 ]; then pass=$((pass+1)); else echo "FAIL(훅이 느린 orca 를 기다림): ${ELAPSED}초"; fail=$((fail+1)); fi
i=0; while [ ! -e "$FAKE/slow.done" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i+1)); done
if [ -e "$FAKE/slow.done" ]; then pass=$((pass+1)); else echo "FAIL(훅이 끝나자 떼어 낸 orca 도 같이 죽음)"; fail=$((fail+1)); fi

echo "session-title: ${pass} 통과 / ${fail} 실패"
[ "$fail" -eq 0 ] && [ "$pass" -ge 26 ] || exit 1
