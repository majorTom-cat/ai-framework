#!/usr/bin/env bash
# archive-friction.py 의 회귀 테스트 — «어느 5줄이 남는가»가 이 도구의 전부다.
# ★B 케이스가 이 파일의 존재 이유다: 2026-09-10 에 뒤집기 판정이 «첫 줄 대 마지막 줄»이라,
#   bnsone friction.md 처럼 **첫 줄도 마지막 줄도 같은 날짜**인 파일을 «최신이 위»로 오판했다.
#   그대로 돌렸으면 **가장 오래된 닫힘 5줄이 남고 최신 닫힘이 보관으로 갔다** — 정반대 결과다.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/archive-friction.py"
TMP="$(mktemp -d)" || { echo "⛔ 임시 폴더를 못 만들었다(울타리?) — 저장소에 픽스처를 떨어뜨리지 않으려고 멈춘다"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
OK=0; FAIL=0

# ★의존 명령 부재는 «건너뜀»이 아니라 **실패**다 — 이 repo 가 반복해서 밟은 실패 유형이 정확히
#   「도구가 없어 검사가 통째로 무음이 되고 초록으로 집계」다(CI 이미지에 git 이 없어 훅 검사가 무음이던 건).
#   2026-09-10 실측: bnsone `self-tests` 잡 이미지(node:24-slim)에 python3 가 없어 이 시험이 **7케이스
#   전부 «기대와 다름»으로 떨어졌는데, 로그 어디에도 «python3 가 없다»는 말이 없었다** — 원인을
#   「검사기가 틀렸다」로 오독하게 만든다. 그래서 여기서 먼저 이름을 대고 죽는다.
command -v python3 >/dev/null 2>&1 || {
  echo "⛔ python3 가 없다 — archive-friction.py 는 python 스크립트다."
  echo "   «도구가 없어서 안 돌았다»를 초록으로 넘기지 않는다. CI 라면 그 잡의 이미지에 python3 를 깔아라"
  echo "   (킷 self-tests = alpine: \`apk add python3\` · 배포처 self-tests = node:24-slim: \`apt-get install -y python3\`)."
  exit 1
}

ck() { # $1=설명 $2=기대 $3=실제
  if [ "$2" = "$3" ]; then OK=$((OK+1))
  else
    FAIL=$((FAIL+1)); echo "  ⛔ $1"; echo "     기대: $2"; echo "     실제: $3"
    # ★도구가 뭐라고 했는지 함께 찍는다 — 안 찍으면 «기대와 다름»만 남아 원인이 사라진다(2026-09-10 CI 실측)
    [ -s "$TMP/last.out" ] && { echo "     도구 출력:"; sed 's/^/       /' "$TMP/last.out" | head -4; }
  fi
}
# ★`cut -c` 는 macOS 에서 바이트라 한글이 잘린다 — 문구 포함 여부로 본다(단위 함정: 한글 1자 = 3바이트)
has_first_kept() { grep -A1 '^## 최근에 끝난 것' "$TMP/f.md" | tail -1 | grep -q "$1" && echo yes || echo no; }
n_entries()  { grep -cE '^[0-9]{4}-' "$1" || true; }

mk() { : > "$TMP/f.md"; rm -f "$TMP/a.md"; printf '# 머리\n\n> 규약 한 줄\n\n' > "$TMP/f.md"; cat >> "$TMP/f.md"; }
run() { python3 "$TOOL" "$TMP/f.md" "$TMP/a.md" "${1:-2}" ${2:-} > "$TMP/last.out" 2>&1; cat "$TMP/last.out"; }

echo "── A. «오래된 것이 위» 파일은 뒤집는다 — 최신 닫힘이 남는다"
mk <<'E'
2026-09-01 옛것 [닫힘:구기록]
2026-09-05 중간 [닫힘:구기록]
2026-09-09 최신 [닫힘:구기록]
E
OUT="$(run 2 --oldest-first)"
ck "A1 뒤집었다고 말한다" "yes" "$(printf '%s' "$OUT" | grep -q 'oldest-first' && echo yes || echo no)"
ck "A2 맨 위가 최신" "yes" "$(has_first_kept '2026-09-09 최신')"
ck "A3 손실 0" "3" "$(( $(n_entries "$TMP/f.md") + $(n_entries "$TMP/a.md") ))"

echo "── B. ★첫 줄과 마지막 줄의 날짜가 «같아도» 뒤집는다 (bnsone 실물 모양)"
mk <<'E'
2026-09-09 가장먼저적은것 [닫힘:구기록]
2026-09-10 다음날적은것 [닫힘:구기록]
2026-09-09 마지막에적은것 [닫힘:구기록]
E
OUT="$(run 1)"
ck "B1 ★추측하지 않고 «경고»를 낸다 — 날짜가 같아 «많으냐»로 물으면 동점이 된다" "yes" "$(printf '%s' "$OUT" | grep -q 'oldest-first' && echo yes || echo no)"
mk <<'E'
2026-09-09 가장먼저적은것 [닫힘:구기록]
2026-09-10 다음날적은것 [닫힘:구기록]
2026-09-09 마지막에적은것 [닫힘:구기록]
E
run 1 --oldest-first >/dev/null
ck "B2 «마지막에 적은 것»이 남는다" "yes" "$(has_first_kept '마지막에적은것')"

echo "── C. «최신이 위» 파일은 그대로 둔다 (두 번 돌려도 순서가 안 뒤집힌다)"
mk <<'E'
2026-09-09 최신 [닫힘:구기록]
2026-09-05 중간 [닫힘:구기록]
2026-09-01 옛것 [닫힘:구기록]
E
OUT="$(run 2)"
ck "C1 뒤집지 않고 경고도 없다" "no" "$(printf '%s' "$OUT" | grep -qE 'oldest-first' && echo yes || echo no)"
ck "C2 맨 위가 최신 그대로" "yes" "$(has_first_kept '2026-09-09 최신')"

echo "── D. 열린 줄은 KEEP 과 무관하게 전부 남는다 — «아직 안 고쳐진 것»을 보관으로 보내면 안 된다"
mk <<'E'
2026-09-09 최신닫힘 [닫힘:구기록]
2026-09-08 열림하나
2026-09-07 열림둘
2026-09-06 옛닫힘 [닫힘:구기록]
E
run 1 >/dev/null
ck "D1 열린 줄 2개가 작업 파일에 남는다" "2" "$(grep -cE '^[0-9]{4}-' "$TMP/f.md" | xargs -I{} sh -c 'grep -E "^[0-9]{4}-" "$0" | grep -vc "\[닫힘:"' "$TMP/f.md")"
ck "D2 보관으로 간 것은 닫힘뿐" "1" "$(n_entries "$TMP/a.md")"

echo "── E. 두 번 돌려도 항목이 늘지 않는다 (보관 파일 중복 방지)"
run 1 >/dev/null
ck "E1 보관 항목 수 그대로" "1" "$(n_entries "$TMP/a.md")"

echo "── F. ★열린 줄이 하나도 없어도 «(없음)» 자리표시가 머리말에 쌓이지 않는다"
mk <<'E'
2026-09-09 닫힘하나 [닫힘:구기록]
E
run 1 >/dev/null
run 1 >/dev/null
run 1 >/dev/null
ck "F1 «(없음)» 은 «지금 살아 있는 것» 아래 딱 한 줄" "1" "$(grep -c '^(없음)$' "$TMP/f.md")"
ck "F2 구획 제목도 한 벌뿐" "1" "$(grep -c '^## 지금 살아 있는 것' "$TMP/f.md")"

echo "── G. ★제목 «위»에 이미 쌓인 고아 «(없음)» 은 걷어낸다 (F 는 이 방어를 안 건드린다 — 제목 아래만 본다)"
: > "$TMP/f.md"; rm -f "$TMP/a.md"
printf '# 머리\n\n> 규약 한 줄\n\n(없음)\n\n(없음)\n\n## 지금 살아 있는 것 — 아직 안 고쳐진 줄\n(없음)\n\n## 최근에 끝난 것 (최신 1줄)\n2026-09-09 닫힘하나 [닫힘:구기록]\n' > "$TMP/f.md"
run 1 >/dev/null
ck "G1 고아까지 걷혀 «(없음)» 은 제목 아래 한 줄뿐" "1" "$(grep -c '^(없음)$' "$TMP/f.md")"

echo "── H. ★제목 아래의 «항목이 아닌» 메모 줄은 지우지 말고 살려 옮긴다 (옛 판은 조용히 지우고 «손실 0» 을 찍었다)"
: > "$TMP/f.md"; rm -f "$TMP/a.md"
printf '# 머리\n\n> 규약 한 줄\n\n## 지금 살아 있는 것 — 아직 안 고쳐진 줄\n(없음)\n※ 수거 카드 메모 — 지우면 안 되는 줄\n\n## 최근에 끝난 것 (최신 1줄)\n2026-09-09 닫힘하나 [닫힘:구기록]\n' > "$TMP/f.md"
run 1 >/dev/null
ck "H1 메모 줄이 파일에 남는다" "1" "$(grep -c '수거 카드 메모' "$TMP/f.md")"
ck "H2 옮겼다고 알린다" "yes" "$(grep -q '옮겼다' "$TMP/last.out" && echo yes || echo no)"

echo "────────  $OK OK / $FAIL FAIL"
[ "$FAIL" = 0 ] || exit 1
