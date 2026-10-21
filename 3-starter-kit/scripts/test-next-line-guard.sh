#!/usr/bin/env bash
# next-line-guard 훅 회귀 테스트 — `bash scripts/test-next-line-guard.sh`
# 왜 있나: 이 훅은 «스스로 죽으면 무음(통과)»이라 죽어도 아무도 모른다. 그래서 «되돌린다»와 «통과시킨다» 양쪽을 건수로 센다.
# 시험할 훅을 바꾸려면(유효성 증명용): NEXT_LINE_GUARD_HOOK=/경로/가짜.cjs bash scripts/test-next-line-guard.sh
set -u
HOOK="${NEXT_LINE_GUARD_HOOK:-$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/next-line-guard.cjs}"
[ -f "$HOOK" ] || { echo "⛔ 훅이 없다: $HOOK — 테스트 실패가 아니라 미배포다."; exit 1; }
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 검증 불능(합격 아님)."; exit 1; }
pass=0; fail=0

check() { # $1=block|pass $2=설명 $3=JSON 입력
  OUT=$(printf '%s' "$3" | node "$HOOK" 2>/dev/null); RC=$?
  if [ "$RC" -ne 0 ]; then echo "FAIL(exit $RC): $2"; fail=$((fail+1)); return; fi
  if [ "$1" = block ]; then
    case "$OUT" in *'"decision":"block"'*) pass=$((pass+1));; *) echo "FAIL(되돌려야 하는데 통과): $2 → ${OUT:-빈 출력}"; fail=$((fail+1));; esac
  else
    [ -z "$OUT" ] && { pass=$((pass+1)); return; }
    echo "FAIL(통과해야 하는데 되돌림): $2 → $OUT"; fail=$((fail+1))
  fi
}
msg() { # $1=응답 본문 → last_assistant_message 입력 JSON
  node -e 'process.stdout.on("error",()=>{});process.stdout.write(JSON.stringify({hook_event_name:"Stop",stop_hook_active:false,last_assistant_message:process.argv[1]}))' "$1"
}

# 되돌린다 — 실제 재발 문장(dev 673)과 변형
check block '재발 원문'        "$(msg $'배포 대기 중입니다.\n\n▶ 다음: 배포를 기다리는 중입니다 — 끝나면 /inspect 673 화면 검사를 이어서 합니다')"
check block '백틱 명령'        "$(msg $'끝.\n▶ 다음: `/inspect 673`')"
check block '선택지 안'        "$(msg $'▶ 다음: 1. /inspect 673 2. /done 673')"
check block 'security-review' "$(msg $'▶ 다음: /security-review 후 /done 673')"
check block '굵은 글씨 머리'   "$(msg $'**▶ 다음:** /inspect')"
check block '끝 공백 줄'       "$(msg $'▶ 다음: /inspect 12\n\n  ')"
# 통과시킨다 — 사람 몫 명령·행동 문장·마지막 줄이 아닌 곳
check pass  '사람 몫 명령'     "$(msg $'▶ 다음: /done 673')"
check pass  '행동 문장'        "$(msg $'▶ 다음: 배포가 끝나면 제가 화면 검사를 이어서 합니다 — 기다리시면 됩니다')"
check pass  '본문 중간 언급'   "$(msg $'/inspect 673 결과: 이상 없음\n▶ 다음: /todo')"
check pass  '▶ 줄 아님'        "$(msg $'다음엔 /inspect 를 돌립니다')"
check pass  '비슷한 이름'      "$(msg $'▶ 다음: /inspector 설정 확인')"
check pass  '빈 응답'          "$(msg '')"
# 한 번만 되돌린다 — 두 번째(stop_hook_active)는 같은 문장이어도 통과
check pass  '재진입'           '{"hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"▶ 다음: /inspect 673"}'
check pass  '깨진 입력'        'not json'

# transcript_path 로 읽기(last_assistant_message 가 없는 판) — 마지막 assistant 글을 본다
T=$(mktemp -d) || { echo "⛔ 임시 폴더 실패 — 검증 불능"; exit 1; }
trap 'rm -rf "$T"' EXIT
# Windows Git Bash 의 /tmp 경로는 node 가 못 읽는다 — 훅에 넘길 경로만 Windows 형식으로(실제 훅 입력은 원래 그 형식)
TN="$T"; command -v cygpath >/dev/null 2>&1 && TN=$(cygpath -m "$T")
cat > "$T/a.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"배포 기다려"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"대기 중입니다.\n▶ 다음: 끝나면 /inspect 673 을 합니다"}]}}
EOF
check block '기록 파일: 되돌림' "{\"stop_hook_active\":false,\"transcript_path\":\"$TN/a.jsonl\"}"
cat > "$T/b.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"▶ 다음: /inspect 673"}]}}
{"type":"user","message":{"role":"user","content":"응"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"검사 결과 이상 없습니다.\n▶ 다음: /done 673"}]}}
EOF
check pass  '기록 파일: 최신 글만' "{\"stop_hook_active\":false,\"transcript_path\":\"$TN/b.jsonl\"}"
check pass  '기록 파일 없음'    "{\"stop_hook_active\":false,\"transcript_path\":\"$TN/none.jsonl\"}"

echo "next-line-guard: 통과 $pass / 실패 $fail"
[ "$fail" -eq 0 ] && [ "$pass" -eq 17 ] || exit 1
