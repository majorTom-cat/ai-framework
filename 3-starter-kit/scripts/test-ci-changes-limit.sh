#!/usr/bin/env bash
# `.gitlab-ci.yml` 의 `changes:` 목록 하나하나가 50줄을 넘지 않는지 센다. CI `self-tests` 가 자동으로 줍는다.
# 사용: bash scripts/test-ci-changes-limit.sh [CI파일]      (인자 없으면 저장소 루트의 .gitlab-ci.yml)
#
# 왜 있나: GitLab 은 `rules: changes:` 목록이 50개를 넘으면 «changes has too many entries (maximum 50)» 로
#   **설정 전체를 무효**로 본다 — 파이프라인이 아예 안 만들어져 전 게이트가 꺼진다. 그런데 무효인 설정에서는
#   CI 자기시험도 안 돌고, 로컬 자기시험은 YAML 을 문법으로만 읽어 전부 초록이다. `glab ci lint` 만 잡는데 그건
#   사람이 기억할 때만 돈다. 그래서 «넘기 전에» 로컬 `run-self-tests` 와 CI `self-tests` 가 막는다.
# 세는 것: 블록 목록(`- 항목` 줄 — 주석 줄 제외)·한 줄 목록(`[a, b]` — 따옴표·중괄호 안 쉼표는 안 센다)·
#   `changes: paths:` 형태. 별칭(`*이름`)은 원본(`&이름`) 자리에서 센다 — 원본이 `changes:` 밑이 아니라
#   따로 둔 키(`.code_changes: &code_changes`)여도 `changes: *code_changes` 로 쓰이면 그 목록을 센다.
# 종료: 0 = 전부 50 이하 · 1 = 넘는 목록 있음 또는 잣대가 빗나감(목록을 거의 못 읽음)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
CI_YML="${1:-$(pwd)/.gitlab-ci.yml}"
LIMIT=50
[ -f "$CI_YML" ] || { echo "⛔ CI 파일이 없다: $CI_YML — 판정 불능"; exit 1; }

# 출력: 줄번호<TAB>이름<TAB>개수 — 목록마다 한 줄
COUNTS=$(awk '
function indent(s) { match(s, /^ */); return RLENGTH }
function count_inline(s,    i, c, n, q, br, sawtok) {
  # s = "[" 부터 "]" 까지. 최상위 쉼표 + 1 (빈 목록이면 0)
  n = 0; q = ""; br = 0; sawtok = 0
  for (i = 2; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; continue }
    if (c == "\"" || c == "\047") { q = c; sawtok = 1; continue }
    if (c == "{") { br++; sawtok = 1; continue }
    if (c == "}") { br--; continue }
    if (c == "]" && br == 0) break
    if (c == "," && br == 0) { n++; continue }
    if (c != " ") sawtok = 1
  }
  return sawtok ? n + 1 : 0
}
function flush() { if (mode != "") { print start "\t" name "\t" cnt }; mode = "" }
function open_list(rest) {
  if (rest ~ /^\[/) {
    if (index(rest, "]") > 0) { mode = "x"; cnt = count_inline(rest); flush(); return }
    mode = "inline"; buf = rest; return
  }
  mode = "block"
}
# 1차 읽기: `changes: *이름` 으로 쓰이는 별칭 이름을 모은다
FNR == NR {
  if (match($0, /changes:[[:space:]]*\*[A-Za-z0-9_.-]+/)) { a = substr($0, RSTART, RLENGTH); sub(/^.*\*/, "", a); used[a] = 1 }
  next
}
{
  line = $0
  if (mode == "inline") {
    buf = buf " " line
    if (index(line, "]") > 0) { cnt = count_inline(buf); flush() }
    next
  }
  if (mode == "block") {
    if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) next
    ind = indent(line)
    body = substr(line, ind + 1)
    if (ind < col || (ind == col && body !~ /^- /)) { flush() }
    else if (body ~ /^paths:[[:space:]]*\[/) {
      s = substr(body, index(body, "["))
      if (index(s, "]") > 0) { cnt = count_inline(s); flush(); next }
      mode = "inline"; buf = s; next
    }
    else if (body ~ /^- /) {
      if (itemind < 0) itemind = ind
      if (ind == itemind) cnt++
      next
    }
    else next
  }
  if (line ~ /^[[:space:]]*(- )?changes:/) {
    p = index(line, "changes:")
    col = p - 1
    rest = substr(line, p + 8)
    sub(/^[[:space:]]+/, "", rest)
    start = FNR; cnt = 0; itemind = -1; name = "(이름없음)"
    if (rest ~ /^\*/) next                       # 별칭 — 원본(&이름) 자리에서 센다
    if (rest ~ /^&/) { name = rest; sub(/[[:space:]].*$/, "", name); sub(/^&/, "", name); rest = substr(rest, length(name) + 2); sub(/^[[:space:]]+/, "", rest) }
    open_list(rest)
    next
  }
  # `changes:` 밖에서 정의됐지만 `changes: *이름` 으로 쓰이는 앵커 목록
  if (line !~ /^[[:space:]]*#/ && match(line, /:[[:space:]]*&[A-Za-z0-9_.-]+/)) {
    nm = substr(line, RSTART, RLENGTH); sub(/^.*&/, "", nm)
    if (nm in used) {
      col = indent(line); start = FNR; cnt = 0; itemind = -1; name = nm
      rest = substr(line, RSTART + RLENGTH); sub(/^[[:space:]]+/, "", rest)
      open_list(rest)
    }
  }
}
END { flush() }
' "$CI_YML" "$CI_YML")

OK=0; FAIL=0
N=$(printf '%s\n' "$COUNTS" | grep -c . || true)
echo "── changes: 목록 ${N}개 (상한 ${LIMIT})"
printf '%s\n' "$COUNTS" | awk -F'\t' 'NF==3 { printf "   %4s행  %-18s %s줄\n", $1, $2, $3 }'
# 잣대가 빗나가면 0 이 나와 «전부 통과»가 된다 — 최소 개수로 막는다.
if [ "$N" -ge 3 ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); echo "  ⛔ FAIL: changes: 목록을 ${N}개밖에 못 읽었다 — 잣대가 빗나감(판정 불능)"; fi
HR=$(printf '%s\n' "$COUNTS" | awk -F'\t' '$2=="high-risk-paths"{print $3}')
if [ -n "$HR" ] && [ "$HR" -ge 10 ]; then OK=$((OK+1)); elif [ -f "$CI_YML" ] && grep -q '&high-risk-paths' "$CI_YML"; then FAIL=$((FAIL+1)); echo "  ⛔ FAIL: high-risk-paths 를 ${HR:-0}줄밖에 못 읽었다 — 잣대가 빗나감"; fi
OVER=$(printf '%s\n' "$COUNTS" | awk -F'\t' -v L="$LIMIT" 'NF==3 && $3+0 > L')
if [ -z "$OVER" ]; then OK=$((OK+1)); else
  FAIL=$((FAIL+1))
  printf '%s\n' "$OVER" | while IFS="$(printf '\t')" read -r ln nm c; do
    echo "  ⛔ FAIL: ${ln}행 changes(${nm})가 ${c}줄이다(상한 ${LIMIT}) — GitLab 이 설정 전체를 무효로 본다. 글로브로 합쳐라"
  done
fi
echo "────────  $OK OK / $FAIL FAIL"
[ "$FAIL" -eq 0 ]
