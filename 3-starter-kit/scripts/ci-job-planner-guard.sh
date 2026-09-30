#!/usr/bin/env bash
# 비개발자(기획/디자이너) 직접 push 안전망 — 차단형 (CI 묶음 잡 `repo-guards`)
# 종전 `.gitlab-ci.yml` `planner-guard` 잡의 본문을 그대로 옮겼다.
# CE엔 경로별 push 제한(CODEOWNERS·Push Rules)이 없어 '사후 감지'로 대체한다.
# 공통 개발자가 CI/CD Variables 에 PLANNER_EMAILS(기획/디자이너 이메일, 쉼표구분)를 등록하면 발효.
# 그 계정이 docs/·README 외(코드·CI·설정) 파일을 바꾸면 파이프라인 실패 → 되돌린다.
# 필요: git (GIT_DEPTH: 0 — 얕은 클론이면 push 범위(BEFORE..SHA)의 앞쪽 커밋이 없어 폴백으로 떨어져 감시 범위가 준다)
# `set -eo pipefail` — 러너가 인라인 스크립트에 걸던 설정이다. 파일로 옮기면 따라오지 않아 여기서 건다.
set -eo pipefail
echo "author=$CI_COMMIT_AUTHOR"
if [ -z "$PLANNER_EMAILS" ]; then echo "PLANNER_EMAILS 미설정 — 감지 비활성(무해). 공통 개발자가 등록하면 발효"; exit 0; fi
HIT=0
for e in $(echo "$PLANNER_EMAILS" | tr ',' ' '); do
  case "$CI_COMMIT_AUTHOR" in *"<$e>"*) HIT=1;; esac
done
if [ "$HIT" != "1" ]; then echo "개발자 커밋 — 통과"; exit 0; fi
# ★push 범위 전체를 본다 — 마지막 커밋 하나(git show $CI_COMMIT_SHA)만 보면
#   커밋 2개를 한 번에 push했을 때 앞 커밋의 위반이 그대로 통과한다.
CH=""
ZERO="0000000000000000000000000000000000000000"
if [ -n "${CI_COMMIT_BEFORE_SHA:-}" ] && [ "$CI_COMMIT_BEFORE_SHA" != "$ZERO" ]; then
  CH=$({ git -c core.quotepath=false log --name-only --pretty=format: "$CI_COMMIT_BEFORE_SHA".."$CI_COMMIT_SHA" 2>/dev/null || true; } | sed '/^$/d' | sort -u)
fi
# 폴백 — 새 브랜치 첫 push는 BEFORE_SHA가 0으로 채워진 SHA다(MR 파이프라인도 동일). 그땐 종전대로 마지막 커밋만 본다.
if [ -z "$CH" ]; then
  CH=$(git -c core.quotepath=false show --name-only --pretty=format: "$CI_COMMIT_SHA" | sed '/^$/d')
fi
echo "변경 파일:"; echo "$CH"
BAD=$(echo "$CH" | grep -vE '^(docs/|README)' || true)
if [ -n "$BAD" ]; then
  echo "⛔ 기획/디자이너 계정이 docs/·README 외 파일을 변경했습니다:"; echo "$BAD"
  echo "코드·CI·배포설정은 개발자만 변경합니다. 이 커밋을 되돌리세요(공통 개발자 문의)."
  exit 1
fi
echo "docs/ 내 변경만 — OK"
