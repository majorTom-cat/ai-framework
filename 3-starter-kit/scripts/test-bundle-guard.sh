#!/usr/bin/env bash
# bundle-guard 훅 회귀 테스트 — `bash scripts/test-bundle-guard.sh`
# 왜 있나: 이 훅은 «스스로 죽으면 무음(통과)»이라, 죽어도 아무도 모른다. 그리고 판정 «종류»가 핵심이다 —
#   deny(AI 에게 되돌림)가 ask(사람에게 창)로 바뀌면 장치가 목적과 정반대가 된다. 그래서 종류를 검사한다(rules/verify.md §5).
# 시험할 훅을 바꾸려면(유효성 증명용): BUNDLE_GUARD_HOOK=/경로/가짜.cjs bash scripts/test-bundle-guard.sh
set -u
HOOK="${BUNDLE_GUARD_HOOK:-$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/bundle-guard.cjs}"
[ -f "$HOOK" ] || { echo "⛔ 훅이 없다: $HOOK — 테스트 실패가 아니라 미배포다."; exit 1; }
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 이 훅은 node 로 돈다. 검증 불능(합격 아님)."; exit 1; }
T=$(mktemp -d) || { echo "⛔ 임시 폴더를 못 만든다 — 검증 불능"; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude" "$T/proj/.claude"
# 허용 목록을 격리한다 — 실제 사용자 설정에 좌우되면 기계마다 결과가 달라진다.
printf '%s\n' '{"permissions":{"allow":["Bash(git *)","Bash(grep *)","Bash(head *)","Bash(jq *)","Bash(wc *)","Bash(bash scripts/*)","Bash(glab *)","Bash(docker compose *)"]}}' > "$T/proj/.claude/settings.json"
pass=0; fail=0

# ★보내는 쪽은 EPIPE 를 삼킨다 — 입력을 안 읽고 끝나는 훅(유효성 증명용 가짜)에서 오류 더미가 결과를 가린다.
run() { node -e 'process.stdout.on("error",()=>{});process.stdout.write(JSON.stringify({tool_input:{command:process.argv[1]}}))' "$1" \
        | HOME="$T/home" CLAUDE_PROJECT_DIR="$T/proj" node "$HOOK" 2>/dev/null; }
t() { # $1=DENY|PASS  $2=기대 조각(-면 무시)  $3=명령
  OUT=$(run "$3"); RC=$?
  if [ "$RC" -ne 0 ]; then echo "FAIL(exit $RC): $3"; fail=$((fail+1)); return; fi
  case "$OUT" in *'"permissionDecision":"ask"'*|*'"permissionDecision":"allow"'*)
    echo "FAIL(deny 가 아닌 판정 — 사람에게 창을 띄우거나 허가를 넓힌다): $3"; fail=$((fail+1)); return;; esac
  if [ "$1" = PASS ]; then
    [ -z "$OUT" ] && { pass=$((pass+1)); return; }
    echo "FAIL(통과해야 하는데 되돌림): $3 → $OUT"; fail=$((fail+1)); return
  fi
  case "$OUT" in *'"permissionDecision":"deny"'*) ;; *) echo "FAIL(안 되돌림): $3"; fail=$((fail+1)); return;; esac
  if [ "$2" = - ] || printf '%s' "$OUT" | grep -q "$2"; then pass=$((pass+1)); else
    echo "FAIL(사유가 다름 — 기대 '$2'): $3 → $OUT"; fail=$((fail+1)); fi
}

echo "── A. 명령을 이으면 되돌린다"
t DENY '명령 2개' 'git status && git log -1'
t DENY '명령 2개' 'ls; pwd'
t DENY '명령 2개' 'false || echo x'
t DENY '명령 2개' 'sleep 1 & echo x'
t DENY '명령 2개' "$(printf 'echo a\necho b')"
t DENY - 'for n in 1 2; do echo $n; done'
# ★2026-09-10 오너 화면에 창을 띄운 바로 그 모양
t DENY - 'S=/tmp/x; rm -rf "$S"; mkdir -p "$S/scripts"; cd "$S" && bash "$S/scripts/t.sh"; echo "EXIT=$?"'

echo "── B. «cd 뒤 git» 은 git -C 로 돌려보낸다"
t DENY 'git -C' 'cd /tmp/x && git status'
t DENY 'git -C' 'cd /tmp/x && FOO=1 git log'

echo "── C. 파이프 — 뒤 단계가 허용 목록 밖이면 되돌린다"
t DENY 'cut' 'grep -n x f | cut -c1-140'
t DENY 'tr' 'git log | head -3 | tr a b'
t PASS - 'grep -n x f | head -3'
t PASS - 'glab api "projects/1/issues" | jq ".[].iid"'
t PASS - 'git log --oneline | wc -l'

echo "── D. 규칙이 시키는 형태는 통과한다"
t PASS - 'git status'
t PASS - 'FOO=1 git status'
t PASS - 'bash scripts/check-asks.sh; echo "EXIT=$?"'
t PASS - 'cd /tmp/scratch && bash /abs/scripts/test-x.sh'
t PASS - 'cd /tmp/scratch && bash /abs/scripts/test-x.sh; echo "EXIT=$?"'
t PASS - 'glab issue note 1 -m "$(cat /tmp/body.md)"'
t PASS - 'npm test 2>&1'
t PASS - 'npm test &>/dev/null'
t PASS - 'npm test > /tmp/out.txt 2>&1'

echo "── E. 따옴표·치환·heredoc «안»의 연산자는 세지 않는다"
t PASS - "echo 'a && b; c | d'"
t PASS - 'git log --format="%h | %s; x && y"'
t PASS - 'echo $(ls | wc -l)'
t PASS - "$(printf "cat <<'EOF' > /tmp/f\nline && x; y | z\nEOF")"
t PASS - "$(printf "python3 - <<'PY'\nimport os; print(1)\nPY")"
t DENY '명령 2개' "$(printf "cat <<'EOF' > /tmp/f\nbody\nEOF\ngit status")"   # heredoc «뒤»에 이은 명령은 센다

echo "── F. 이상 입력은 무음(장치 결함으로 일을 막지 않는다)"
OUT=$(printf '' | node "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(빈 입력)"; fail=$((fail+1)); }
OUT=$(printf 'not json' | node "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(비 JSON)"; fail=$((fail+1)); }

echo "── H. 2026-09-10 리뷰 수리 — 허용은 «줄» 단위 · 큰따옴표 안 \$( ) · 줄 끝 주석 · EXIT 꼬리 변형"
# ★옛 판에서는 이 절이 전부 FAIL 한다(첫 낱말 판정·따옴표 짝 깨짐·주석 속 ; ·EXIT 모양 한 가지).
t DENY 'bash' 'git log | bash'                                     # bash 는 `bash scripts/*` 만 허용이다
t DENY 'docker' 'git log | docker ps'                              # docker 는 `docker compose *` 만
t PASS - "$(printf "git commit -m \"\$(cat <<'EOF'\nit\"s odd\nEOF\n)\"")"   # heredoc 본문의 따옴표 홀수
t PASS - 'git status # a; b'                                       # 줄 끝 주석 속 ;
t PASS - "bash scripts/x.sh; echo 'EXIT='\$?"
t PASS - 'bash scripts/x.sh; echo "exit: $?"'

echo "── G. 스킬이 열릴 때 도는 명령(!\`…\`)은 되돌리면 안 된다 — 되돌리면 스킬 자체가 안 열린다"
# ★실물 스킬 파일에서 줄을 뽑아 이 저장소의 실제 허용 목록으로 돌린다 — 새 스킬 줄이 생겨도 자동으로 검사된다.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N=0
while IFS= read -r line; do
  c=${line#\!\`}; c=${c%\`}
  OUT=$(node -e 'process.stdout.on("error",()=>{});process.stdout.write(JSON.stringify({tool_input:{command:process.argv[1]}}))' "$c" \
        | HOME="$T/home" CLAUDE_PROJECT_DIR="$ROOT" node "$HOOK" 2>/dev/null)
  if [ -z "$OUT" ]; then pass=$((pass+1)); else echo "FAIL(스킬 자동 명령을 되돌림): $c"; fail=$((fail+1)); fi
  N=$((N+1))
done < <(grep -rh '^!`' "$ROOT/.claude/skills" 2>/dev/null)
# ★0줄이면 «통과»가 아니라 잣대가 틀린 것이다(세는 모양이 실물과 다르면 0이 나온다 — rules/verify.md §5).
[ "$N" -gt 0 ] || { echo "FAIL(스킬 자동 명령을 한 줄도 못 찾았다 — 잣대가 틀렸다)"; fail=$((fail+1)); }
echo "   (스킬 자동 명령 ${N}줄 검사)"

echo "──────── $pass OK / $fail FAIL"
[ "$fail" -eq 0 ] || exit 1
