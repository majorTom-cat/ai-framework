#!/usr/bin/env bash
# done-merge-verdict.cjs 회귀 테스트 — `bash scripts/test-done-merge-verdict.sh` (#610)
# 왜 있나: /done 이 «main 이 움직였는데 그대로 머지해도 되나»·«합친 뒤 리뷰가 아직 유효한가»를 이 판정기 1행으로 믿는다.
#   «합치기»를 «그대로»로 내거나 내 파일이 바뀐 병합을 «리뷰유효»로 내는 회귀가 나도 행동 시험이 없으면 아무도 모른다.
# 방법: 임시 폴더에 진짜 git 저장소를 만들어 갈래마다 main 을 움직인다 — 가짜 없이 판정 논리와 git 을 같이 잰다.
# ★«판정 불능»(exit 2)과 «판정했다»(exit 0)를 가른다 — git 실패를 어느 토큰으로도 위장하지 않는지 본다(rules/verify.md §1).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/done-merge-verdict.cjs"
command -v node >/dev/null 2>&1 || { echo "⛔ node 가 없다 — 검증 불능(합격 아님)."; exit 1; }
command -v git >/dev/null 2>&1 || { echo "⛔ git 이 없다 — 검증 불능(합격 아님)."; exit 1; }
[ -f "$TOOL" ] || { echo "⛔ 판정기가 없다: $TOOL"; exit 1; }
TMP="$(mktemp -d)" || { echo "⛔ 임시 폴더를 못 만들었다(울타리?) — 저장소에 픽스처를 떨어뜨리지 않으려고 멈춘다"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"
OK=0; FAIL=0
G() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

# main 에 기준 파일을 만들고 feat 브랜치로 나간다. 파일 x.md 는 줄이 멀어 두 곳을 따로 고쳐도 글자 충돌이 안 난다.
setup() {
  rm -rf "$R"; mkdir -p "$R" || exit 1
  git -C "$R" init -q -b main || exit 1
  mkdir -p "$R/src/modules/people" "$R/src/modules/approval" "$R/src/shared" "$R/docs/adr" "$R/prisma/schema/migrations/20260101_000000_a"
  printf 'a\n' > "$R/src/modules/people/a.ts"; printf 'b\n' > "$R/src/modules/approval/b.ts"
  printf 's\n' > "$R/src/shared/s.ts"; printf '{}\n' > "$R/package.json"; printf '{}\n' > "$R/package-lock.json"
  printf 'ci\n' > "$R/.gitlab-ci.yml"; printf 'sql\n' > "$R/prisma/schema/migrations/20260101_000000_a/migration.sql"
  printf 'adr1\n' > "$R/docs/adr/0001-a.md"; printf 'adr1b\n' > "$R/docs/adr/0001-b.md";printf 'x\n' > "$R/src/modules/approval/index.ts"
  { echo L1; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo mid$i; done; echo L14; } > "$R/docs/x.md"
  G add -A && G commit -q -m base || exit 1
  G checkout -q -b feat || exit 1
}
# $1=브랜치 $2=파일 $3=내용(전체 덮어쓰기) — 파일을 쓰고 그 브랜치에 커밋
put() { G checkout -q "$1" && mkdir -p "$(dirname "$R/$2")" && printf '%s\n' "$3" > "$R/$2" && G add "$2" && G commit -q -m "$1 $2"; }
sedx() { G checkout -q "$1" && sed "$3" "$R/$2" > "$R/$2.tmp" && mv "$R/$2.tmp" "$R/$2" && G add "$2" && G commit -q -m "$1 edit $2"; }
rmf() { G checkout -q "$1" && G rm -q "$2" && G commit -q -m "$1 rm $2"; }
merge_main() { G checkout -q feat && G merge -q --no-edit main >/dev/null 2>&1; }

# $1=설명 $2=기대 종료코드 $3=기대 1행(- 면 안 봄) $4=있어야 할 줄 조각('' 면 안 봄) $5...=판정기 인자
t() {
  local d="$1" rc="$2" tok="$3" frag="$4"; shift 4
  G checkout -q feat 2>/dev/null
  OUT=$(cd "$R" && node "$TOOL" "$@" 2>&1); RC=$?
  L1=$(printf '%s\n' "$OUT" | head -1)
  if [ "$RC" != "$rc" ]; then echo "  ⛔ $d — 종료코드 기대 $rc 실제 $RC → $OUT"; FAIL=$((FAIL+1)); return; fi
  if [ "$tok" != - ] && [ "$L1" != "$tok" ]; then echo "  ⛔ $d — 1행 기대 '$tok' 실제 '$L1' → $OUT"; FAIL=$((FAIL+1)); return; fi
  if [ -n "$frag" ] && ! printf '%s' "$OUT" | grep -qF -- "$frag"; then echo "  ⛔ $d — '$frag' 줄이 없다 → $OUT"; FAIL=$((FAIL+1)); return; fi
  OK=$((OK+1)); echo "  OK  $d"
}
head_sha() { G rev-parse HEAD; }

echo "── A. main-moved — 안 겹치면 그대로 (통과해야 하는 쪽)"
setup; put feat docs/mine.md m
t 'main 이 안 움직임 → 최신' 0 최신 '' main-moved main
put main docs/other.md o
t '다른 파일·모듈 없음 → 그대로' 0 그대로 '안 겹친다' main-moved main
setup; put feat src/modules/people/a.ts mine; put main src/modules/approval/b.ts theirs
t '다른 모듈 파일 → 그대로' 0 그대로 '' main-moved main
setup; put feat src/modules/people/a.ts mine; put main src/modules/approval/c.ts new
t '모듈 폴더에 새 파일(index 아님)·내 모듈과 다름 → 그대로' 0 그대로 '' main-moved main

setup; put feat docs/adr/0001-a.md changed; put main docs/adr/0001-b.md changed
t '번호가 같은 기존 ADR 을 각자 «수정»만 함(새로 만든 게 아님) → 그대로' 0 그대로 '안 겹친다' main-moved main

echo "── B. main-moved — 겹치거나 위험하면 합치기 (막아야 하는 쪽)"
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; sedx main docs/x.md 's/^L14$/L14theirs/'
t '같은 파일(글자 충돌은 없음) → 합치기' 0 합치기 '같은 파일' main-moved main
setup; put feat prisma/schema/a.prisma mine; put main prisma/schema/migrations/20260102_000000_b/migration.sql sql
t 'main 에 새 마이그레이션 + 나도 prisma/ 를 바꿈 → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat prisma/schema/migrations/20260103_000000_mine/migration.sql sql; put main prisma/schema/migrations/20260102_000000_b/migration.sql sql
t 'main 에 새 마이그레이션 + 나도 새 마이그레이션(순서) → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat db/migrations/20260103_000000_mine.sql sql; put main db/migrations/20260102_000000_b.sql sql
t '킷 일반형 마이그레이션 폴더(db/migrations) 도 위험 경로 → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat src/modules/people/a.ts mine; put main package.json '{"a":1}'
t 'package.json 변경 → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat src/modules/people/a.ts mine; put main package-lock.json '{"a":1}'
t 'package-lock 변경 → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat src/modules/people/a.ts mine; put main src/shared/s.ts changed
t 'shared 변경 → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat src/modules/people/a.ts 'import x from "@/modules/approval";'; put main src/modules/approval/index.ts changed
t '내가 쓰는 모듈의 index.ts 에서 export 줄이 바뀜 → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat src/modules/people/a.ts 'import x from "@/modules/approval";'; rmf main src/modules/approval/index.ts
t '내가 쓰는 모듈의 index.ts 가 지워짐 → 합치기' 0 합치기 '위험 경로' main-moved main
setup; G checkout -q main; put main src/modules/people/index.ts x; merge_main; put feat src/modules/people/a.ts mine; put main src/modules/people/index.ts changed
t '내 모듈의 index.ts 에서 export 줄이 바뀜(상대경로로 쓴다) → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat src/modules/people/a.ts mine; put main .gitlab-ci.yml changed
t 'CI 파일 변경 → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat docs/adr/0002-mine.md m; put main docs/adr/0002-theirs.md t
t 'ADR 번호 겹침 → 합치기' 0 합치기 'ADR 번호 겹침' main-moved main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; sedx main docs/x.md 's/^L1$/L1theirs/'
t '같은 줄 수정(글자 충돌) → 합치기' 0 합치기 '글자 충돌' main-moved main

echo "── B2. main-moved — 내 변경이 문서뿐이면 남의 위험 경로는 사유가 아니다 (#610 후속 · 통과해야 하는 쪽)"
setup; put feat docs/mine.md m; put main prisma/schema/migrations/20260102_000000_b/migration.sql sql
t '문서만 바꿈 + main 새 마이그레이션 → 그대로' 0 그대로 '' main-moved main
setup; put feat docs/mine.md m; put main package.json '{"a":1}'
t '문서만 바꿈 + main package.json → 그대로(참고 줄)' 0 그대로 '문서뿐이라 사유에서 뺐다' main-moved main
setup; put feat docs/mine.md m; put main package-lock.json '{"a":1}'
t '문서만 바꿈 + main package-lock → 그대로' 0 그대로 '' main-moved main
setup; put feat docs/mine.md m; put main src/shared/s.ts changed
t '문서만 바꿈 + main shared → 그대로' 0 그대로 '' main-moved main
setup; put feat docs/mine.md m; put main src/modules/approval/index.ts changed
t '문서만 바꿈 + main 다른 모듈 index → 그대로' 0 그대로 '' main-moved main
setup; put feat docs/mine.md m; put main .gitlab-ci.yml changed
t '문서만 바꿈 + main CI 변경 → 그대로' 0 그대로 '' main-moved main
risk_case() { # $1=설명 $2=기대 1행 $3=내가 바꾼 파일 — main 은 src/shared(위험 경로)를 바꾼다
  setup; put feat "$3" m; put main src/shared/s.ts changed
  t "$1" 0 "$2" '' main-moved main
}
risk_case '루트 README.md 만 바꿈 + main shared → 그대로' 그대로 README.md
risk_case '스킬 문서(.claude/skills/x/SKILL.md)만 바꿈 + main shared → 그대로' 그대로 .claude/skills/x/SKILL.md
risk_case '텍스트 notes.txt 만 바꿈 + main shared → 그대로' 그대로 notes.txt
risk_case 'docs/ 의 그림(png)만 바꿈 + main shared → 그대로' 그대로 docs/a.png
risk_case 'docs/ 의 html 만 바꿈 + main shared → 그대로' 그대로 docs/a.html

echo "── B3. main-moved — 코드로 치는 변경이면 위험 경로가 여전히 사유다 (막아야 하는 쪽)"
risk_case 'scripts/*.ts 를 바꿈 + main shared → 합치기' 합치기 scripts/tool.ts
risk_case 'scripts/*.cjs 를 바꿈(CI 가 직접 돌림) + main shared → 합치기' 합치기 scripts/tool.cjs
risk_case 'scripts/*.sh 를 바꿈 + main shared → 합치기' 합치기 scripts/tool.sh
risk_case 'scripts/*.py 를 바꿈 + main shared → 합치기' 합치기 scripts/tool.py
risk_case '하위 폴더 스크립트 scripts/sub/x.sh → 합치기' 합치기 scripts/sub/x.sh
risk_case '루트 postcss.config.mjs → 합치기' 합치기 postcss.config.mjs
risk_case '루트 tailwind.config.ts → 합치기' 합치기 tailwind.config.ts
risk_case '루트 middleware.ts → 합치기' 합치기 middleware.ts
risk_case '루트 docker-entrypoint.sh → 합치기' 합치기 docker-entrypoint.sh
risk_case '.env.example → 합치기' 합치기 .env.example
risk_case '.claude/hooks/a.cjs → 합치기' 합치기 .claude/hooks/a.cjs
risk_case '.github/x.yml → 합치기' 합치기 .github/x.yml
risk_case 'public/ 의 파일 → 합치기' 합치기 public/logo.svg
risk_case 'k8s/ 의 파일 → 합치기' 합치기 k8s/a.yaml
risk_case 'prisma/ 의 스키마 → 합치기' 합치기 prisma/schema/a.prisma
risk_case 'tsconfig.json → 합치기' 합치기 tsconfig.json
risk_case 'docs/ 안의 json(CI 검사가 읽는다) → 합치기' 합치기 docs/05_UIUX/screen-registry.json
risk_case 'docs/ 안의 yaml → 합치기' 합치기 docs/a.yaml
risk_case 'docs/ 안의 ts → 합치기' 합치기 docs/a.ts
risk_case 'docs/ 안의 cjs → 합치기' 합치기 docs/a.cjs
risk_case 'docs/ 안의 mjs → 합치기' 합치기 docs/a.mjs
risk_case 'docs/ 안의 sh → 합치기' 합치기 docs/a.sh
risk_case 'docs/ 안의 py → 합치기' 합치기 docs/a.py
risk_case 'docs/ 안의 tsx → 합치기' 합치기 docs/a.tsx
setup; put feat test/unit.test.ts m; put main package.json '{"a":1}'
t 'test/ 를 바꿈 + main package.json → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat package.json '{"b":1}'; put main src/shared/s.ts changed
t '내가 package.json 을 바꿈 + main shared → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat .gitlab-ci.yml mine-ci; put main package.json '{"a":1}'
t '내가 CI 파일을 바꿈 + main package.json → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat Dockerfile mine; put main src/shared/s.ts changed
t '내가 Dockerfile 을 바꿈 + main shared → 합치기' 0 합치기 '위험 경로' main-moved main
setup; put feat docs/mine.md m; sedx feat docs/x.md 's/^L1$/L1mine/'; sedx main docs/x.md 's/^L1$/L1theirs/'
t '문서만 바꿔도 글자 충돌이면 여전히 합치기' 0 합치기 '글자 충돌' main-moved main
setup; put feat docs/mine.md m; put main docs/mine.md changed
t '문서만 바꿔도 같은 파일이면 여전히 합치기' 0 합치기 '같은 파일' main-moved main

echo "── B4. main-moved — 내 변경이 실제로 안 쓰는 남의 변경은 사유가 아니다 (#716 · 통과해야 하는 쪽)"
setup; put feat src/modules/people/a.ts mine; put main src/modules/people/c.ts new
t '같은 모듈 다른 파일 → 그대로' 0 그대로 '안 겹친다' main-moved main
setup; put feat src/modules/people/a.ts mine; put main prisma/schema/migrations/20260102_000000_b/migration.sql sql
t 'main 새 마이그레이션·나는 스키마를 안 건드림 → 그대로' 0 그대로 '' main-moved main
setup; put feat src/modules/people/a.ts mine; put main src/modules/approval/index.ts changed
t '내가 안 쓰는 모듈의 index.ts 가 바뀜 → 그대로' 0 그대로 '' main-moved main
setup; put feat src/modules/people/a.ts 'import x from "@/modules/approval-extra";'; put main src/modules/approval/index.ts changed
t '이름이 접두사만 같은 모듈(approval-extra)을 씀 → approval 은 안 쓰는 것 → 그대로' 0 그대로 '' main-moved main
setup; G checkout -q feat; mkdir -p "$R/src/modules/people"
{ echo 'import x from "@/modules/approval";'; head -c 70000000 /dev/zero | tr '\0' a; echo; } > "$R/src/modules/people/big.ts"; G add src/modules/people/big.ts; G commit -q -m big
put main src/modules/approval/index.ts changed
t '내 파일이 너무 커서 못 읽음(버퍼 초과) → 그대로로 위장하지 않고 판정 불능(fail-closed)' 2 - '못 읽었다' main-moved main
setup; put feat src/modules/people/a.ts 'import x from "@/modules/approval";'; put main src/modules/approval/index.ts $'x\nexport y'
t '내가 쓰는 모듈의 index.ts 에 export 만 더해짐 → 그대로' 0 그대로 '' main-moved main
setup; put feat src/modules/people/a.ts mine; put main src/shared/ui/tokens.test.ts t
t 'src/shared 의 시험 파일만 바뀜 → 그대로' 0 그대로 '' main-moved main
echo "── B5. #708 에서 실제로 «합치기» 가 세 바퀴 난 모양 — 완화 후 «그대로»"
setup; put feat src/modules/attendance/a.ts 'import x from "@/modules/people";'
put main src/modules/attendance/b.ts new; put main src/modules/people/index.ts $'a\nexport z'
t '#708 ① 같은 모듈 다른 파일 + 쓰는 모듈 index 에 export 추가 → 그대로' 0 그대로 '' main-moved main
setup; put feat src/modules/attendance/a.ts 'import x from "@/modules/people";'
put main prisma/schema/migrations/20260102_000000_b/migration.sql sql; put main src/modules/approval/index.ts changed; put main src/modules/reservation/index.ts changed
t '#708 ② 새 마이그레이션 + 안 쓰는 모듈 둘의 index → 그대로' 0 그대로 '' main-moved main
setup; put feat src/modules/attendance/a.ts 'import x from "@/modules/people";'
put main src/modules/approval/index.ts changed; put main src/shared/ui/tokens.test.ts t
t '#708 ③ 안 쓰는 모듈의 index + shared 시험 파일 → 그대로' 0 그대로 '' main-moved main

echo "── C. main-moved — 이미 합친 적이 있는 브랜치 (두 번째 이동)"
setup; put feat src/modules/people/a.ts mine; put main docs/o1.md 1; merge_main; put main docs/o2.md 2
t '합친 뒤 main 이 또 움직임·안 겹침 → 그대로' 0 그대로 '1개 파일' main-moved main
put main src/shared/s.ts again
t '합친 뒤 또 움직임·shared → 합치기' 0 합치기 '위험 경로' main-moved main

echo "── D. after-merge — 병합이 main 쪽만 바꿨으면 리뷰 유효"
setup; put feat docs/mine.md m; REV=$(head_sha)
t '병합 없이 HEAD 그대로 → 리뷰유효' 0 리뷰유효 '병합 없음' after-merge "$REV" main
put main docs/other.md o; merge_main
t '깨끗한 병합(main 쪽 파일만) → 리뷰유효' 0 리뷰유효 'main 쪽 파일 1개만' after-merge "$REV" main

echo "── E. after-merge — 내 코드가 바뀌었으면 재리뷰 (막아야 하는 쪽)"
setup; put feat docs/mine.md m; REV=$(head_sha); put main docs/other.md o; merge_main; put feat docs/mine.md changed
t '병합 뒤 내 파일을 다시 고침 → 재리뷰' 0 재리뷰 '내 파일이 바뀜: docs/mine.md' after-merge "$REV" main
setup; put feat docs/mine.md m; REV=$(head_sha); put main docs/other.md o; merge_main; put feat docs/new-fix.md f
t '병합 중 main 도 내 것도 아닌 새 파일을 손댐 → 재리뷰' 0 재리뷰 '손댄 파일: docs/new-fix.md' after-merge "$REV" main
setup; put feat prisma/schema/migrations/20260105_000000_mine/migration.sql sql; REV=$(head_sha)
put main prisma/schema/migrations/20260106_000000_theirs/migration.sql sql; merge_main
rmf feat prisma/schema/migrations/20260105_000000_mine/migration.sql; put feat prisma/schema/migrations/20260107_000000_mine/migration.sql sql
t '내 마이그레이션 재생성(이름 바뀜) → 재리뷰' 0 재리뷰 '20260105_000000_mine' after-merge "$REV" main
setup; put feat docs/mine.md m; REV=$(head_sha); put main docs/other.md o
G checkout -q feat; G merge -q --no-commit --no-ff main >/dev/null 2>&1; printf 'evil\n' >> "$R/docs/other.md"; G add docs/other.md; G commit -q -m evil
t '병합 커밋에서 main 이 바꾼 파일을 손으로 고침(evil merge) → 재리뷰' 0 재리뷰 '손댄 파일: docs/other.md' after-merge "$REV" main
setup; put feat docs/mine.md m; REV=$(head_sha); put main docs/other.md o; merge_main; put feat docs/other.md changed
t '깨끗한 병합 뒤 main 이 바꾼 파일을 직선 커밋으로 고침 → 재리뷰' 0 재리뷰 '손댄 파일: docs/other.md' after-merge "$REV" main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^L14$/L14theirs/'; merge_main
t '같은 파일을 자동 병합·고친 곳이 멀다(1행 vs 14행) → 리뷰유효(#677)' 0 리뷰유효 '4줄 이상 떨어져' after-merge "$REV" main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^L14$/L14theirs/'
G checkout -q feat; G merge -q --no-commit --no-ff main >/dev/null 2>&1; chmod +x "$R/docs/x.md"; G add docs/x.md; G commit -q -m chmod
t '병합 커밋에서 같은 파일의 실행권한(mode)만 바꿈 → 재리뷰(독립 검토가 재현한 구멍)' 0 재리뷰 '기계적 병합과 다름' after-merge "$REV" main
echo "── E3. after-merge — main 의 변경을 통째로 버린 병합은 재리뷰 (옛 판부터 있던 구멍)"
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^L14$/L14theirs/'
G checkout -q feat; G merge -q -s ours --no-edit main >/dev/null 2>&1
t '병합을 -s ours 로 해 main 이 고친 같은 파일 변경이 사라짐 → 재리뷰' 0 재리뷰 'main 의 변경이 버려짐' after-merge "$REV" main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^L1$/L1theirs/'
G checkout -q feat; G merge -q --no-commit --no-ff main >/dev/null 2>&1; G checkout -q --ours docs/x.md; G add docs/x.md; G commit -q -m ours-resolve
t '같은 줄 충돌을 --ours 로 풀어 main 변경이 사라짐 → 재리뷰' 0 재리뷰 'docs/x.md' after-merge "$REV" main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); rmf main docs/x.md
G checkout -q feat; G merge -q -s ours --no-edit main >/dev/null 2>&1
t 'main 이 지운 파일을 내 쪽으로 되살림 → 재리뷰' 0 재리뷰 'docs/x.md' after-merge "$REV" main
echo "── E4. after-merge — 파일 이름에 글롭 글자([id])가 있어도 다른 파일의 줄을 끌어오지 않는다"
BODY=$(echo L1; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo mid$i; done; echo L14)
setup; put main docs/i.md "$BODY"; put main 'docs/[id].md' "$BODY"; merge_main
sedx feat 'docs/[id].md' 's/^L1$/L1mine/'; REV=$(head_sha); sedx main 'docs/[id].md' 's/^L14$/L14theirs/'; sedx main docs/i.md 's/^mid1$/mid1theirs/'; merge_main
t '파일 이름이 [id].md·곁 파일 i.md 의 가까운 줄을 main 이 고침 → 리뷰유효(글롭이 끌어오지 않는다)' 0 리뷰유효 '4줄 이상 떨어져' after-merge "$REV" main
echo "── E2. after-merge — 같은 파일: 가까우면·손댔으면·충돌이면 재리뷰, 4줄 이상 멀고 기계적 병합이면 유효 (경계)"
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^mid3$/mid3theirs/'; merge_main
t '같은 파일·main 이 내 줄(1행)에서 3줄 떨어진 4행을 고침 → 재리뷰(가깝다)' 0 재리뷰 '줄 안' after-merge "$REV" main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^mid4$/mid4theirs/'; merge_main
t '같은 파일·main 이 4줄 떨어진 5행을 고침 → 리뷰유효(경계)' 0 리뷰유효 '4줄 이상 떨어져' after-merge "$REV" main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^L14$/L14theirs/'; merge_main; sedx feat docs/x.md 's/^mid6$/mid6hand/'
t '같은 파일 멀리 병합했지만 그 뒤 직선 커밋으로 손댐 → 재리뷰(기계적 병합과 다름)' 0 재리뷰 '기계적 병합과 다름' after-merge "$REV" main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^L14$/L14theirs/'
G checkout -q feat; G merge -q --no-commit --no-ff main >/dev/null 2>&1; sed 's/^mid6$/mid6evil/' "$R/docs/x.md" > "$R/docs/x.md.tmp"; mv "$R/docs/x.md.tmp" "$R/docs/x.md"; G add docs/x.md; G commit -q -m evil
t '병합 커밋 안에서 같은 파일의 다른 곳을 몰래 고침(evil merge) → 재리뷰' 0 재리뷰 '기계적 병합과 다름' after-merge "$REV" main
setup; sedx feat docs/x.md 's/^L1$/L1mine/'; REV=$(head_sha); sedx main docs/x.md 's/^L1$/L1theirs/'
G checkout -q feat; G merge -q --no-commit --no-ff main >/dev/null 2>&1; { echo L1resolved; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo mid$i; done; echo L14; } > "$R/docs/x.md"; G add docs/x.md; G commit -q -m resolved
t '같은 줄을 둘이 고쳐 손으로 충돌을 해결 → 재리뷰' 0 재리뷰 'docs/x.md' after-merge "$REV" main
setup; put feat docs/mine.md m; REV=$(head_sha); G checkout -q --orphan other >/dev/null 2>&1; G commit -q --allow-empty -m other; G branch -q -f feat other; G checkout -q feat
t '리뷰한 커밋이 조상이 아님(이력 갈아엎음) → 재리뷰' 0 재리뷰 '조상이 아니다' after-merge "$REV" main

echo "── F. 판정 불능은 어느 토큰으로도 위장하지 않는다 (exit 2)"
setup; put feat docs/mine.md m; REV=$(head_sha)
t '없는 main 참조 → 판정 불능' 2 - '판정 불능' main-moved nosuchref
t '인자 없음 → 판정 불능' 2 - '사용:'
t '모르는 모드 → 판정 불능' 2 - '사용:' bogus
t 'SHA 가 40자가 아님(짧은 값) → 판정 불능' 2 - '40자' after-merge "${REV:0:8}" main
t '없는 SHA(형식은 맞음) → 판정 불능' 2 - '판정 불능' after-merge "$(printf 'b%.0s' $(seq 40))" main

echo; echo "결과: 통과 $OK / 실패 $FAIL"
[ "$FAIL" = 0 ] && [ "$OK" -gt 0 ]
