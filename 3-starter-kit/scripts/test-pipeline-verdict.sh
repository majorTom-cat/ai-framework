#!/usr/bin/env bash
# pipeline-verdict.cjs 회귀 테스트 — `bash scripts/test-pipeline-verdict.sh`
# 왜 있나: 이 판정기의 1행(실패|진행중|게이트대기|종결초록)을 스킬이 그대로 믿고 머지한다. 행동 시험이 없어
#   «게이트대기»를 «종결초록»으로 내는 회귀가 나도 아무도 모른다(2026-09-29 배포처 friction).
# 방법: 가짜 `glab` 을 PATH 앞에 두고 고정 JSON 을 내게 한다 — 네트워크·인증 없이 판정 논리만 잰다.
# ★«판정 불능»(exit 2)과 «판정했다»(exit 0)를 가른다 — 조회 실패를 어느 토큰으로도 위장하지 않는지 본다(rules/verify.md §1).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/pipeline-verdict.cjs"
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 이 판정기는 node 로 돈다. 검증 불능(합격 아님)."; exit 1; }
[ -f "$TOOL" ] || { echo "⛔ 판정기가 없다: $TOOL"; exit 1; }
TMP="$(mktemp -d)" || { echo "⛔ 임시 폴더를 못 만들었다(울타리?) — 저장소에 픽스처를 떨어뜨리지 않으려고 멈춘다"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" || exit 1
# 가짜 glab: FAKE_JOBS 파일을 그대로 내고, FAKE_FAIL 이면 조회 실패를 흉내 낸다
cat > "$TMP/bin/glab" <<'EOF'
#!/bin/sh
[ -n "${FAKE_FAIL:-}" ] && { echo "x509: certificate signed by unknown authority" >&2; exit 1; }
cat "$FAKE_JOBS"
EOF
chmod +x "$TMP/bin/glab" || exit 1
OK=0; FAIL=0

# $1=설명 $2=기대 종료코드 $3=기대 1행(- 면 안 봄) $4=잡 JSON(- 면 조회 실패) [$5=추가로 있어야 할 줄 조각]
v() {
  printf '%s' "$4" > "$TMP/jobs.json"
  if [ "$4" = - ]; then OUT=$(FAKE_FAIL=1 FAKE_JOBS="$TMP/jobs.json" PATH="$TMP/bin:$PATH" node "$TOOL" 42 2>&1); RC=$?
  else OUT=$(FAKE_JOBS="$TMP/jobs.json" PATH="$TMP/bin:$PATH" node "$TOOL" 42 2>&1); RC=$?; fi
  L1=$(printf '%s\n' "$OUT" | head -1)
  if [ "$RC" != "$2" ]; then echo "  ⛔ $1 — 종료코드 기대 $2 실제 $RC → $OUT"; FAIL=$((FAIL+1)); return; fi
  if [ "$3" != - ] && [ "$L1" != "$3" ]; then echo "  ⛔ $1 — 1행 기대 '$3' 실제 '$L1'"; FAIL=$((FAIL+1)); return; fi
  if [ -n "${5:-}" ] && ! printf '%s' "$OUT" | grep -qF "$5"; then echo "  ⛔ $1 — '$5' 줄이 없다 → $OUT"; FAIL=$((FAIL+1)); return; fi
  OK=$((OK+1)); echo "  OK  $1"
}
J() { printf '{"id":%s,"name":"%s","status":"%s","allow_failure":%s}' "$1" "$2" "$3" "$4"; }

echo "── A. 토큰 4종"
v '차단형 잡 실패 → 실패' 0 실패 "[$(J 1 test failed false),$(J 2 lint success false)]" '실패 잡: 1 test'
v '차단형 잡 취소 → 실패' 0 실패 "[$(J 1 test canceled false)]"
v '돌고 있는 잡 → 진행중' 0 진행중 "[$(J 1 test running false),$(J 2 lint success false)]"
v '대기(pending) → 진행중' 0 진행중 "[$(J 1 test pending false)]"
v '게이트 아닌 created → 진행중' 0 진행중 "[$(J 1 deploy created true)]"
v '이름 있는 게이트 manual → 게이트대기' 0 게이트대기 "[$(J 1 test success false),$(J 9 high-risk-gate manual false)]" '남은 게이트 잡: 9 high-risk-gate (manual)'
v '라벨 게이트 created → 게이트대기' 0 게이트대기 "[$(J 9 high-risk-label-gate created false)]"
v '이름 모를 차단형 manual → 게이트대기' 0 게이트대기 "[$(J 9 deploy-prod manual false)]"
v '성공만 → 종결초록' 0 종결초록 "[$(J 1 test success false),$(J 2 lint skipped false)]"
v '무시 가능 manual 만 잔존 → 종결초록' 0 종결초록 "[$(J 1 test success false),$(J 2 pages manual true)]"

echo "── B. 우선순위 (실패 > 진행중 > 게이트대기)"
v '실패 + 진행중 → 실패' 0 실패 "[$(J 1 test failed false),$(J 2 lint running false)]"
v '진행중 + 게이트 → 진행중' 0 진행중 "[$(J 1 test running false),$(J 9 high-risk-gate manual false)]"
v '게이트 이름은 allow_failure 여도 게이트' 0 게이트대기 "[$(J 9 high-risk-gate manual true)]"

echo "── C. 경고 가시화 — allow_failure 실패는 status 에 가려진다"
v 'allow_failure 실패 → 종결초록 + 경고 줄' 0 종결초록 "[$(J 1 test success false),$(J 3 density-check failed true)]" '경고(allow_failure 실패): density-check'

echo "── D. 판정 불능은 exit 2 — 어느 토큰으로도 위장하지 않는다"
v '조회 실패 → exit 2' 2 - -
v '잡 0개 → exit 2' 2 - '[]'
v '깨진 JSON → exit 2' 2 - 'not json'
OUT=$(PATH="$TMP/bin:$PATH" node "$TOOL" abc 2>&1); RC=$?
[ "$RC" = 2 ] && { OK=$((OK+1)); echo "  OK  숫자 아닌 ID → exit 2"; } || { echo "  ⛔ 숫자 아닌 ID — exit $RC → $OUT"; FAIL=$((FAIL+1)); }
for tok in 실패 진행중 게이트대기 종결초록; do  # 판정 불능 출력에 토큰이 새면 1행만 읽는 스킬이 오독한다
  FAKE_FAIL=1 FAKE_JOBS="$TMP/jobs.json" PATH="$TMP/bin:$PATH" node "$TOOL" 42 2>/dev/null | grep -qx "$tok" \
    && { echo "  ⛔ 조회 실패인데 stdout 에 '$tok'"; FAIL=$((FAIL+1)); }
done

echo "──────── $OK OK / $FAIL FAIL"
[ "$FAIL" -eq 0 ] || exit 1
