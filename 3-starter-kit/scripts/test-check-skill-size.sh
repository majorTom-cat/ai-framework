#!/usr/bin/env bash
# check-skill-size.sh 의 회귀 테스트 — 검사기가 «실제로 잡는지»부터 본다(초록은 근거가 아니다).
# ★C 케이스가 이 파일의 존재 이유다: 2026-09-07 에 사람이 바이트(`wc -c`)로 재서 「기준의 두 배」라
#   오판했다(한글 1자 = 3바이트). 검사기가 같은 실수를 하면 «멀쩡한 스킬»을 초과로 잡는다.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHK="$HERE/check-skill-size.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OK=0; FAIL=0

mkskill() { # $1=이름  $2=본문파일내용(stdin)
  mkdir -p "$TMP/.claude/skills/$1"
  cat > "$TMP/.claude/skills/$1/SKILL.md"
}
run() { SKILL_ROOT="$TMP" bash "$CHK" 2>&1; }
reset() { rm -rf "$TMP/.claude"; }

ck() { # $1=설명  $2=기대문구  $3=출력
  if printf '%s' "$3" | grep -q "$2"; then OK=$((OK+1))
  else FAIL=$((FAIL+1)); echo "  ⛔ $1"; echo "     기대: $2"; echo "     실제: $(printf '%s' "$3" | head -3)"; fi
}
ckno() { # 없어야 한다
  if printf '%s' "$3" | grep -q "$2"; then FAIL=$((FAIL+1)); echo "  ⛔ $1 (있으면 안 되는 것이 나왔다: $2)"
  else OK=$((OK+1)); fi
}

echo "── A. 작은 스킬은 통과한다"
reset; printf '# 작은 스킬\n짧다.\n' | mkskill tiny
ck "A1 통과 메시지" "스킬 크기 OK" "$(run)"

echo "── B. 큰 스킬은 잡는다"
reset; { printf '# 큰 스킬\n'; i=0; while [ $i -lt 400 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmno\n'; i=$((i+1)); done; } | mkskill big
OUT="$(run)"
ck "B1 초과로 잡음" "⚠️ /big" "$OUT"
ck "B2 넘는 개수 보고" "넘는 스킬 1개" "$OUT"

echo "── C. ★바이트로 재면 틀린다 — 한글 5,000자는 15,000바이트지만 한도(5,376자) 이내다"
reset; { printf '# 한글 스킬\n'; i=0; while [ $i -lt 100 ]; do printf '한글로만 채운 줄이다 이 줄은 마흔여덟 글자쯤 되게 맞춘 것이며 바이트로는 세 배가 된다\n'; i=$((i+1)); done; } | mkskill kor
BYTES=$(wc -c < "$TMP/.claude/skills/kor/SKILL.md" | tr -d ' ')
CHARS=$(wc -m < "$TMP/.claude/skills/kor/SKILL.md" | tr -d ' ')
OUT="$(run)"
echo "     (이 파일: ${CHARS}자 / ${BYTES}바이트)"
if [ "$BYTES" -le 5376 ]; then echo "  ⚠️ 케이스가 무의미하다 — 바이트도 한도 이내다(테스트를 키워라)"; FAIL=$((FAIL+1)); fi
if [ "$CHARS" -gt 5376 ]; then echo "  ⚠️ 케이스가 무의미하다 — 문자도 한도 초과다(테스트를 줄여라)"; FAIL=$((FAIL+1)); fi
ckno "C1 문자로 재므로 통과해야 한다" "⚠️ /kor" "$OUT"
ck "C2 통과 메시지" "스킬 크기 OK" "$OUT"

echo "── D. 앞쪽 보조파일 안내를 찾는다"
reset; { printf '# 안내 있는 스킬\n\n> 곁에 `함정.md` 를 둔다.\n'; i=0; while [ $i -lt 400 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmno\n'; i=$((i+1)); done; } | mkskill withaux
ck "D1 안내 목록에 함정.md" "함정.md" "$(run)"

echo "── E. 안내가 없으면 그 사실을 말한다"
reset; { printf '# 안내 없는 스킬\n'; i=0; while [ $i -lt 400 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmno\n'; i=$((i+1)); done; } | mkskill noaux
ck "E1 아무 대비도 없으면 그렇게 말한다" "앞쪽에 아무 대비가 없다" "$(run)"

echo "── E2. ★앞쪽 «잘려도 지킬 것» 보강을 알아본다 (고쳐도 같은 경고면 결국 안 읽힌다)"
reset; { printf '# 보강 있는 스킬\n\n> ★잘려도 이것은 지켜라 — 게이트를 건너뛰지 마라.\n'; i=0; while [ $i -lt 400 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmno\n'; i=$((i+1)); done; } | mkskill guarded
OUT="$(run)"
ck "E2-1 보강을 인식" "«잘려도 지킬 것» 보강 있음" "$OUT"
ckno "E2-2 «대비 없음»으로 잘못 말하지 않는다" "앞쪽에 아무 대비가 없다" "$OUT"

echo "── F. 잘리는 첫 절을 지목한다"
reset; { printf '# 절 있는 스킬\n\n## 앞절\n'; i=0; while [ $i -lt 200 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmno\n'; i=$((i+1)); done; printf '\n## 뒷절\n'; i=0; while [ $i -lt 200 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmno\n'; i=$((i+1)); done; } | mkskill sections
OUT="$(run)"
ck "F1 살아남는 절" "살아남는 마지막 절 : ## 앞절" "$OUT"
ck "F2 잘리는 절" "여기부터 안 읽힘 : ## 뒷절" "$OUT"

echo "── G. 경고형이다(종료 코드 0) — 지금 넘는 스킬이 있어도 파이프라인을 막지 않는다"
reset; { printf '# 큰 스킬\n'; i=0; while [ $i -lt 400 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmno\n'; i=$((i+1)); done; } | mkskill big2
SKILL_ROOT="$TMP" bash "$CHK" >/dev/null 2>&1
if [ "$?" = 0 ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); echo "  ⛔ G1 종료 코드가 0이 아니다"; fi

echo "────────  $OK OK / $FAIL FAIL"
[ "$FAIL" = 0 ] || exit 1
