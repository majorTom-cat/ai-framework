#!/usr/bin/env bash
# 누적 파일(friction·CHANGELOG 류)의 «사라진 줄» 검사 — 차단형 (CI 묶음 잡 `mr-checks`)
# 종전 `.gitlab-ci.yml` `append-only-check` 잡의 본문을 그대로 옮겼다. 왜 차단형인지는 `mr-checks` 잡 주석에 있다.
# 필요: bash git python3 (GIT_DEPTH: 0 — 얕은 클론이면 대상 브랜치가 없어 «판정 불능»(exit 2)으로 죽는다)
# `set -eo pipefail` — 러너가 인라인 스크립트에 걸던 설정이다. 파일로 옮기면 따라오지 않아 여기서 건다.
set -eo pipefail
git fetch -q origin "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-main}"
# ★검사기 자체가 맞는지 먼저 본다 — self-tests 잡은 `changes: scripts/**` 라 **누적 파일만 고친
#   MR 에서는 안 돈다**. 그 MR 에서 검사기가 깨져 있으면 무음으로 통과한다.
bash scripts/test-check-append-only-git.sh
bash scripts/check-append-only-git.sh "origin/${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-main}"
