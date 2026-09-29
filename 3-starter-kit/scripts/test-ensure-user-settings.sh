#!/usr/bin/env bash
# ensure-user-settings.cjs 회귀 테스트 — `bash scripts/test-ensure-user-settings.sh`
# 왜 있나: 이 훅은 세션마다 «사람의 개인 설정 파일»에 쓴다. 틀리면 남의 설정을 날리거나 매번 다시 쓴다(2026-09-29 배포처 friction).
# 방법: CLAUDE_CONFIG_DIR 을 임시 폴더로 돌려 진짜 ~/.claude 는 절대 안 건드린다.
# 보는 것: 없음(새로 만든다) · 있음(더하기만, 원본 .bak-kit) · 이미 있음(안 쓴다 = 매 세션 재작성 아님) · 깨진 JSON(건너뛴다, 원본 보존).
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/ensure-user-settings.cjs"
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 이 훅은 node 로 돈다. 검증 불능(합격 아님)."; exit 1; }
[ -f "$HOOK" ] || { echo "⛔ 훅이 없다: $HOOK — 테스트 실패가 아니라 미배포다."; exit 1; }
TMP="$(mktemp -d)" || { echo "⛔ 임시 폴더를 못 만들었다(울타리?) — 진짜 설정에 쓰지 않으려고 멈춘다"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
OK=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then OK=$((OK+1)); echo "  OK  $1"; else FAIL=$((FAIL+1)); echo "  ⛔ $1 — 기대 '$2' 실제 '$3'"; fi; }
run() { CLAUDE_CONFIG_DIR="$1" HOME="$TMP/nohome" node "$HOOK" 2>&1; }   # HOME 도 돌려 새어 나가면 티가 나게
val() { node -e 'try{const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(String(s.sandbox&&s.sandbox.network&&s.sandbox.network.allowLocalBinding)+"|"+String(s.keep))}catch(e){console.log("읽기실패")}' "$1"; }

echo "── A. 파일 없음 → 새로 만든다(.bak 없음)"
D="$TMP/a"; OUT=$(run "$D"); RC=$?
ck 'exit 0' 0 "$RC"
ck '값이 들어갔다' 'true|undefined' "$(val "$D/settings.json")"
ck '.bak-kit 없음(원본이 없었다)' no "$([ -e "$D/settings.json.bak-kit" ] && echo yes || echo no)"
ck '알림 한 줄' yes "$(printf '%s' "$OUT" | grep -q '자동으로 넣음' && echo yes || echo no)"

echo "── B. 파일 있음·값 없음 → 더하기만, 원본은 .bak-kit"
D="$TMP/b"; mkdir -p "$D"; printf '{"keep":"mine","sandbox":{"enabled":true}}\n' > "$D/settings.json"
cp "$D/settings.json" "$TMP/b.orig"
OUT=$(run "$D"); RC=$?
ck 'exit 0' 0 "$RC"
ck '값 추가 + 기존 키 보존' 'true|mine' "$(val "$D/settings.json")"
ck '기존 sandbox 하위 키 보존' true "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).sandbox.enabled)' "$D/settings.json")"
ck '.bak-kit = 원본 그대로' same "$(cmp -s "$D/settings.json.bak-kit" "$TMP/b.orig" && echo same || echo diff)"

echo "── C. 이미 있음 → 안 쓴다(매 세션 재작성 아님)"
D="$TMP/c"; mkdir -p "$D"; printf '{\n    "sandbox": {"network": {"allowLocalBinding": true}}, "keep": 1\n}\n' > "$D/settings.json"
cp "$D/settings.json" "$TMP/c.orig"
OUT=$(run "$D"); RC=$?
ck 'exit 0' 0 "$RC"
ck '파일 바이트 그대로(서식도 안 바뀜)' same "$(cmp -s "$D/settings.json" "$TMP/c.orig" && echo same || echo diff)"
ck '.bak-kit 안 만든다' no "$([ -e "$D/settings.json.bak-kit" ] && echo yes || echo no)"
ck '출력 없음' '' "$OUT"
OUT=$(run "$TMP/a")   # A 에서 만든 파일로 두 번째 세션 — 멱등
ck 'A 두 번째 실행도 조용' '' "$OUT"

echo "── D. 값이 false → true 로 고친다"
D="$TMP/d"; mkdir -p "$D"; printf '{"sandbox":{"network":{"allowLocalBinding":false}}}\n' > "$D/settings.json"
run "$D" >/dev/null
ck 'false → true' 'true|undefined' "$(val "$D/settings.json")"

echo "── E. 깨진 JSON → 건너뛴다(원본 보존·.bak 없음·exit 0)"
D="$TMP/e"; mkdir -p "$D"; printf '{"keep": "mine",,, 깨짐\n' > "$D/settings.json"
cp "$D/settings.json" "$TMP/e.orig"
OUT=$(run "$D"); RC=$?
ck 'exit 0(세션을 막지 않는다)' 0 "$RC"
ck '원본 바이트 그대로' same "$(cmp -s "$D/settings.json" "$TMP/e.orig" && echo same || echo diff)"
ck '.bak-kit 안 만든다' no "$([ -e "$D/settings.json.bak-kit" ] && echo yes || echo no)"
ck '건너뜀을 알린다' yes "$(printf '%s' "$OUT" | grep -q '건너뜀' && echo yes || echo no)"

echo "── F. 새어 나감 없음 — HOME 쪽엔 아무것도 안 생긴다"
ck '가짜 HOME 비어 있음' no "$([ -e "$TMP/nohome" ] && echo yes || echo no)"

echo "──────── $OK OK / $FAIL FAIL"
[ "$FAIL" -eq 0 ] || exit 1
