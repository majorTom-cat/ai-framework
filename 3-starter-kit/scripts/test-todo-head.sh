#!/usr/bin/env bash
# todo-head.sh 회귀 테스트 — `bash scripts/test-todo-head.sh`
# 왜 있나: 맥은 «조회 건너뜀», 그 밖은 «glab 호출»이 갈려야 한다. 건수로 양쪽을 센다(둘 다 같은 출력이면 분기가 죽은 것).
# 시험할 스크립트를 바꾸려면(유효성 증명용): TODO_HEAD=/경로/가짜.sh bash scripts/test-todo-head.sh
set -u
HEAD_SH="${TODO_HEAD:-$(cd "$(dirname "$0")" && pwd)/todo-head.sh}"
[ -f "$HEAD_SH" ] || { echo "⛔ 스크립트가 없다: $HEAD_SH — 테스트 실패가 아니라 미배포다."; exit 1; }
D=$(mktemp -d) || { echo "⛔ 임시폴더를 못 만들었다 — 검증 불능."; exit 1; }
cd "$D" || { echo "⛔ 임시폴더로 못 들어갔다 — 검증 불능."; exit 1; }
mkdir bin
# 가짜 glab: 부르면 표식 파일을 남기고 120줄을 낸다(자르는 한계 확인용)
cat > bin/glab <<'EOF'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
i=0; while [ $i -lt 120 ]; do echo "줄$i"; i=$((i+1)); done
EOF
chmod +x bin/glab
export PATH="$D/bin:$PATH" FAKE_LOG="$D/glab.log"
pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }

: > "$FAKE_LOG"
OUT=$(HEAD_OS=Darwin bash "$HEAD_SH" issues);
case "$OUT" in *"맥: 자동 조회 건너뜀"*) ok;; *) no "맥 issues 에 건너뜀 안내가 없다: $OUT";; esac
[ ! -s "$FAKE_LOG" ] && ok || no "맥인데 glab 을 불렀다"
OUT=$(HEAD_OS=Darwin bash "$HEAD_SH" todos)
case "$OUT" in *"맥: 자동 조회 건너뜀"*) ok;; *) no "맥 todos 에 건너뜀 안내가 없다";; esac
[ ! -s "$FAKE_LOG" ] && ok || no "맥 todos 인데 glab 을 불렀다"

: > "$FAKE_LOG"
OUT=$(HEAD_OS=Linux bash "$HEAD_SH" issues)
grep -q 'issue list --assignee=@me' "$FAKE_LOG" && ok || no "리눅스 issues 가 glab issue list 를 안 불렀다: $(cat "$FAKE_LOG")"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 30 ] && ok || no "issues 가 30줄로 안 잘렸다"
: > "$FAKE_LOG"
OUT=$(HEAD_OS=MINGW64_NT bash "$HEAD_SH" todos)
grep -q 'todo list -P 100' "$FAKE_LOG" && ok || no "윈도우 todos 가 glab todo list -P 100 을 안 불렀다: $(cat "$FAKE_LOG")"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 60 ] && ok || no "todos 가 60줄로 안 잘렸다"

: > "$FAKE_LOG"
OUT=$(HEAD_OS=Linux bash "$HEAD_SH" 엉뚱)
case "$OUT" in *사용법*) ok;; *) no "모르는 인자에 사용법이 없다";; esac
[ ! -s "$FAKE_LOG" ] && ok || no "모르는 인자인데 glab 을 불렀다"

cd / && rm -r "$D"
echo "통과 $pass / 실패 $fail"
[ "$fail" -eq 0 ] && [ "$pass" -ge 9 ]
