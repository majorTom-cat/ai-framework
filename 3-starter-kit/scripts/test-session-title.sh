#!/usr/bin/env bash
# session-title 훅 회귀 테스트 — `bash scripts/test-session-title.sh`
# 왜 있나: 이 훅은 «스스로 죽으면 무음(통과)»이라 죽어도 아무도 모른다. 그래서 «제목이 붙는다»와 «안 붙어야 할 때 안 붙는다» 양쪽을 건수로 센다.
# 시험할 훅을 바꾸려면(유효성 증명용): SESSION_TITLE_HOOK=/경로/가짜.cjs bash scripts/test-session-title.sh
set -u
HOOK="${SESSION_TITLE_HOOK:-$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/session-title.cjs}"
[ -f "$HOOK" ] || { echo "⛔ 훅이 없다: $HOOK — 테스트 실패가 아니라 미배포다."; exit 1; }
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 검증 불능(합격 아님)."; exit 1; }
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

echo "session-title: ${pass} 통과 / ${fail} 실패"
[ "$fail" -eq 0 ] && [ "$pass" -ge 17 ] || exit 1
