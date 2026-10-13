#!/usr/bin/env bash
# check-kit-sync.sh 의 회귀 테스트.
# ★이 파일의 존재 이유 = C 케이스다: «프레임워크 밖 커밋(docs·CLAUDE.md)은 세지 않는다».
#   그걸 놓치면 킷에 마찰 한 줄만 적어도 매번 «안 간 커밋 있음»이 떠서, 곧 아무도 안 본다.
#   그래서 맨 아래에서 **경로 거르기를 뗀 돌연변이**로 C 를 다시 돌려 «그때는 FAIL 이 난다»를 증명한다.
# ★그리고 «판정 불능»(exit 2)과 «부채 있음»(exit 1)을 가른다 — 조회 실패를 «깨끗»으로 읽지 않기 위해서다(rules/verify.md §1).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/check-kit-sync.sh"
TMP="$(mktemp -d)" || { echo "⛔ 임시 폴더를 못 만들었다(울타리?) — 저장소에 픽스처를 떨어뜨리지 않으려고 멈춘다"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
OK=0; FAIL=0

command -v git >/dev/null 2>&1 || {
  echo "⛔ git 이 없다 — 이 시험은 git 이력을 만들어 돌린다. «도구가 없어서 안 돌았다»를 초록으로 넘기지 않는다."; exit 1; }

G() { git -c user.email=t@t -c user.name=t -C "$1" "${@:2}"; }   # 신원 없는 환경에서도 커밋된다

ck() { # $1=설명 $2=기대 $3=실제
  if [ "$2" = "$3" ]; then OK=$((OK+1)); echo "  OK  $1"
  else
    FAIL=$((FAIL+1)); echo "  ⛔ $1"; echo "     기대: $2"; echo "     실제: $3"
    [ -s "$TMP/last.out" ] && { echo "     도구 출력:"; sed 's/^/       /' "$TMP/last.out" | head -5; }
  fi
}

# ── 픽스처: 킷 저장소(3-starter-kit 가 한 칸 아래) + 배포처 클론
KIT="$TMP/kit"
mkdir -p "$KIT/3-starter-kit/scripts" "$KIT/3-starter-kit/.claude/rules" "$KIT/3-starter-kit/docs" || exit 1
cp "$TOOL" "$KIT/3-starter-kit/scripts/check-kit-sync.sh" || exit 1
G "$KIT" init -q . 2>/dev/null || { cd "$KIT" && git init -q; }
echo "규칙 1" > "$KIT/3-starter-kit/.claude/rules/a.md"
echo "마찰 1" > "$KIT/3-starter-kit/docs/friction.md"
G "$KIT" add -A >/dev/null; G "$KIT" commit -qm "기준 커밋"
C1=$(G "$KIT" rev-parse --short HEAD)
echo "규칙 2" >> "$KIT/3-starter-kit/.claude/rules/a.md"
G "$KIT" add -A >/dev/null; G "$KIT" commit -qm "킷: 규칙을 고친다(프레임워크)"
C2=$(G "$KIT" rev-parse --short HEAD)
echo "마찰 2" >> "$KIT/3-starter-kit/docs/friction.md"
G "$KIT" add -A >/dev/null; G "$KIT" commit -qm "킷: 마찰 한 줄(프레임워크 아님)"
C3=$(G "$KIT" rev-parse --short HEAD)

RUN="$KIT/3-starter-kit/scripts/check-kit-sync.sh"
mkdep() { # $1=배포처 이름 $2=커밋 메시지(빈 값이면 킷동기 커밋 없음)
  local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d" || return 1
  ( cd "$d" && git init -q ) || return 1
  echo x > "$d/f.txt"; G "$d" add -A >/dev/null
  G "$d" commit -qm "${2:-일반 작업}"
  printf '%s' "$d"
}
run() { bash "$RUN" "$1" > "$TMP/last.out" 2>&1; echo $?; }
cnt() { grep -oE '안 간 킷 커밋 [0-9]+ 건' "$TMP/last.out" | grep -oE '[0-9]+' | head -1; }

echo "── A. 배포처가 킷 HEAD 까지 받았다 → 안 간 커밋 0"
D=$(mkdep depA "킷동기: $C3 — 최신까지")
ck "A1 종료코드 0" "0" "$(run "$D")"
ck "A2 «없다» 문구" "yes" "$(grep -q '킷 동기 OK' "$TMP/last.out" && echo yes || echo no)"

echo "── B. 기준 커밋까지만 받았다 → 프레임워크 커밋 1건만 센다(마찰 커밋은 안 센다)"
D=$(mkdep depB "킷동기: $C1 — 기준까지")
ck "B1 종료코드 1" "1" "$(run "$D")"
ck "B2 건수 1" "1" "$(cnt)"

echo "── C. ★그 뒤로 «프레임워크 밖» 커밋만 있다 → 0 건(이 시험의 핵심)"
D=$(mkdep depC "킷동기: $C2 — 규칙까지")
ck "C1 종료코드 0" "0" "$(run "$D")"

echo "── D. 배포처에 «킷동기» 커밋이 아예 없다 → 판정 불능(2), «깨끗»(0) 이 아니다"
D=$(mkdep depD "")
ck "D1 종료코드 2" "2" "$(run "$D")"

echo "── E. 킷동기 해시가 이 킷에 없다 → 판정 불능(2)"
D=$(mkdep depE "킷동기: deadbee — 남의 저장소 해시")
ck "E1 종료코드 2" "2" "$(run "$D")"

echo "── F. 배포처 경로가 git 저장소가 아니다 → 판정 불능(2)"
mkdir -p "$TMP/notrepo" || exit 1
ck "F1 종료코드 2" "2" "$(run "$TMP/notrepo")"

echo "── H. ★실물 모양 — 표시가 «머지 커밋 본문»에 있어도 읽는다(제목만 보면 판정 불능이 된다)"
D="$TMP/depH"; rm -rf "$D"; mkdir -p "$D" || exit 1
( cd "$D" && git init -q ) || exit 1
echo x > "$D/f.txt"; G "$D" add -A >/dev/null; G "$D" commit -qm "일반 작업"
G "$D" commit -q --allow-empty -m "Merge branch 'kit/sync' into 'main'" -m "킷동기: $C2 — 규칙까지"
ck "H1 종료코드 0(머지 본문에서 기준점을 읽었다)" "0" "$(run "$D")"
ck "H2 기준점을 제대로 집었다" "yes" "$(grep -q "$C2" "$TMP/last.out" && echo yes || echo no)"

echo "── J. ★킷 전용 도구(이 검사기와 그 시험)만 바뀐 커밋은 «안 간 것»으로 세지 않는다"
cp "$TOOL" "$KIT/3-starter-kit/scripts/check-kit-sync.sh"   # 자기 자신을 고친 셈
echo "# 킷 전용" >> "$KIT/3-starter-kit/scripts/test-check-kit-sync.sh" 2>/dev/null || true
G "$KIT" add -A >/dev/null; G "$KIT" commit -qm "킷: 킷 전용 도구만 고친다"
D=$(mkdep depJ "킷동기: $C3 — 그 앞까지")
ck "J1 종료코드 0(킷 전용 커밋은 안 센다)" "0" "$(run "$D")"

echo "── K. ★배포처는 «작업 폴더»가 아니라 서버(origin/main)를 본다"
D="$TMP/depK"; rm -rf "$D"; mkdir -p "$D" || exit 1
( cd "$D" && git init -q ) || exit 1
echo x > "$D/f.txt"; G "$D" add -A >/dev/null; G "$D" commit -qm "일반"
G "$D" commit -q --allow-empty -m "킷동기: $C1 — 낡은 작업 폴더 상태"
G "$D" branch -f origin/main HEAD 2>/dev/null                     # 서버 쪽이 더 앞서 있다고 가정
G "$D" commit -q --allow-empty -m "킷동기: $C2 — 서버에는 더 갔다"
G "$D" branch -f origin/main HEAD
G "$D" reset -q --hard HEAD~1                                     # 작업 폴더만 한 칸 뒤로
ck "K1 서버 기준이라 프레임워크 커밋 0" "0" "$(run "$D")"
ck "K2 어느 ref 로 쟀는지 말한다" "yes" "$(grep -q '배포처 기준 ref' "$TMP/last.out" && echo yes || echo no)"

echo "── L. ★표시에 해시가 여럿이면 «가장 새» 것이 기준점이다 (한 동기가 킷 커밋 여러 개를 실어 온다)"
# 2026-09-23 실측: MR 제목이 「킷동기: c77f257·a58f9fb」였는데 첫 해시를 집어, 머지 직후인데도 1건이 남았다.
D=$(mkdep depL "킷동기: ${C1}·${C3} — 두 건을 한 MR 로")
ck "L1 종료코드 0(새 쪽 $C3 를 기준으로)" "0" "$(run "$D")"
ck "L2 기준점이 새 해시다" "yes" "$(grep -q "$C3" "$TMP/last.out" && echo yes || echo no)"
D=$(mkdep depL2 "킷동기: ${C3}·${C1} — 순서를 뒤집어도 같다")
ck "L3 적는 순서와 무관하다" "0" "$(run "$D")"

echo "── I. ★최신 표시에 해시가 없으면 그 앞 표시로 거슬러 가되, 그 사실을 말한다"
D="$TMP/depI"; rm -rf "$D"; mkdir -p "$D" || exit 1
( cd "$D" && git init -q ) || exit 1
echo x > "$D/f.txt"; G "$D" add -A >/dev/null; G "$D" commit -qm "일반 작업"
G "$D" commit -q --allow-empty -m "킷동기: $C1 — 기준까지"
G "$D" commit -q --allow-empty -m "킷동기: 본 클론이 main 을 따라가게 (킷 8커밋)"   # 해시 없음
ck "I1 종료코드 1(그 앞 표시로 판정)" "1" "$(run "$D")"
ck "I2 «해시가 없어 거슬렀다»를 알린다" "yes" "$(grep -q '해시가 없어' "$TMP/last.out" && echo yes || echo no)"
ck "I3 판정 불능(2)으로 죽지 않는다" "yes" "$(grep -q '판정 불능' "$TMP/last.out" && echo no || echo yes)"

echo "── M. ★배포처가 킷 커밋을 «순서 뒤섞어» 받았다 — 이미 표시된 새 커밋을 «안 간 것»으로 올리지 않는다"
# 2026-10-12 bnsone 실측: 킷 기록 순서 X1→X2→X3→X4 인데 배포처는 X3, X4 를 먼저 받고 마지막에 X1·X2 를 받았다.
#   마지막 표시(X1·X2)를 기준점으로 잡으니 그 뒤 구간의 X3·X4 가 이미 들어왔는데도 «안 간 커밋 2건».
XS=()
for n in 1 2 3 4; do
  echo "규칙 X$n" >> "$KIT/3-starter-kit/.claude/rules/a.md"
  G "$KIT" add -A >/dev/null; G "$KIT" commit -qm "킷: 순서 시험 X$n"
  XS[$n]=$(G "$KIT" rev-parse --short HEAD)
done
X1=${XS[1]}; X2=${XS[2]}; X3=${XS[3]}; X4=${XS[4]}
mkdep_multi() { # $1=배포처 이름, 나머지=킷동기 커밋 메시지들(오래된 것부터)
  local d="$TMP/$1"; shift; rm -rf "$d"; mkdir -p "$d" || return 1
  ( cd "$d" && git init -q ) || return 1
  echo x > "$d/f.txt"; G "$d" add -A >/dev/null; G "$d" commit -qm "일반 작업"
  local msg; for msg in "$@"; do G "$d" commit -q --allow-empty -m "$msg"; done
  printf '%s' "$d"
}
D=$(mkdep_multi depM "킷동기: $C3 — 기준" "킷동기: $X3 — 새 것 먼저" "킷동기: $X4 — 그다음" "킷동기: ${X1}·${X2} — 옛 것을 나중에")
ck "M1 종료코드 0(이미 받은 X3·X4 를 후보에서 뺀다)" "0" "$(run "$D")"
ck "M2 «이미 표시된 N건은 뺐다»를 알린다" "yes" "$(grep -q '이미 적힌 킷 커밋 2건' "$TMP/last.out" && echo yes || echo no)"
D=$(mkdep_multi depM2 "킷동기: $C3 — 기준" "킷동기: $X3 — 새 것 먼저" "킷동기: ${X1}·${X2} — 옛 것을 나중에")
ck "M3 ★표시에 없는 X4 는 여전히 센다(종료 1)" "1" "$(run "$D")"
ck "M4 건수 1" "1" "$(cnt)"
ck "M5 센 것이 X4 다" "yes" "$(grep -q "$X4" "$TMP/last.out" && echo yes || echo no)"

echo "── T. ★임시 파일을 못 만드는 환경(울타리)에서도 «안 간 커밋 있음»을 «OK» 로 바꾸지 않는다"
# 2026-10-13 bnsone 실측: 울타리 안에서 here-document 임시 파일 생성이 막혀 입력이 빈 채로 읽히고 «킷 동기 OK»(0)로 끝났다.
#   ⚠️이 환경에선 재현이 안 된다(bash 가 /tmp 로 물러난다) — 그래서 행동이 아니라 «구조»를 검사한다: 도구 본문에
#   임시 파일을 만드는 입력 방식(heredoc `<<`·here-string `<<<`)이 없어야 한다. 옛 판은 `done <<EOF` 로 T1 이 빨개진다.
ck "T1 heredoc·here-string 입력이 없다(임시 파일 생성 실패를 «대상 없음»으로 못 읽는다)" "0" "$(grep -cE '^[^#]*<<' "$TOOL")"
ck "T2 git log 조회 실패는 판정 불능(2)으로 닫는다" "yes" "$(grep -qE 'RAW=\$\(.*\) *\|\| *\{' "$TOOL" && echo yes || echo no)"

echo "── G. ★잣대 증명 — 경로 거르기를 뗀 돌연변이는 C 에서 FAIL 이 나야 한다"
MUT="$TMP/mutant.sh"
sed 's/ -- "${PATHSPEC\[@\]}"//' "$RUN" > "$MUT" || exit 1
D="$TMP/depC"
bash "$MUT" "$D" > "$TMP/mut.out" 2>&1; MRC=$?
ck "G1 돌연변이는 C 를 통과하지 못한다(0 이 아니다)" "yes" "$([ "$MRC" -ne 0 ] && echo yes || echo no)"
ck "G2 그리고 원판과 달라야 한다" "yes" "$([ "$MRC" != "0" ] && echo yes || echo no)"

echo
echo "결과: OK $OK / FAIL $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
