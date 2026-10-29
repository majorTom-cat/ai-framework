#!/usr/bin/env bash
# docker-leak-guard 훅 회귀 테스트 — `bash scripts/test-docker-leak-guard.sh`
# 왜 있나: 이 훅은 «스스로 죽으면 무음(통과)»이라 죽어도 아무도 모른다. 판정 «종류»도 핵심이다 —
#   deny(AI 에게 되돌림)가 ask(사람에게 창)로 바뀌면 장치가 목적과 정반대가 된다(rules/verify.md §5).
# 시험할 훅을 바꾸려면(유효성 증명용): DOCKER_LEAK_GUARD_HOOK=/경로/가짜.cjs bash scripts/test-docker-leak-guard.sh
#   (훅은 같은 폴더의 bundle-guard.cjs 를 불러 쓴다 — 가짜 훅이 그걸 쓰려면 같은 폴더에 두어라.)
set -u
HOOK="${DOCKER_LEAK_GUARD_HOOK:-$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/docker-leak-guard.cjs}"
[ -f "$HOOK" ] || { echo "⛔ 훅이 없다: $HOOK — 테스트 실패가 아니라 미배포다."; exit 1; }
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 이 훅은 node 로 돈다. 검증 불능(합격 아님)."; exit 1; }
pass=0; fail=0

# ★보내는 쪽은 EPIPE 를 삼킨다 — 입력을 안 읽고 끝나는 가짜 훅에서 오류 더미가 결과를 가린다.
run() { node -e 'process.stdout.on("error",()=>{});process.stdout.write(JSON.stringify({tool_input:{command:process.argv[1]}}))' "$1" \
        | node "$HOOK" 2>/dev/null; }
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

echo "── A. docker run — --rm 도 볼륨 지정도 없으면 되돌린다"
t DENY '`docker run` 에' 'docker run -d postgres:16'
t DENY '`docker run` 에' 'docker run postgres:16'
t DENY '`docker run` 에' 'docker container run -d postgres:16'
t DENY '`docker run` 에' 'docker  run   -d   postgres:16'
t DENY '`docker run` 에' 'sudo docker run -d postgres:16'
t DENY '`docker run` 에' 'FOO=1 docker run -d postgres:16'
t DENY '`docker run` 에' '/usr/local/bin/docker run -d postgres:16'
t DENY '`docker run` 에' 'docker -H tcp://h:2375 run -d postgres:16'
t DENY '`docker run` 에' 'docker run -d -e POSTGRES_PASSWORD=x -p 5433:5432 postgres:16'
t DENY '`docker run` 에' 'docker run --rm=false -d postgres:16'
# ★세부: 대입의 $( ) 안쪽과 파이프 뒤 단계
t DENY '`docker run` 에' 'LIVE=$(docker run -d postgres:16)'
t DENY '`docker run` 에' 'echo "$(docker run -d postgres:16)"'
t DENY '`docker run` 에' 'docker run -d postgres:16 | cat'
# ★제어문 키워드 뒤 · --volume-driver(볼륨 지정 아님) · 줄바꿈 잇기 (bnsone !1618 리뷰)
t DENY '`docker run` 에' 'if true; then docker run -d img; fi'
t DENY '`docker run` 에' 'for i in 1 2; do docker run -d img; done'
t DENY '`docker rm -f`' 'while true; do docker rm -f a; done'
t DENY '`docker run` 에' 'docker run -d --volume-driver local postgres:16'
t DENY '`docker run` 에' 'if ! docker run x; then :; fi'
t PASS - 'if ! docker run --rm x; then :; fi'
t PASS - 'if true; then docker run --rm img; fi'
t PASS - 'docker run --rm\
 img'

echo "── B. docker rm -f — -v 가 없으면 되돌린다"
t DENY '`docker rm -f`' 'docker rm -f c1'
t DENY '`docker rm -f`' 'docker rm --force c1'
t DENY '`docker rm -f`' 'docker container rm -f c1'
t DENY '`docker rm -f`' 'docker rm -f c1 c2'
t DENY '`docker rm -f`' 'docker ps -aq | xargs docker rm -f'
t DENY '`docker rm -f`' 'docker rm -f $(docker ps -aq)'
t DENY '`docker rm -f`' 'sudo docker rm -f c1'

echo "── C. 지키는 모양은 통과한다 (run)"
t PASS - 'docker run --rm postgres:16'
t PASS - 'docker run -d --rm postgres:16'
t PASS - 'docker run -dit --rm postgres:16'
t PASS - 'docker run --rm=true postgres:16'
t PASS - 'docker run -d -v pgdata:/var/lib/postgresql/data postgres:16'
t PASS - 'docker run -d --volume pgdata:/var/lib/postgresql/data postgres:16'
t PASS - 'docker run -d --volume=pgdata:/x postgres:16'
t PASS - 'docker run -dv pgdata:/x postgres:16'
t PASS - 'docker run -d --mount type=volume,src=a,dst=/b postgres:16'
t PASS - 'docker run -d --volumes-from other postgres:16'
t PASS - 'LIVE=$(docker run -d --rm postgres:16)'

echo "── D. 지키는 모양은 통과한다 (rm)"
t PASS - 'docker rm -fv c1'
t PASS - 'docker rm -vf c1'
t PASS - 'docker rm -f -v c1'
t PASS - 'docker rm --force --volumes c1'
t PASS - 'docker ps -aq | xargs docker rm -fv'
t PASS - 'docker container rm -fv c1'

echo "── E. 대상이 아닌 것은 건드리지 않는다"
t PASS - 'docker ps -a'
t PASS - 'docker images'
t PASS - 'docker volume ls'
t PASS - 'docker system df'
t PASS - 'docker compose up -d'
t PASS - 'docker compose down --rmi local'
t PASS - 'docker rm c1'
t PASS - 'docker stop c1'
t PASS - 'docker exec -it c1 psql -U postgres'
t PASS - 'git status'
t PASS - 'echo hello'

echo "── F. 글자만 닮은 것은 통과한다 (따옴표·heredoc 본문 안)"
t PASS - 'git commit -m "docker run -d postgres 를 --rm 없이 띄우지 마라"'
t PASS - "echo 'docker rm -f c1'"
t PASS - "$(printf "cat <<'EOF'\ndocker run -d postgres:16\nEOF")"
t PASS - 'grep -rn "docker run" scripts/'

echo "── G. 훅이 스스로 죽는 경우는 무음(통과)이다"
OUT=$(printf 'not json' | node "$HOOK" 2>/dev/null); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then pass=$((pass+1)); else echo "FAIL(깨진 입력에서 무음 통과가 아님: exit $RC / $OUT)"; fail=$((fail+1)); fi
OUT=$(printf '{"tool_input":{}}' | node "$HOOK" 2>/dev/null); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then pass=$((pass+1)); else echo "FAIL(명령 없는 입력에서 무음 통과가 아님: exit $RC / $OUT)"; fail=$((fail+1)); fi

echo "── 결과: 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
