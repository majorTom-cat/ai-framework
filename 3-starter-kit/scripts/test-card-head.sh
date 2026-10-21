#!/usr/bin/env bash
# card-head.sh 회귀 테스트 — `bash scripts/test-card-head.sh`
# 왜 있나: 맥은 «조회 건너뜀», 그 밖은 «옛 머리 줄과 같은 조회»가 갈려야 하고, 번호가 이상하면 «오류» 가 떠야 스킬이 멈춘다.
# 시험할 스크립트를 바꾸려면(유효성 증명용): CARD_HEAD=/경로/가짜.sh bash scripts/test-card-head.sh
set -u
HEAD_SH="${CARD_HEAD:-$(cd "$(dirname "$0")" && pwd)/card-head.sh}"
[ -f "$HEAD_SH" ] || { echo "⛔ 스크립트가 없다: $HEAD_SH — 테스트 실패가 아니라 미배포다."; exit 1; }
D=$(mktemp -d) || { echo "⛔ 임시폴더를 못 만들었다 — 검증 불능."; exit 1; }
cd "$D" || { echo "⛔ 임시폴더로 못 들어갔다 — 검증 불능."; exit 1; }
mkdir bin
# 가짜 glab: 부른 인자를 기록하고 본문 100줄(체크박스 둘 포함)과, --comments 면 notes 구획을 낸다
cat > bin/glab <<'EOF'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
i=0; while [ $i -lt 100 ]; do echo "본문$i"; i=$((i+1)); done
echo "- [ ] 남은일하나"
echo "- [x] 끝난일"
case "$*" in *--comments*) echo "comments/notes:"; echo "댓글A";; esac
EOF
chmod +x bin/glab
export PATH="$D/bin:$PATH" FAKE_LOG="$D/glab.log"
pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }
lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

: > "$FAKE_LOG"
for m in view60 view40 todo notes tail; do
  OUT=$(HEAD_OS=Darwin bash "$HEAD_SH" $m 123)
  case "$OUT" in *"맥: 자동 조회 건너뜀"*"issue view 123"*) ok;; *) no "맥 $m 에 건너뜀 안내가 없다: $OUT";; esac
done
[ ! -s "$FAKE_LOG" ] && ok || no "맥인데 glab 을 불렀다"

OUT=$(HEAD_OS=Linux bash "$HEAD_SH" view60 123)
[ "$(lines "$OUT")" = 61 ] && ok || no "view60 이 60줄+잘림 안내(61줄)가 아니다: $(lines "$OUT")줄"
case "$OUT" in *"⚠️ 잘렸다"*) ok;; *) no "view60 에 잘림 안내가 없다";; esac
OUT=$(HEAD_OS=Linux bash "$HEAD_SH" view40 123)
[ "$(lines "$OUT")" = 41 ] && ok || no "view40 이 41줄이 아니다: $(lines "$OUT")줄"
OUT=$(HEAD_OS=MINGW64_NT bash "$HEAD_SH" todo 123)
[ "$OUT" = "□ 남은일하나" ] && ok || no "todo 가 체크 안 된 줄만 내지 않았다: $OUT"
OUT=$(HEAD_OS=Linux bash "$HEAD_SH" notes 123)
case "$OUT" in "comments/notes:"*"댓글A"*) ok;; *) no "notes 가 comments 구획부터 내지 않았다: $OUT";; esac
OUT=$(HEAD_OS=Linux bash "$HEAD_SH" tail 123)
case "$OUT" in *"댓글A") ok;; *) no "tail 이 끝(댓글)까지 내지 않았다";; esac
[ "$(lines "$OUT")" -le 40 ] && ok || no "tail 이 40줄로 안 잘렸다"
grep -q -- 'issue view 123 --comments' "$FAKE_LOG" && ok || no "댓글 조회에 --comments 가 안 붙었다: $(cat "$FAKE_LOG")"

: > "$FAKE_LOG"
for bad in "" "abc" "12;ls" '$(id)'; do
  OUT=$(HEAD_OS=Linux bash "$HEAD_SH" view60 "$bad")
  case "$OUT" in *"⚠️ 오류: 카드 번호가 숫자가 아니다"*) ok;; *) no "번호 [$bad] 에 오류 안내가 없다: $OUT";; esac
done
OUT=$(HEAD_OS=Darwin bash "$HEAD_SH" view60 "")
case "$OUT" in *"⚠️ 오류"*) ok;; *) no "맥 + 번호 없음에도 오류 안내가 떠야 한다(건너뜀으로 덮이면 안 멈춘다): $OUT";; esac
OUT=$(HEAD_OS=Linux bash "$HEAD_SH" 엉뚱 123)
case "$OUT" in *사용법*) ok;; *) no "모르는 모드에 사용법이 없다";; esac
[ ! -s "$FAKE_LOG" ] && ok || no "이상 입력인데 glab 을 불렀다: $(cat "$FAKE_LOG")"

cd / && rm -r "$D"
echo "통과 $pass / 실패 $fail"
[ "$fail" -eq 0 ] && [ "$pass" -ge 21 ]
