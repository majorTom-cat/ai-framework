#!/usr/bin/env bash
# warning-ack.cjs 회귀 테스트 — `bash scripts/test-warning-ack.sh`
# 왜 있나: 이 도구의 1행(경고없음|경고처리됨|경고미처리|미종료)을 /done 이 그대로 믿고 머지한다. 가드가 풀려 «경고미처리»를
#   «경고처리됨» 으로 내거나 조회 실패를 «경고없음» 으로 위장하면 경고가 다시 무음으로 새는데, 행동 시험이 없으면 아무도 모른다.
# 방법: 가짜 `glab` 을 PATH 앞에 두고 고정 JSON·로그를 내게 한다 — 네트워크·인증 없이 판정 논리만 잰다.
# ★대조군(경고 없음·정상 처리)이 먼저 초록이어야 뒤의 빨강이 의미가 있다. 가드를 지운 가짜 도구로 돌리면 빨개져야 한다:
#   WARNING_ACK_TOOL=/경로/가짜.cjs bash scripts/test-warning-ack.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="${WARNING_ACK_TOOL:-$HERE/warning-ack.cjs}"
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 이 도구는 node 로 돈다. 검증 불능(합격 아님)."; exit 1; }
[ -f "$TOOL" ] || { echo "⛔ 도구가 없다: $TOOL"; exit 1; }
TMP="$(mktemp -d)" || { echo "⛔ 임시 폴더를 못 만들었다(울타리?) — 저장소에 픽스처를 떨어뜨리지 않으려고 멈춘다"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/fx" || exit 1
# 가짜 glab: 경로로 갈라 FX 폴더의 고정 파일을 낸다. FAKE_FAIL_ON=mr|jobs|notes|trace 면 그 조회만 실패
cat > "$TMP/bin/glab" <<'EOF'
#!/bin/sh
p="$2"
fail() { echo "x509: certificate signed by unknown authority" >&2; exit 1; }
case "$p" in
  *merge_requests/*/notes*) [ "${FAKE_FAIL_ON:-}" = notes ] && fail; cat "$FX/notes.json";;
  *merge_requests/*)        [ "${FAKE_FAIL_ON:-}" = mr ] && fail; cat "$FX/mr.json";;
  *pipelines/*/jobs*)       [ "${FAKE_FAIL_ON:-}" = jobs ] && fail; cat "$FX/jobs.json";;
  *jobs/*/trace)            [ "${FAKE_FAIL_ON:-}" = trace ] && fail; id="${p#*jobs/}"; id="${id%/trace}"; cat "$FX/trace-$id.txt";;
  *) echo "알 수 없는 경로: $p" >&2; exit 1;;
esac
EOF
chmod +x "$TMP/bin/glab" || exit 1
. "$HERE/lib/fake-cli.sh"; fake_cli_win "$TMP/bin" glab || exit 1
OK=0; FAIL=0
SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OLD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

mr() { # $1=head_pipeline.sha (- 면 head_pipeline null)
  if [ "$1" = - ]; then printf '{"iid":7,"sha":"%s","head_pipeline":null}' "$SHA" > "$TMP/fx/mr.json"
  else printf '{"iid":7,"sha":"%s","head_pipeline":{"id":100,"sha":"%s"}}' "$SHA" "$1" > "$TMP/fx/mr.json"; fi
}
J() { printf '{"id":%s,"name":"%s","status":"%s","allow_failure":%s}' "$1" "$2" "$3" "$4"; }
jobs() { printf '[%s]' "$1" > "$TMP/fx/jobs.json"; }
note() { # $1=id $2=본문 [$3=system]
  python3 - "$1" "$2" "${3:-false}" >> "$TMP/fx/notes.list" <<'PY'
import json, sys
print(json.dumps({"id": int(sys.argv[1]), "body": sys.argv[2], "system": sys.argv[3] == "true"}))
PY
}
notes_flush() { python3 -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1]) if l.strip()]))' "$TMP/fx/notes.list" > "$TMP/fx/notes.json"; }
reset() { : > "$TMP/fx/notes.list"; echo '[]' > "$TMP/fx/notes.json"; rm -f "$TMP/fx"/trace-*.txt; unset FAKE_FAIL_ON; }
trace() { printf '%b' "$2" > "$TMP/fx/trace-$1.txt"; }   # $1=잡 id $2=로그(\n 해석)

# $1=설명 $2=기대 종료코드 $3=기대 1행(- 면 안 봄) [$4=있어야 할 조각] [$5=없어야 할 조각]
t() {
  notes_flush
  OUT=$(FX="$TMP/fx" PATH="$TMP/bin:$PATH" node "$TOOL" 7 2>&1); RC=$?
  L1=$(printf '%s\n' "$OUT" | head -1)
  if [ "$RC" != "$2" ]; then echo "  ⛔ $1 — 종료코드 기대 $2 실제 $RC → $OUT"; FAIL=$((FAIL+1)); return; fi
  if [ "$3" != - ] && [ "$L1" != "$3" ]; then echo "  ⛔ $1 — 1행 기대 '$3' 실제 '$L1'"; FAIL=$((FAIL+1)); return; fi
  if [ -n "${4:-}" ] && ! printf '%s' "$OUT" | grep -qF -- "$4"; then echo "  ⛔ $1 — '$4' 없음 → $OUT"; FAIL=$((FAIL+1)); return; fi
  if [ -n "${5:-}" ] && printf '%s' "$OUT" | grep -qF -- "$5"; then echo "  ⛔ $1 — '$5' 가 나오면 안 된다 → $OUT"; FAIL=$((FAIL+1)); return; fi
  OK=$((OK+1)); echo "  OK  $1"
}

LOG2='════════ [낡은기록] ⛔ 실패\n[경고:낡은기록] docs/a.md 가 낡았다\n[경고:새UI] 화면 변경 기록 없음\n════════ [통과한검사] OK\n'
H="sha=$SHA pipeline=100 job=11"

echo "── A. 대조군 — 경고 없음 / 정상 처리"
reset; mr $SHA; jobs "$(J 1 test success false),$(J 2 density-check success true)"
t '경고 잡 없음 → 경고없음' 0 경고없음
reset; mr $SHA; jobs "$(J 1 test success false),$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"
note 5 "경고 처리 $H
- 낡은기록: 수정함 — docs/a.md 갱신
- 새UI: 수정불필요 — 비화면 파일"
t '경고 2개 모두 기록 → 경고처리됨' 0 경고처리됨 '처리됨: mr-warnings(잡 11) 항목 2개'
reset; mr $SHA; jobs "$(J 1 test failed false)"
t '차단형 잡 실패는 경고가 아니다(pipeline-verdict 몫) → 경고없음' 0 경고없음
reset; mr $SHA; jobs "$(J 1 test success false),$(J 2 pages manual true)"
t '무시 가능 manual 은 미종료가 아니다 → 경고없음' 0 경고없음

echo "── B. 기록이 모자라면 막는다 (가드가 산다는 증거)"
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"
t '기록 없음 → 경고미처리 (키·머리 줄 서식을 알려 준다)' 0 경고미처리 "기록 머리 줄: $H"
t '미처리 항목 이름이 나온다' 0 경고미처리 '낡은기록'
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"
note 5 "$H
- 낡은기록: 수정함 — 갱신함"
t '항목 하나 빠짐 → 경고미처리 (빠진 것만 지목)' 0 경고미처리 '새UI — 처리 기록이 없다' '- 낡은기록 —'
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"
note 5 "sha=$OLD pipeline=100 job=11
- 낡은기록: 수정함 — 갱신함
- 새UI: 수정불필요 — 비화면"
t '다른 sha 의 기록은 재사용 안 함 → 경고미처리' 0 경고미처리
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"
note 5 "sha=$SHA pipeline=99 job=11
- 낡은기록: 수정함 — 갱신함
- 새UI: 수정불필요 — 비화면"
t '다른 파이프라인 번호의 기록은 재사용 안 함 → 경고미처리' 0 경고미처리
reset; mr $SHA; jobs "$(J 12 mr-warnings failed true)"; trace 12 "$LOG2"
note 5 "$H
- 낡은기록: 수정함 — 갱신함
- 새UI: 수정불필요 — 비화면"
t '재실행으로 잡 번호가 바뀌면 옛 기록은 무효 → 경고미처리' 0 경고미처리 "job=12"
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"
note 5 "$H
- 낡은기록: 수정함 —
- 새UI: 수정불필요 — 비화면"
t '근거가 빈 항목 → 경고미처리' 0 경고미처리 '낡은기록 — 처리 기록이 없다'
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"
note 5 "$H
- 낡은기록: 나중에봄 — 갱신
- 새UI: 수정불필요 — 비화면"
t '처리값이 규정 밖(나중에봄) → 경고미처리' 0 경고미처리
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"
note 5 "$H
- 낡은기록: 수정함 — 갱신함
- 새UI: 수정불필요 — 비화면" true
t '시스템 댓글의 기록은 안 센다 → 경고미처리' 0 경고미처리

echo "── C. 키 규약 — 키가 없으면 검사이름, 구간이 없으면 잡 이름"
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 '════════ [tamper-check] ⛔ 실패\n테스트가 약해졌다\n'
note 5 "$H
- tamper-check: 수정불필요 — 의도한 변경"
t '구간에 [경고:키] 없음 → 검사이름이 항목 → 경고처리됨' 0 경고처리됨
reset; mr $SHA; jobs "$(J 11 density-check failed true)"; trace 11 '밀도 초과\n'
note 5 "$H
- density-check: 수정함 — 줄 줄임"
t '구간 자체가 없으면 잡 이름이 항목 → 경고처리됨' 0 경고처리됨
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 '════════ [통과한검사] OK\n[경고:엉뚱] 통과 구간의 줄\n════════ [x] ⛔ 실패\n내용\n'
note 5 "$H
- x: 수정함 — 고침"
t '⛔ 실패 구간 밖의 [경고:키] 는 항목이 아니다 → 경고처리됨' 0 경고처리됨
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 '════════ [a] ⛔ 실패\n\033[31m[경고:색깔]\033[0m 내용\n'
note 5 "$H
- 색깔: 수정함 — 고침"
t '로그의 색 코드(ANSI)를 벗겨 읽는다 → 경고처리됨' 0 경고처리됨

echo "── D. 잡이 둘 — 둘 다 기록돼야 한다"
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true),$(J 13 density-check failed true)"; trace 11 "$LOG2"; trace 13 'x\n'
note 5 "$H
- 낡은기록: 수정함 — 갱신
- 새UI: 수정불필요 — 비화면"
t '한 잡만 기록 → 경고미처리 (다른 잡을 지목)' 0 경고미처리 'density-check(잡 13)'
note 6 "sha=$SHA pipeline=100 job=13
- density-check: 수정함 — 줄임"
t '다른 댓글에 나머지 잡 기록을 더하면 → 경고처리됨' 0 경고처리됨

echo "── E. 아직 모른다 — 미종료"
reset; mr $SHA; jobs "$(J 1 test success false),$(J 11 mr-warnings running true)"
t '경고 잡이 도는 중 → 미종료' 0 미종료 'mr-warnings(running)'
reset; mr $SHA; jobs "$(J 1 test success false),$(J 11 mr-warnings pending true)"
t '경고 잡이 대기 중 → 미종료' 0 미종료
reset; mr $OLD; jobs "$(J 1 test success false)"
t '파이프라인이 다른 커밋의 것(낡은 파이프라인) → 미종료' 0 미종료 '낡은 파이프라인'
reset; mr -; jobs "$(J 1 test success false)"
t '이 커밋의 파이프라인이 없음 → 미종료' 0 미종료

echo "── F. 판정 불능은 exit 2 — 어느 토큰으로도 위장하지 않는다"
for on in mr jobs notes trace; do
  reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 "$LOG2"; export FAKE_FAIL_ON=$on
  t "$on 조회 실패 → exit 2" 2 -
  for tok in 경고없음 경고처리됨 경고미처리 미종료; do
    notes_flush
    FX="$TMP/fx" PATH="$TMP/bin:$PATH" node "$TOOL" 7 2>/dev/null | grep -qx "$tok" && { echo "  ⛔ $on 조회 실패인데 stdout 에 '$tok'"; FAIL=$((FAIL+1)); }
  done
done
reset; mr $SHA; jobs ''
t '잡 0개 → exit 2' 2 -
OUT=$(FX="$TMP/fx" PATH="$TMP/bin:$PATH" node "$TOOL" abc 2>&1); RC=$?
[ "$RC" = 2 ] && { OK=$((OK+1)); echo "  OK  숫자 아닌 MR 번호 → exit 2"; } || { echo "  ⛔ 숫자 아닌 번호 — exit $RC → $OUT"; FAIL=$((FAIL+1)); }

echo "── G. 비밀값을 옮기지 않는다 — 로그 원문은 출력에 없다"
reset; mr $SHA; jobs "$(J 11 mr-warnings failed true)"; trace 11 '════════ [a] ⛔ 실패\n[경고:키1] TOKEN=glpat-SECRET123 이 로그에 찍혔다\n'
t '미처리 출력에 로그 원문(토큰)이 없다' 0 경고미처리 '' 'glpat-SECRET123'

echo "──────── $OK OK / $FAIL FAIL"
[ "$FAIL" -eq 0 ] || exit 1
