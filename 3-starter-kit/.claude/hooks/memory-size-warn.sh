#!/usr/bin/env bash
# 세션을 열 때 메모리 목차(MEMORY.md)가 커졌으면 한 줄로 알린다. 읽기만 하고 아무것도 바꾸지 않는다.
# 한도: 목차는 200줄을 넘으면 뒤가 잘려 읽힌다. 170줄 또는 36KB(대략 1만 6천 토큰)에서 먼저 알린다.
# 경로: 현재 프로젝트 폴더의 «/» 를 «-» 로 바꾼 이름이 메모리 폴더 이름이다(예: /Users/ysk/orca/projects/x → -Users-ysk-orca-projects-x).
#   다른 위치를 보려면 CLAUDE_MEMORY_INDEX 로 MEMORY.md 경로를 직접 준다(시험용). 문턱: MEMORY_WARN_LINES·MEMORY_WARN_BYTES.
# 출처: 배포처 bnsone-90 제안(2026-10-21). 실패해도 세션을 막지 않는다(항상 종료 0).
P="${CLAUDE_PROJECT_DIR:-$PWD}"
ENC="$(printf '%s' "$P" | sed 's#/#-#g')"
M="${CLAUDE_MEMORY_INDEX:-$HOME/.claude/projects/$ENC/memory/MEMORY.md}"
[ -f "$M" ] || exit 0
lines="$(wc -l < "$M" | tr -d ' ')"
bytes="$(wc -c < "$M" | tr -d ' ')"
if [ "$lines" -ge "${MEMORY_WARN_LINES:-170}" ] || [ "$bytes" -ge "${MEMORY_WARN_BYTES:-36000}" ]; then
  echo "⚠️ 메모리 목차가 ${lines}줄·${bytes}바이트로 커졌다(200줄이 넘으면 뒤가 잘려 읽힌다). 사용자에게 한 줄로 알리고, 좋다고 하면 _reference/memory-tidy.md 의 읽기 단계(백업·조회·후보 표)를 네가 하라. 삭제는 사용자가 항목을 고른 뒤에만."
fi
exit 0
