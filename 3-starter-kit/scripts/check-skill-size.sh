#!/usr/bin/env bash
# 스킬 크기 검사 — 컴팩션 뒤 «안 읽히게 되는 부분»을 보여준다.
#
# 왜 있나: 공식 동작은 «컴팩션 시 각 스킬의 **앞 5,000토큰만 남기고 뒤를 자른다**»이다
#   (2026-09-07 공식 재확인: "keeping the first 5,000 tokens of each" · 재부착 전체 합산 25,000토큰,
#   최근 호출 순이라 스킬을 많이 부르면 오래된 것은 통째로 빠진다).
#   넘는 스킬은 대화가 길어지면 **뒤쪽 절이 통째로 안 읽힌다** — 조용히, 아무 신호 없이.
#   기준은 있었는데 **재는 도구가 없어서** 2026-09-07 에 바이트(`wc -c`)로 재고 「기준의 두 배」라
#   오판했다(한글 1자 = 3바이트). 그래서 «재는 법»을 스크립트로 박는다.
#
# ★단위 함정 — 문자 수를 세는 법은 둘뿐이다(alpine busybox 실측 2026-09-07, 같은 파일):
#     wc -m                                  → 9,232  ✅ 문자
#     awk '{n+=length($0)+1}'                → 18,328 ❌ **바이트다**
#     awk 로 연속바이트(\200-\277) 지우고 length → 9,232  ✅ 문자  ← 줄별 누적에 쓴다
#   `wc -c` 도 당연히 바이트. **awk length 를 문자 수로 쓰지 마라.**
# ★한국어 1자 ≈ 0.93토큰(2026-09-07 실측: 13,003자 = 12,072토큰) → 5,000토큰 ≈ 5,376자.
#
# 경고형이다(exit 0). 여러 스킬이 이미 넘고 있고 당장 못 맞추기 때문 — 대신 **무엇이 안 읽히는지**를
# 찍어서 «읽을 값이 있는 경고»로 만든다. 넘는 스킬의 처방은 둘:
#   ① 뒤쪽 절을 보조 파일로 빼고 ② **보조 파일 안내를 맨 앞에** 둔다(뒤에 두면 포인터째로 잘린다).
set -u
LIMIT="${SKILL_CHAR_LIMIT:-5376}"     # 5,000토큰 ÷ 0.93토큰/자
# ★SKILL_ROOT 로 검사 대상 폴더를 덮을 수 있다 — 자기테스트가 격리 폴더에서 돌리기 위함이다.
ROOT="${SKILL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 0
[ -d .claude/skills ] || { echo "스킬 폴더 없음 — 건너뜀"; exit 0; }

OVER=0
for f in .claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  name=$(basename "$(dirname "$f")")
  LC_ALL=C awk -v lim="$LIMIT" -v nm="$name" '
    function chars(s) { gsub(/[\200-\277]/, "", s); return length(s) }
    { c += chars($0) + 1
      if (substr($0,1,3) == "## ") { if (c < lim) last=$0; else if (lost=="") lost=$0 }
      if (c < lim && $0 ~ /\.md`/) { s=$0
        while (match(s, /[^ `"(]+\.md/)) { a[substr(s, RSTART, RLENGTH)]=1; s=substr(s, RSTART+RLENGTH) } }
      # ★앞쪽에 «잘려도 지킬 것» 보강이 있나 — 보조 파일로 못 빼는 스킬의 차선책이다.
      #   이걸 안 보면 «고쳤는데 같은 경고»가 계속 떠서 결국 안 읽히게 된다.
      if (c < lim && $0 ~ /잘려도/) guard=1
    }
    END {
      if (c <= lim) exit 0
      printf "⚠️ /%s — %d자 (한도 %d자 ≈ 5,000토큰). 뒤 %d자가 컴팩션 뒤 안 읽힌다.\n", nm, c, lim, c-lim
      if (last != "") printf "     살아남는 마지막 절 : %s\n", last
      if (lost != "") printf "     ⛔여기부터 안 읽힘 : %s\n", lost
      n=0; s=""
      for (k in a) { n++; s = s (s==""?"":" ") k }
      if (n > 0) printf "     앞쪽 보조파일 안내  : %s\n", s
      if (guard) print "     ✅앞쪽에 «잘려도 지킬 것» 보강 있음 — 차선책은 돼 있다(줄이는 게 정답인 것은 그대로)."
      else if (n == 0) print "     ⛔앞쪽에 아무 대비가 없다 — 잘리면 «무엇을 지켜야 하는지»도 «어디를 읽어야 하는지»도 안 남는다."
      else print "     ⚠️앞쪽에 «잘려도 지킬 것» 보강은 없다 — 보조 파일로 못 빼는 부분이 있으면 한 줄 넣어라."
      exit 9
    }' "$f"
  [ "$?" = 9 ] && OVER=$((OVER+1))
done

if [ "$OVER" = 0 ]; then
  echo "스킬 크기 OK — 전부 ${LIMIT}자 이내"
else
  echo "— 넘는 스킬 ${OVER}개. 처방: ①뒤쪽 절을 보조 파일로 ②그 안내를 **맨 앞에**(뒤에 두면 포인터째 잘린다)"
fi
exit 0
