#!/usr/bin/env bash
# 머지된 마이그레이션 불변 감시 — 삭제·수정·이름변경이면 실패, 차단형 (CI 묶음 잡 `mr-checks`)
# 종전 `.gitlab-ci.yml` `migration-immutable` 잡의 본문을 그대로 옮겼다. 왜 이 검사가 있는지는 `mr-checks` 잡 주석에 있다.
# 스택 확정 시 아래 `DIR` 을 마이그레이션 실경로로 치환한다(/scaffold). DB 없는 스택이면 diff 0건 = 항상 통과(무해).
# 필요: git (GIT_DEPTH: 0 — 얕은 클론이면 대상 브랜치와의 merge base 가 없어 diff 가 성립하지 않는다)
# `set -eo pipefail` — 러너가 인라인 스크립트에 걸던 설정이다. 파일로 옮기면 따라오지 않아 여기서 건다.
set -eo pipefail
# 비교 기준은 MR 의 실제 대상 브랜치 — main 을 박아두면 다른 브랜치로 가는 MR을 엉뚱한 기준과 비교한다
TARGET="${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-main}"
git fetch -q origin "$TARGET" || { echo "⛔ origin/$TARGET fetch 실패 — 비교 기준이 없어 판정 불가"; exit 1; }
BASE=$(git merge-base HEAD "origin/$TARGET") || BASE=""
# ★기준을 못 구하면 조용히 통과하지 않고 소리를 낸다 — 통과시키면 안전망이 필요한 순간에만 꺼진다
if [ -z "$BASE" ]; then echo "⛔ merge base 를 못 구했다(GIT_DEPTH: 0 확인) — 판정 불가라 실패시킨다"; exit 1; fi
DIR="db/migrations"               # 스택 마이그레이션 경로로 치환 (Prisma 폴더형이면 prisma/schema/migrations)
# ★필터에 R(이름변경)을 반드시 포함한다 — 폴더명만 바꾸면 git 은 삭제로 보지 않고 R 로 기록해
#   DM 만 볼 때 이름 변경이 100% 새어 나갔다(사본 실측). 마이그레이션은 이름이 곧 순번이다.
HIT=$(git diff --diff-filter=DMR --name-only "$BASE" HEAD -- "$DIR" || true)
if [ -n "$HIT" ]; then
  echo "⛔ 머지된 마이그레이션을 삭제·수정·이름변경했습니다 (CLAUDE.md '스키마·데이터' — 머지된 파일은 불변):"
  echo "$HIT"
  echo "   → 되돌리려면: git revert -m 1 --no-commit <머지커밋> 후"
  echo "     git checkout <머지커밋> -- $DIR/<되돌릴대상> 로 파일을 되살리고,"
  echo "     역DDL(DROP ... IF EXISTS 등 멱등)을 담은 새 마이그레이션을 추가하세요(_reference/revert.md B)."
  echo "   → 신규 추가(A)만 있으면 이 잡은 통과합니다. 마이그레이션 MR 은 고위험 = 경고 레인(AI 경고 리뷰 + 증적 3종)."
  exit 1
fi
ADD=$(git diff --diff-filter=A --name-only "$BASE" HEAD -- "$DIR" || true)
N=$(echo "$ADD" | sed '/^$/d' | wc -l | tr -d ' ')
echo "마이그레이션 삭제·수정·이름변경 없음 — OK (신규 추가 파일 ${N}건)"
