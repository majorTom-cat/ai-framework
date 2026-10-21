#!/usr/bin/env bash
# check-friction-dir.py(마찰 폴더 검사기) + check-append-only-git.sh 연결 회귀 테스트 — `bash scripts/test-check-friction-dir.sh`
# 왜 있나: 이 검사기는 «항목 삭제·덮어쓰기·중복·형식 오류»를 막는 차단형이다. 대조군(변경 없음·정상 추가·닫힘·보관 이동)이 먼저 초록이어야
#   뒤의 빨강이 «검사기가 산다»는 증거가 된다(rules/verify.md §5). 병합 시험은 두 브랜치가 각자 추가해 합쳤을 때 충돌 0 을 센다.
# 시험할 검사기를 바꾸려면(유효성 증명용): FRICTION_CHECK=/경로/가짜.py bash scripts/test-check-friction-dir.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="${FRICTION_CHECK:-$HERE/check-friction-dir.py}"
TOOL="$HERE/friction.py"
GITCHK="$HERE/check-append-only-git.sh"
for f in "$CHECK" "$TOOL" "$GITCHK"; do [ -f "$f" ] || { echo "⛔ 없다: $f — 테스트 실패가 아니라 미배포다."; exit 1; }; done
python3 -c 'import sys' >/dev/null 2>&1 || { echo "⛔ python3 이 실행되지 않는다 — 검증 불능(합격 아님)."; exit 1; }
D=$(mktemp -d) || { echo "⛔ 임시폴더를 못 만들었다 — 검증 불능."; exit 1; }
cd "$D" || { echo "⛔ 임시폴더로 못 들어갔다 — 검증 불능."; exit 1; }
git init -q -b main . || { echo "⛔ git init 실패 — 검증 불능."; exit 1; }
git config user.email t@t; git config user.name t
mkdir -p docs/friction scripts
cp "$CHECK" scripts/check-friction-dir.py; cp "$HERE/check-append-only.py" "$HERE/check-append-only-git.sh" scripts/ 2>/dev/null
pass=0; fail=0; skipped=0
ok() { pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }
run() { python3 scripts/check-friction-dir.py "$1" 2>&1; }

L1='2026-10-20 /dev — 첫 마찰 한 줄'
L2='2026-10-21 /done — 둘째 마찰 한 줄'
printf '%s\n' "$L1" > docs/friction/2026-10-20-0-aaaaaa.md
printf '%s\n' "$L2" > docs/friction/2026-10-21-776-bbbbbb.md
LEG1='2026-10-01 /dev — 옛 파일의 첫 줄(앞머리 고침 시험용으로 충분히 긴 문장을 쓴다 abcdefghijklmnopqrstuvwxyz)'
LEG2='2026-10-02 /fix — 옛 파일의 둘째 줄'
printf '%s\n\n%s\n%s\n' '# 마찰 로그' "$LEG1" "$LEG2" > docs/friction.md
printf '%s\n%s\n' '# 보관' '2026-09-01 /dev — 옛 보관 줄 [닫힘:구기록]' > docs/friction-보관.md
git add -A && git commit -q -m base && git branch -q base

# 기대 종료코드와 문구를 확인 — $1=이름 $2=기대코드 $3=문구(없으면 -)
expect() {
  OUT=$(run base); RC=$?
  [ "$RC" = "$2" ] && ok || no "$1: 종료코드 $RC (기대 $2) — $OUT"
  if [ "$3" != - ]; then case "$OUT" in *"$3"*) ok;; *) no "$1: 문구 «$3» 없음 — $OUT";; esac; fi
}
reset() { git checkout -q -f main; git clean -fdq; git reset -q --hard base; }

# ── 대조군: 변경 없음 · 정상 추가 · 닫힘 표시 · 보관 이동은 통과해야 한다
expect "변경 없음" 0 "OK"
printf '%s\n' '2026-10-22 /todo — 새 줄' > docs/friction/2026-10-22-0-cccccc.md
expect "새 파일 추가" 0 "새로 더한 1개"
reset
printf '%s\n' "$L1 [닫힘:#12]" > docs/friction/2026-10-20-0-aaaaaa.md
expect "닫힘 표시 추가" 0 "OK"
reset
mkdir -p docs/friction/보관
printf '%s\n' "$L1 [닫힘:#12]" > docs/friction/보관/2026-10-20-0-aaaaaa.md
rm docs/friction/2026-10-20-0-aaaaaa.md
expect "닫힌 채 보관 이동" 0 "OK"
reset
mkdir -p docs/friction/보관
git mv docs/friction/2026-10-20-0-aaaaaa.md docs/friction/보관/
expect "열린 채 보관 이동도 내용이 같으면 통과(이동 자체는 막지 않는다)" 0 "OK"
reset

# ── 막아야 하는 것: 삭제 · 덮어쓰기 · 중복 · 형식 오류 (각각 «빨강이어야» 한다)
rm docs/friction/2026-10-20-0-aaaaaa.md
expect "삭제" 1 "삭제:"
reset
printf '%s\n' '2026-10-20 /dev — 완전히 다른 내용' > docs/friction/2026-10-20-0-aaaaaa.md
expect "덮어쓰기" 1 "덮어쓰기:"
reset
printf '%s\n' "$L1 뒤에 덧붙임" > docs/friction/2026-10-20-0-aaaaaa.md
expect "닫힘이 아닌 덧붙임" 1 "덮어쓰기:"
reset
printf '%s\n' "$L1 [닫힘:#1] [닫힘:#2]" > docs/friction/2026-10-20-0-aaaaaa.md
expect "닫힘 두 번 붙임" 1 "덮어쓰기:"
reset
printf '%s\n' "$L1 [닫힘:#12]" > docs/friction/2026-10-20-0-aaaaaa.md
git commit -q -am closed; git branch -q -f base
printf '%s\n' "$L1 [닫힘:#99]" > docs/friction/2026-10-20-0-aaaaaa.md
expect "이미 닫힌 줄의 닫힘 값 바꾸기" 1 "덮어쓰기:"
reset
printf '%s\n' '2026-10-22 /todo — 같은 ID' > docs/friction/2026-10-22-0-aaaaaa.md
expect "다른 파일이 같은 6자리" 1 "중복 ID:"
reset
mkdir -p docs/friction/보관
printf '%s\n' "$L1" > docs/friction/보관/2026-10-20-0-aaaaaa.md
expect "같은 파일이 열린 쪽·보관 둘 다" 1 "중복:"
reset
printf '%s\n' '2026-10-22 /todo — 이름 틀림' > docs/friction/메모.md
expect "이름 형식 오류" 1 "형식:"
reset
printf '%s\n%s\n' '2026-10-22 /todo — 첫 줄' '둘째 줄' > docs/friction/2026-10-22-0-dddddd.md
expect "두 줄 파일" 1 "한 줄이어야"
reset
printf '%s\n' '그냥 글' > docs/friction/2026-10-22-0-eeeeee.md
expect "날짜로 안 시작" 1 "날짜"
reset
printf '%s\n' '2026-10-23 /todo — 날짜 다름' > docs/friction/2026-10-22-0-ffffff.md
expect "이름 날짜와 줄 날짜 불일치" 1 "날짜"
reset
printf '\xff\xfe깨진바이트\n' > docs/friction/2026-10-22-0-gggggg.md
expect "utf-8 아님" 1 "utf-8"
reset

# ── 옛 파일(friction.md·friction-보관.md): 새 폴더를 쓰는 repo 에선 «새 줄» 금지, 닫기·옮기기·앞머리 고침은 통과
expect "옛 파일 변경 없음" 0 "OK"
printf '%s\n' '2026-10-22 /todo — 옛 파일 맨 위에 몰래 더한 새 줄' >> docs/friction.md
expect "옛 파일에 새 줄 더함" 1 "옛 파일에 새 줄"
reset
sed -i.bak "s|^\(2026-10-02 /fix — 옛 파일의 둘째 줄\)\$|\1 [닫힘:#5]|" docs/friction.md; rm -f docs/friction.md.bak
expect "옛 파일 줄 닫기" 0 "OK"
reset
sed -i.bak "s|^2026-10-01 /dev — 옛 파일의 첫 줄|2026-10-01 /dev — 요지로 고친 앞머리 — 옛 파일의 첫 줄|" docs/friction.md; rm -f docs/friction.md.bak
expect "옛 파일 줄 앞머리 고침" 0 "OK"
reset
grep -v '둘째 줄' docs/friction.md > docs/friction.md.new; mv docs/friction.md.new docs/friction.md
printf '%s\n' "$LEG2" >> docs/friction-보관.md
expect "옛 파일 줄을 옛 보관으로 옮김" 0 "OK"
reset
printf '%s\n' '2026-10-22 /todo — 옛 보관에 몰래 더한 새 줄' >> docs/friction-보관.md
expect "옛 보관에 새 줄 더함" 1 "옛 파일에 새 줄"
reset
printf '%s\n' "$LEG1" >> docs/friction.md
expect "옛 파일에 같은 줄 중복 더함" 1 "옛 파일에 새 줄"
reset

# ── 월별 보관 폴더(보관/YYYY-MM/): 이동 허용 · 이름이 틀리면 형식 오류 · 삭제는 막음
git branch -q -f pre base      # 이 구획이 base 를 «보관에 파일이 든 판» 으로 옮기므로 끝에서 되돌린다
mkdir -p docs/friction/보관/2026-10
git mv docs/friction/2026-10-20-0-aaaaaa.md docs/friction/보관/2026-10/
expect "월별 보관으로 이동" 0 "OK"
git commit -q -m monthly; git branch -q -f base
rm docs/friction/보관/2026-10/2026-10-20-0-aaaaaa.md
expect "월별 보관의 파일 삭제" 1 "삭제:"
reset
mkdir -p docs/friction/보관/abc
git mv docs/friction/보관/2026-10/2026-10-20-0-aaaaaa.md docs/friction/보관/abc/
expect "월별 폴더 이름이 YYYY-MM 아님" 1 "YYYY-MM"
reset
git mv docs/friction/보관/2026-10/2026-10-20-0-aaaaaa.md docs/friction/
expect "보관에서 보관 밖으로 꺼냄" 1 "보관 밖"
reset
mkdir -p docs/friction/보관
git mv docs/friction/보관/2026-10/2026-10-20-0-aaaaaa.md docs/friction/보관/
expect "월별 → 평평한 보관으로 이동(보관 안 자리 이동)" 0 "OK"
reset
cp docs/friction/보관/2026-10/2026-10-20-0-aaaaaa.md docs/friction/
expect "같은 이름이 열린 쪽·월별 보관에 둘 다" 1 "중복:"
reset
git branch -q -f base pre; reset

# ── 아직 새 폴더를 안 쓰는 repo(기준 tip 에 폴더 없음)에선 옛 파일에 더해도 막지 않는다
git checkout -q -f main; git reset -q --hard base; git clean -fdq
git rm -rq docs/friction; git commit -q -m nofolder2; git branch -q -f nf2
printf '%s\n' '2026-10-22 /todo — 새 방식 도입 전이라 옛 파일에 적는 줄' >> docs/friction.md
OUT=$(python3 scripts/check-friction-dir.py nf2 2>&1); RC=$?
[ "$RC" = 0 ] && ok || no "폴더 도입 전 repo 에서 옛 파일 추가가 막혔다(RC $RC) — $OUT"
git checkout -q -f main; git reset -q --hard base; git clean -fdq

# ── 읽기 실패는 «통과»가 아니라 판정 불능(2)
chmod 000 docs/friction/2026-10-21-776-bbbbbb.md
if [ -r docs/friction/2026-10-21-776-bbbbbb.md ]; then
  echo "· 건너뜀 — 이 환경은 chmod 000 파일도 읽는다(root 등): 읽기 실패 시험 생략"
  skipped=$((skipped+2))  # expect 한 번 = 단언 둘(종료코드·문구) — 건너뛴 만큼 센다
else
  expect "읽을 수 없는 파일" 2 "판정 불능"
fi
chmod 644 docs/friction/2026-10-21-776-bbbbbb.md
reset
OUT=$(python3 scripts/check-friction-dir.py no-such-ref 2>&1); RC=$?
[ "$RC" = 2 ] && ok || no "없는 기준 ref: 종료코드 $RC (기대 2)"

# ── 병합: 두 브랜치가 각자 새 항목을 더해 합치면 충돌 0 이고 양쪽이 다 남는다 (옛 한 파일에선 충돌이 나는 모양)
git checkout -q -f main; git reset -q --hard base; git clean -fdq
git checkout -q -b br-a; python3 "$TOOL" add --card 1 "2026-10-22 /dev — A 가 더한 줄" >/dev/null; git add -A; git commit -q -m a
git checkout -q main; git checkout -q -b br-b; python3 "$TOOL" add --card 2 "2026-10-22 /fix — B 가 더한 줄" >/dev/null; git add -A; git commit -q -m b
git checkout -q br-a
if git merge -q --no-edit br-b >/dev/null 2>&1; then ok; else no "두 브랜치 병합에서 충돌이 났다"; fi
N=$(ls docs/friction | wc -l | tr -d ' ')
[ "$N" = 4 ] && ok || no "병합 뒤 파일이 4개가 아니다: $N"
OUT=$(python3 "$TOOL" list 2>&1)
case "$OUT" in *"A 가 더한 줄"*"B 가 더한 줄"*|*"B 가 더한 줄"*"A 가 더한 줄"*) ok;; *) no "병합 뒤 조회에 양쪽 줄이 없다: $OUT";; esac
[ "$(run base >/dev/null; echo $?)" = 0 ] && ok || no "병합 결과가 검사기를 통과하지 못했다"
# 같은 시험을 옛 한 파일에서 하면 충돌이 난다는 것을 보여 주는 대조(이 시험의 존재 이유)
git checkout -q -f main; git reset -q --hard base; git clean -fdq
printf '%s\n' '# 마찰' '' '## 살아 있는 것' '(없음)' > docs/friction.md; git add -A; git commit -q -m legacy; git branch -q -f lbase
git checkout -q -b la; sed -i.bak 's/^(없음)$/2026-10-22 A 줄/' docs/friction.md; rm -f docs/friction.md.bak; git commit -q -am la
git checkout -q lbase; git checkout -q -b lb; sed -i.bak 's/^(없음)$/2026-10-22 B 줄/' docs/friction.md; rm -f docs/friction.md.bak; git commit -q -am lb
git checkout -q la
if git merge -q --no-edit lb >/dev/null 2>&1; then no "대조: 옛 한 파일은 같은 자리 추가가 충돌해야 하는데 안 났다"; else ok; fi
git merge --abort >/dev/null 2>&1

# ── check-append-only-git.sh 연결: 폴더 삭제가 이 스크립트 종료코드에 반영되고, 폴더가 없는 repo 는 건너뛴다
git checkout -q -f main; git reset -q --hard base; git clean -fdq
cp "$HERE/check-append-only.py" "$HERE/check-append-only-git.sh" scripts/ 2>/dev/null
git add -A; git commit -q --allow-empty -m tools; git branch -q -f base
OUT=$(bash scripts/check-append-only-git.sh base 2>&1); RC=$?
[ "$RC" = 0 ] && ok || no "연결: 변경 없음이 통과해야 한다(RC $RC) — $OUT"
rm docs/friction/2026-10-20-0-aaaaaa.md
OUT=$(bash scripts/check-append-only-git.sh base 2>&1); RC=$?
[ "$RC" = 1 ] && ok || no "연결: 폴더 파일 삭제가 종료코드 1 로 안 막혔다(RC $RC)"
git checkout -q -f main; git reset -q --hard base; git clean -fdq
git rm -rq docs/friction; git commit -q -m nofolder; git branch -q -f nf
OUT=$(bash scripts/check-append-only-git.sh nf 2>&1); RC=$?
case "$OUT" in *"docs/friction/ 가 기준에도 이 트리에도 없음"*) ok;; *) no "연결: 폴더가 없는 repo 에서 건너뜀 안내가 없다: $OUT";; esac

# ── 오래된 브랜치(대상 tip 을 아직 안 품음): 갈라진 뒤 main 이 더한·닫은·보관한 기록을 «삭제·덮어쓰기» 로 세면 안 된다 (bnsone dev 776)
expect_ref() {   # $1=이름 $2=ref $3=기대코드 $4=문구
  OUT=$(run "$2"); RC=$?
  [ "$RC" = "$3" ] && ok || no "$1: 종료코드 $RC (기대 $3) — $OUT"
  if [ "$4" != - ]; then case "$OUT" in *"$4"*) ok;; *) no "$1: 문구 «$4» 없음 — $OUT";; esac; fi
}
git checkout -q -f main; git reset -q --hard base; git clean -fdq
SL='2026-10-20 /dev — 오래된 브랜치 시험용 열린 기록'
printf '%s\n' "$SL" > docs/friction/2026-10-20-0-eeeeee.md
git add docs/friction/2026-10-20-0-eeeeee.md; git commit -q -m "시험 기준"; git branch -q -f sb
git checkout -q -b stale sb
printf '무관\n' > unrelated.txt; git add unrelated.txt; git commit -q -m "무관한 변경"
git checkout -q -b tip1 sb
printf '%s\n' '2026-10-23 /todo — main 이 나중에 더한 줄' > docs/friction/2026-10-23-0-dddddd.md
git add docs/friction/2026-10-23-0-dddddd.md; git commit -q -m "main: 새 기록"
git checkout -q stale
expect_ref "오래된 브랜치 — main 이 새 기록을 더함" tip1 0 "오래된 브랜치"
git checkout -q -b tip2 sb
printf '%s\n' "$SL [닫힘:#12]" > docs/friction/2026-10-20-0-eeeeee.md
git add docs/friction/2026-10-20-0-eeeeee.md; git commit -q -m "main: 닫음"
git checkout -q stale
expect_ref "오래된 브랜치 — main 이 기록을 닫음" tip2 0 "오래된 브랜치"
git checkout -q -b tip3 sb
mkdir -p docs/friction/보관/2026-10
git mv docs/friction/2026-10-20-0-eeeeee.md docs/friction/보관/2026-10/
git commit -q -m "main: 보관 이동"
git checkout -q stale
expect_ref "오래된 브랜치 — main 이 기록을 보관으로 옮김" tip3 0 "오래된 브랜치"
# 막아야 하는 짝: 오래된 브랜치라도 갈라진 시점에 있던 기록을 지우면 막힌다
git rm -q docs/friction/2026-10-20-0-eeeeee.md; git commit -q -m "stale: 삭제"
expect_ref "오래된 브랜치가 갈라진 시점의 기록을 지움" tip1 1 "삭제:"
git reset -q --hard HEAD~1
printf '%s\n' '2026-10-20 /dev — 완전히 다른 내용' > docs/friction/2026-10-20-0-eeeeee.md; git commit -q -am "stale: 덮어씀"
expect_ref "오래된 브랜치가 갈라진 시점의 기록을 덮어씀" tip1 1 "덮어쓰기:"
git reset -q --hard HEAD~1
# 막아야 하는 짝: tip 을 품은 브랜치는 tip 기준 그대로 엄격 — main 의 기록을 버리면 막힌다
git merge -q --no-edit tip1
git rm -q docs/friction/2026-10-23-0-dddddd.md; git commit -q -m "tip 품은 뒤 main 기록 삭제"
expect_ref "tip 을 품은 브랜치가 main 의 기록을 지움" tip1 1 "삭제:"
git checkout -q -f main; git reset -q --hard base; git clean -fdq

cd / && rm -r "$D"
echo "통과 $pass / 실패 $fail / 건너뜀 $skipped"
[ "$fail" -eq 0 ] && [ $((pass + skipped)) -ge 84 ]
