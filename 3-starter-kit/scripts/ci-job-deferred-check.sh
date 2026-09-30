#!/usr/bin/env bash
# «미룬 일»이 카드 번호 없이 문장으로만 남았나 — 차단형 (CI 묶음 잡 `mr-checks`)
# 종전 `.gitlab-ci.yml` `deferred-check` 잡의 본문을 그대로 옮겼다. 이 MR 이 «더한 줄»만 본다.
# 필요: bash git python3 (GIT_DEPTH: 0)
# `set -eo pipefail` — 러너가 인라인 스크립트에 걸던 설정이다. 파일로 옮기면 따라오지 않아 여기서 건다.
set -eo pipefail
git fetch -q origin "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-main}"
# 검사기 자체가 맞는지 먼저 — self-tests 는 scripts/** 변경 MR 에서만 돈다(append-only-check 와 같은 이유)
bash scripts/test-check-deferred.sh
bash scripts/check-deferred.sh "origin/${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-main}"
