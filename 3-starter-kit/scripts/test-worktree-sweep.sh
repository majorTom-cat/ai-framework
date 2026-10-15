#!/usr/bin/env bash
# worktree-sweep.cjs 회귀 테스트 — `bash scripts/test-worktree-sweep.sh`
# 왜 있나: 이 점검기가 «지워도 된다»를 잘못 말하면 푸시 안 된 일이 사라진다. 그래서 «보류해야 할 것을 보류한다»를
#   «정리 가능을 낸다»만큼 건수로 센다. 시험은 임시 폴더 안에서만 돈다(모든 git 은 -C 로 그 안을 가리킨다).
# 시험할 점검기를 바꾸려면(유효성 증명용): WORKTREE_SWEEP=/경로/가짜.cjs bash scripts/test-worktree-sweep.sh
set -u
SWEEP="${WORKTREE_SWEEP:-$(cd "$(dirname "$0")" && pwd)/worktree-sweep.cjs}"
[ -f "$SWEEP" ] || { echo "⛔ 점검기가 없다: $SWEEP — 테스트 실패가 아니라 미배포다."; exit 1; }
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 검증 불능(합격 아님)."; exit 1; }
T=$(mktemp -d) || { echo "⛔ 임시 폴더를 못 만든다 — 검증 불능"; exit 1; }
[ -d "$T" ] || { echo "⛔ 임시 폴더가 없다"; exit 1; }
trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false "$@"; }

g init -q --bare "$T/origin.git" || { echo "⛔ bare 저장소 실패 — 검증 불능"; exit 1; }
g clone -q "$T/origin.git" "$T/main" 2>/dev/null
g -C "$T/main" checkout -q -b main
echo base > "$T/main/base.txt"
echo old > "$T/main/old.txt"
# ★잠금 파일·.env 를 무시시킨다 — 안 그러면 w5 가 «저장 안 된 변경»으로 보류돼 «다른 세션이 쓰는 중» 방어를 지워도 초록이다(verify.md §5)
printf '%s\n' '.claude/.session-lock' '.env' > "$T/main/.gitignore"
g -C "$T/main" add base.txt old.txt .gitignore
g -C "$T/main" commit -q -m base
g -C "$T/main" push -q origin main 2>/dev/null

# w1: 브랜치 끝이 main 에 들어 있다 (A)
g -C "$T/main" worktree add -q -b merged-br "$T/w1" main
# w2: 저장 안 된 변경
g -C "$T/main" worktree add -q -b dirty-br "$T/w2" main
echo wip > "$T/w2/wip.txt"
# w3: 같은 내용이 다른 경로로 main 에 들어갔다 (C) — 닫힌 MR 뒤 브랜치 끝만 남은 모양
g -C "$T/main" worktree add -q -b dup-br "$T/w3" main
echo same > "$T/w3/x.txt"
g -C "$T/w3" add x.txt
g -C "$T/w3" commit -q -m "x via branch"
# w4: main 에 없는 일이 있다
g -C "$T/main" worktree add -q -b uniq-br "$T/w4" main
echo uniq > "$T/w4/y.txt"
g -C "$T/w4" add y.txt
g -C "$T/w4" commit -q -m "y only here"
# w5: 다른 세션이 쓰는 중 (살아 있는 pid = 이 셸)
g -C "$T/main" worktree add -q -b busy-br "$T/w5" main
mkdir -p "$T/w5/.claude"
printf '%s\tbusy-br\t0\t%s\n' "$$" "$T/w5" > "$T/w5/.claude/.session-lock"
# w6: 분리된 HEAD
g -C "$T/main" worktree add -q --detach "$T/w6" main
# w8: 잠긴 워크트리 (끝은 main 의 조상)
g -C "$T/main" worktree add -q -b locked-br "$T/w8" main
g -C "$T/main" worktree lock "$T/w8"
# w9: 이름 바꾸기 — 새 경로는 main 에 같은 내용으로 있지만 옛 경로는 main 에 아직 있다(삭제가 main 에 없음)
g -C "$T/main" worktree add -q -b rename-br "$T/w9" main
g -C "$T/w9" mv old.txt new.txt
g -C "$T/w9" commit -q -m "rename old to new"
echo old > "$T/main/new.txt"
g -C "$T/main" add new.txt
g -C "$T/main" commit -q -m "new via main"
# w1: git 이 안 보는 파일(.env) — 정리 가능이지만 경고가 붙어야 한다
echo SECRET=1 > "$T/w1/.env"
# main 에 x.txt 를 다른 커밋으로 넣는다(w3 의 내용과 같다) — w1 도 이 뒤 main 의 조상이다
echo same > "$T/main/x.txt"
g -C "$T/main" add x.txt
g -C "$T/main" commit -q -m "x via main"
g -C "$T/main" push -q origin main 2>/dev/null
g -C "$T/main" fetch -q origin 2>/dev/null
# w7: 방금 만든 워크트리 — 끝이 지금 origin/main 과 같다(아직 시작 안 함과 FF 머지가 같은 모양)
g -C "$T/main" worktree add -q -b fresh-br "$T/w7" origin/main

OUT=$(WORKTREE_SWEEP_NO_GLAB=1 node "$SWEEP" --repo "$T/main" 2>&1); RC=$?
pass=0; fail=0
chk() { # $1=기대 줄 머리(정리 가능|보류) $2=폴더 이름
  if printf '%s\n' "$OUT" | grep -a -q "^$1.*$T/$2[[:space:]]"; then pass=$((pass+1)); else echo "FAIL($2 는 $1 이어야 한다)"; fail=$((fail+1)); fi
}
[ "$RC" -eq 0 ] && pass=$((pass+1)) || { echo "FAIL(종료 코드 $RC)"; fail=$((fail+1)); }
chk "정리 가능" w1
chk "보류" w2
chk "정리 가능" w3
chk "보류" w4
chk "보류" w5
chk "보류" w6
chk "보류" w7
chk "보류" w8
chk "보류" w9
case "$OUT" in *"9개 중 정리 가능 2개"*) pass=$((pass+1));; *) echo "FAIL(요약 줄: 9개 중 정리 가능 2개)"; fail=$((fail+1));; esac
# .env 경고
printf '%s\n' "$OUT" | grep -a "$T/w1[[:space:]]" | grep -q 'git 이 안 보는' && pass=$((pass+1)) || { echo "FAIL(w1 의 .env 경고가 없다)"; fail=$((fail+1)); }
# 신선도 창을 0 으로 하면 w7 은 정리 가능이 된다(= 신선도 방어가 w7 을 막고 있었다는 증명)
OUT3=$(WORKTREE_SWEEP_FRESH_SECS=0 WORKTREE_SWEEP_NO_GLAB=1 node "$SWEEP" --repo "$T/main" 2>&1)
printf '%s\n' "$OUT3" | grep -a -q "^정리 가능.*$T/w7[[:space:]]" && pass=$((pass+1)) || { echo "FAIL(신선도 0 이면 w7 은 정리 가능이어야 한다)"; fail=$((fail+1)); }
# 점검 불능: git 저장소가 아니면 종료 2 (거짓 «정리할 것 없음» 금지)
OUT2=$(node "$SWEEP" --repo "$T" 2>&1); RC2=$?
if [ "$RC2" -eq 2 ]; then pass=$((pass+1)); else echo "FAIL(저장소 아님 → 종료 2 기대, 실제 $RC2)"; fail=$((fail+1)); fi
# 점검기는 지우지 않는다
for d in w1 w2 w3 w4 w5 w6 w7 w8 w9; do [ -d "$T/$d" ] && pass=$((pass+1)) || { echo "FAIL($d 가 지워졌다 — 점검기는 보고만 한다)"; fail=$((fail+1)); }; done

echo "worktree-sweep: ${pass} 통과 / ${fail} 실패"
[ "$fail" -eq 0 ] && [ "$pass" -ge 21 ] || exit 1
