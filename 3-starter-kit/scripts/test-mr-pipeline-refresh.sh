#!/usr/bin/env bash
# `scripts/mr-pipeline-refresh.cjs` 동작 시험. CI `self-tests` 가 자동으로 줍는다.
#
# 지키는 성질:
#   ① 라벨이 파이프라인보다 «먼저» 붙었으면 **아무것도 만들지 않는다**(이게 깨지면 같은 커밋에 두 벌 — 이 스크립트의 존재 이유)
#   ② 라벨이 «나중에» 붙었으면 새로 만들고, 같은 커밋의 «돌고 있는» 앞 파이프라인만 취소한다
#   ③ 만들기가 실패하면 **취소하지 않는다**(MR 에 도는 파이프라인이 0개가 되면 안 된다)
#   ④ 모르면 «유지»가 아니라 판정 불능(2) — 조회 실패를 «할 일 없음»으로 위장하지 않는다
#   ⑤ 스크립트의 GATE_LABELS ↔ `.gitlab-ci.yml` 게이트 잡이 읽는 라벨이 같다(한쪽만 바꾸면 게이트가 못 읽은 파이프라인을 «유지»한다)
# 방법: PATH 맨 앞에 가짜 `glab` 을 세워 응답을 먹이고, **무엇을 불렀는지**(POST 유무·취소 대상)를 호출 기록으로 단언한다.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
SUT="$(pwd)/scripts/mr-pipeline-refresh.cjs"
CI_YML="$(pwd)/.gitlab-ci.yml"
[ -f "$SUT" ] || { echo "⛔ 대상이 없다: $SUT"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 검증 불능(합격 아님)"; exit 1; }

OK=0; FAIL=0
pass() { OK=$((OK+1)); }
fail() { FAIL=$((FAIL+1)); echo "  ⛔ FAIL: $1"; }

T=$(mktemp -d) || { echo "⛔ 임시 폴더를 못 만들었다"; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# 가짜 glab — 마지막 인자(경로)로 응답 파일을 고른다. 호출은 한 줄씩 기록한다.
cat > "$T/bin/glab" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_LOG"
for a in "$@"; do last="$a"; done
case "$*" in *"--method POST"*) post=1 ;; *) post=0 ;; esac
case "$last" in
  */cancel)
    [ -n "${FAKE_FAIL_CANCEL:-}" ] && { echo "403 Forbidden" >&2; exit 1; }
    echo '{}' ;;
  */resource_label_events*)
    [ -n "${FAKE_FAIL_EVENTS:-}" ] && { echo "500" >&2; exit 1; }
    # 쪽 구분 — 2쪽 파일이 있으면 2쪽에 그것을, 3쪽부터는 빈 배열. 없으면 1쪽 파일(100건 미만이라 1쪽에서 끝난다).
    case "$last" in
      *page=1) cat "$FAKE_DIR/events.json" ;;
      *page=2) if [ -f "$FAKE_DIR/events2.json" ]; then cat "$FAKE_DIR/events2.json"; else echo '[]'; fi ;;
      *) echo '[]' ;;
    esac ;;
  */merge_requests/*/pipelines*)
    if [ "$post" = 1 ]; then
      [ -n "${FAKE_FAIL_CREATE:-}" ] && { echo "400 Bad Request" >&2; exit 1; }
      cat "$FAKE_DIR/created.json"
    else
      [ -n "${FAKE_FAIL_LIST:-}" ] && { echo "500" >&2; exit 1; }
      cat "$FAKE_DIR/list.json"
    fi ;;
  */merge_requests/*)
    [ -n "${FAKE_FAIL_MR:-}" ] && { echo "x509: certificate signed by unknown authority" >&2; exit 1; }
    cat "$FAKE_DIR/mr.json" ;;
  *) echo "가짜 glab: 모르는 경로 $last" >&2; exit 1 ;;
esac
SH
chmod +x "$T/bin/glab"
export FAKE_LOG="$T/calls.log" FAKE_DIR="$T"

SHA=6d873dfe00000000000000000000000000000000
OLD=1111111100000000000000000000000000000000
# mr <labels-json> <head_pipeline-json|null>
mr() { printf '{"iid":660,"sha":"%s","labels":%s,"head_pipeline":%s}' "$SHA" "$1" "$2" > "$T/mr.json"; }
hp() { printf '{"id":%s,"sha":"%s","created_at":"%s","status":"running"}' "$1" "$2" "$3"; }
ev() { printf '{"action":"%s","created_at":"%s","label":{"name":"%s"}}' "$1" "$2" "$3"; }
events() { local IFS=,; printf '[%s]' "$*" > "$T/events.json"; }
printf '{"id":4900,"sha":"%s","status":"created"}' "$SHA" > "$T/created.json"
printf '[{"id":4900,"sha":"%s","status":"created"},{"id":4859,"sha":"%s","status":"running"},{"id":4858,"sha":"%s","status":"pending"},{"id":4850,"sha":"%s","status":"success"},{"id":4849,"sha":"%s","status":"manual"},{"id":4800,"sha":"%s","status":"running"}]' \
  "$SHA" "$SHA" "$SHA" "$SHA" "$SHA" "$OLD" > "$T/list.json"

# ★`${L1}` 로 감싼다 — `set -u` 에서 변수 바로 뒤에 한글 문장부호(«»)가 붙으면 변수 이름의 일부로 읽혀 unbound 로 죽는다.
run() { : > "$FAKE_LOG"; OUT=$(PATH="$T/bin:$PATH" node "$SUT" "$@" 2>"$T/err"); RC=$?; L1=$(printf '%s\n' "$OUT" | sed -n 1p); }
posts() { grep -c -- '--method POST' "$FAKE_LOG" || true; }
no_writes() { [ "$(posts)" = 0 ] && pass || fail "$1 — 바꾸는 호출(POST)이 나갔다: $(grep -- '--method POST' "$FAKE_LOG" | tr '\n' ' ')"; }

echo "── ① 라벨이 먼저 붙었으면 아무것도 만들지 않는다 (라벨 05:23:13 · 파이프라인 05:23:15 — MR 을 라벨과 함께 만든 모양)"
mr '["shared","고위험","셀프승인"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
events "$(ev add 2026-09-30T05:23:13.123Z 고위험)" "$(ev add 2026-09-30T05:23:13.123Z 셀프승인)" "$(ev add 2026-09-30T05:23:13.123Z shared)"
run 660
[ "$RC" = 0 ] && [ "$L1" = 유지 ] && pass || fail "라벨이 먼저인데 rc=$RC 1행=«${L1}» (기대 유지)"
no_writes "라벨이 먼저"
events "$(ev add 2026-09-30T05:23:15.155Z 셀프승인)"
run 660
[ "$L1" = 유지 ] && pass || fail "같은 시각(경계)은 유지여야 한다 — 1행 «${L1}»"
no_writes "같은 시각"

echo "── 게이트 라벨이 없거나, 붙인 기록이 없으면(=MR 생성 때부터) 유지"
mr '["shared"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
events "$(ev add 2026-09-30T09:00:00.000Z shared)"
run 660
[ "$RC" = 0 ] && [ "$L1" = 유지 ] && pass || fail "게이트 라벨 없음 — rc=$RC 1행 «${L1}»"
no_writes "게이트 라벨 없음"
mr '["셀프승인"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
events
run 660
[ "$RC" = 0 ] && [ "$L1" = 유지 ] && pass || fail "붙인 기록 없음 — rc=$RC 1행 «${L1}»"
no_writes "붙인 기록 없음"

echo "── 떼어낸 라벨·무관한 라벨의 늦은 기록은 세지 않는다"
mr '["고위험"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
events "$(ev add 2026-09-30T05:00:00.000Z 고위험)" "$(ev add 2026-09-30T09:00:00.000Z 셀프승인)" "$(ev remove 2026-09-30T09:10:00.000Z 셀프승인)" "$(ev add 2026-09-30T09:20:00.000Z 검수요청)" "$(ev remove 2026-09-30T09:30:00.000Z 고위험)"
run 660
[ "$L1" = 유지 ] && pass || fail "지금 없는 라벨(셀프승인)·무관 라벨·remove 기록을 셌다 — 1행 «${L1}»"
no_writes "떼어낸 라벨"

echo "── 현재 커밋의 파이프라인이 아직 없으면 만들지 않는다(push 가 곧 만든다 — 여기서 만들면 두 벌)"
mr '["셀프승인"]' "$(hp 4800 "$OLD" 2026-09-30T05:00:00.000Z)"
events "$(ev add 2026-09-30T09:00:00.000Z 셀프승인)"
run 660
# 토큰은 «유지» 가 아니라 «대기» 다 — 유지 = 할 일 없음, 대기 = 다시 물어라.
[ "$RC" = 0 ] && [ "$L1" = 대기 ] && pass || fail "옛 커밋 파이프라인 — rc=$RC 1행 «${L1}» (기대 대기)"
no_writes "옛 커밋 파이프라인"
run 660 --force
[ "$L1" = 대기 ] && pass || fail "--force 여도 현재 커밋 파이프라인이 없으면 대기 — 1행 «${L1}»"
no_writes "--force + 옛 커밋 파이프라인"
mr '["셀프승인"]' null
run 660
[ "$RC" = 0 ] && [ "$L1" = 대기 ] && pass || fail "head_pipeline 없음 — rc=$RC 1행 «${L1}» (기대 대기)"
no_writes "head_pipeline 없음"

echo "── ② 라벨이 나중에 붙었으면 새로 만들고, 같은 커밋의 돌고 있는 앞 것만 취소한다"
mr '["고위험","셀프승인"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
events "$(ev add 2026-09-30T05:00:00.000Z 고위험)" "$(ev add 2026-09-30T05:40:00.000Z 셀프승인)"
run 660
[ "$RC" = 0 ] && [ "$L1" = 새로만듦 ] && pass || fail "라벨이 나중 — rc=$RC 1행 «${L1}» (기대 새로만듦)"
printf '%s\n' "$OUT" | grep -qx '새 파이프라인: 4900' && pass || fail "새 파이프라인 번호가 안 찍힌다"
[ "$(grep -c -- '--method POST projects/:id/merge_requests/660/pipelines$' "$FAKE_LOG")" = 1 ] && pass || fail "생성 POST 가 정확히 1번이어야 한다"
CANCELED=$(grep -oE 'pipelines/[0-9]+/cancel' "$FAKE_LOG" | sed 's#pipelines/##; s#/cancel##' | sort | tr '\n' ' ')
[ "$CANCELED" = "4858 4859 " ] && pass || fail "취소 대상이 «${CANCELED}» (기대 «4858 4859 » — 새것 4900·끝난 4850·게이트에 선 4849·다른 커밋 4800 은 건드리면 안 된다)"
# 순서: 생성이 취소보다 먼저
FIRST_POST=$(grep -- '--method POST' "$FAKE_LOG" | sed -n 1p)
case "$FIRST_POST" in *merge_requests/660/pipelines) pass ;; *) fail "취소가 생성보다 먼저 나갔다: $FIRST_POST" ;; esac

echo "── 뗐다 다시 붙였으면 나중 것이 기준이다"
events "$(ev add 2026-09-30T05:00:00.000Z 셀프승인)" "$(ev remove 2026-09-30T05:30:00.000Z 셀프승인)" "$(ev add 2026-09-30T05:40:00.000Z 셀프승인)" "$(ev add 2026-09-30T05:00:00.000Z 고위험)"
run 660
[ "$L1" = 새로만듦 ] && pass || fail "다시 붙인 라벨 — 1행 «${L1}»"

echo "── 라벨 이력이 100건을 넘으면 다음 쪽까지 읽는다 (늦은 라벨이 2쪽에 있을 때)"
FILL=""
i=0
while [ "$i" -lt 100 ]; do FILL="$FILL${FILL:+,}$(ev add 2026-09-01T00:00:00.000Z 검수요청)"; i=$((i+1)); done
printf '[%s]' "$FILL" > "$T/events.json"
printf '[%s]' "$(ev add 2026-09-30T05:40:00.000Z 셀프승인)" > "$T/events2.json"
run 660 --dry-run
[ "$RC" = 0 ] && [ "$L1" = 새로만들것 ] && pass || fail "2쪽의 늦은 라벨을 못 읽었다 — rc=$RC 1행 «${L1}»"
grep -q 'page=2$' "$FAKE_LOG" && pass || fail "2쪽을 묻지 않았다: $(tr '\n' ' ' < "$FAKE_LOG")"
rm -f "$T/events2.json"

echo "── --force 는 시각 판정을 건너뛴다(유지인데 게이트가 manual 로 선 경우의 출구) — 게이트 라벨이 없으면 그래도 유지"
mr '["고위험","셀프승인"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
events "$(ev add 2026-09-30T05:23:13.123Z 고위험)" "$(ev add 2026-09-30T05:23:13.123Z 셀프승인)"
run 660
[ "$L1" = 유지 ] && pass || fail "--force 없는 대조군이 유지가 아니다 — 1행 «${L1}»"
run 660 --force
[ "$RC" = 0 ] && [ "$L1" = 새로만듦 ] && pass || fail "--force — rc=$RC 1행 «${L1}» (기대 새로만듦)"
CANCELED=$(grep -oE 'pipelines/[0-9]+/cancel' "$FAKE_LOG" | sed 's#pipelines/##; s#/cancel##' | sort | tr '\n' ' ')
[ "$CANCELED" = "4858 4859 " ] && pass || fail "--force 의 취소 대상이 «${CANCELED}»"
mr '["shared"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
run 660 --force
[ "$L1" = 유지 ] && pass || fail "게이트 라벨이 없는데 --force 가 만들었다 — 1행 «${L1}»"
no_writes "--force + 게이트 라벨 없음"
mr '["고위험","셀프승인"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
events "$(ev add 2026-09-30T05:00:00.000Z 셀프승인)" "$(ev remove 2026-09-30T05:30:00.000Z 셀프승인)" "$(ev add 2026-09-30T05:40:00.000Z 셀프승인)" "$(ev add 2026-09-30T05:00:00.000Z 고위험)"

echo "── --dry-run 은 말만 한다"
run 660 --dry-run
[ "$RC" = 0 ] && [ "$L1" = 새로만들것 ] && pass || fail "dry-run — rc=$RC 1행 «${L1}»"
no_writes "dry-run"

echo "── ③ 만들기가 실패하면 취소하지 않는다"
: > "$FAKE_LOG"; OUT=$(FAKE_FAIL_CREATE=1 PATH="$T/bin:$PATH" node "$SUT" 660 2>/dev/null); RC=$?
[ "$RC" = 2 ] && pass || fail "생성 실패인데 rc=$RC (기대 2)"
[ "$(grep -c '/cancel' "$FAKE_LOG")" = 0 ] && pass || fail "생성이 실패했는데 앞 파이프라인을 취소했다 — MR 에 도는 파이프라인이 0개가 된다"
printf '%s\n' "$OUT" | grep -qx '새로만듦' && fail "생성이 실패했는데 «새로만듦» 을 찍었다" || pass

echo "── ④ 모르면 판정 불능(2) — «유지»로 위장하지 않는다"
for v in FAKE_FAIL_MR FAKE_FAIL_EVENTS; do
  : > "$FAKE_LOG"; OUT=$(env "$v=1" PATH="$T/bin:$PATH" node "$SUT" 660 2>/dev/null); RC=$?
  [ "$RC" = 2 ] && [ -z "$OUT" ] && pass || fail "$v — rc=$RC · stdout «${OUT}» (기대 2·무출력)"
  no_writes "$v"
done
: > "$FAKE_LOG"; OUT=$(FAKE_FAIL_LIST=1 PATH="$T/bin:$PATH" node "$SUT" 660 2>/dev/null); RC=$?
[ "$RC" = 2 ] && pass || fail "앞 파이프라인 목록 조회 실패인데 rc=$RC (취소를 못 했으면 2)"
: > "$FAKE_LOG"; OUT=$(FAKE_FAIL_CANCEL=1 PATH="$T/bin:$PATH" node "$SUT" 660 2>/dev/null); RC=$?
[ "$RC" = 2 ] && pass || fail "취소 실패인데 rc=$RC (두 벌이 도는 채 0 을 내면 안 된다)"
printf '{"message":"404 Not found"}' > "$T/mr.json"
run 660
[ "$RC" = 2 ] && [ -z "$OUT" ] && pass || fail "MR 이 아닌 응답인데 rc=$RC · stdout «${OUT}»"
mr '["셀프승인"]' "$(hp 4859 "$SHA" 2026-09-30T05:23:15.155Z)"
events "$(ev add 이건-시각이-아니다 셀프승인)"
run 660
[ "$RC" = 2 ] && pass || fail "시각을 못 읽었는데 rc=$RC (못 읽은 시각을 «먼저 붙었다»로 치면 안 된다)"
no_writes "시각 못 읽음"
run
[ "$RC" = 2 ] && pass || fail "인자 없음인데 rc=$RC"
run 66a
[ "$RC" = 2 ] && [ ! -s "$FAKE_LOG" ] && pass || fail "숫자 아닌 번호인데 rc=$RC 또는 glab 을 불렀다"

echo "── ⑤ GATE_LABELS ↔ .gitlab-ci.yml 게이트 잡이 읽는 라벨"
# CI 쪽: `$CI_MERGE_REQUEST_LABELS =~ /…/` 정규식에서 라벨 이름만 뽑는다(앵커 `(^|,)`·`(,|$)` 제거).
if [ ! -f "$CI_YML" ]; then fail "⑤ $CI_YML 이 없다 — 판정 불능"; else
  CI_LABELS=$(grep -aoE 'CI_MERGE_REQUEST_LABELS =~ /[^/]+/' "$CI_YML" | sed 's#.*=~ /##; s#/$##; s#(\^|,)##; s#(,|\$)##' | sort -u)
  JS_LABELS=$(grep -aE '^const GATE_LABELS' "$SUT" | grep -oE "'[^']+'" | tr -d "'" | sort -u)
  [ -n "$CI_LABELS" ] && pass || fail "⑤ CI 에서 게이트 라벨을 0개 읽었다 — 잣대가 빗나감"
  [ -n "$JS_LABELS" ] && pass || fail "⑤ 스크립트에서 GATE_LABELS 를 0개 읽었다 — 잣대가 빗나감"
  [ "$CI_LABELS" = "$JS_LABELS" ] && pass || fail "⑤ 라벨이 다르다 — CI «$(echo $CI_LABELS)» · 스크립트 «$(echo $JS_LABELS)»"
fi

echo "────────  $OK OK / $FAIL FAIL"
[ "$FAIL" -eq 0 ]
