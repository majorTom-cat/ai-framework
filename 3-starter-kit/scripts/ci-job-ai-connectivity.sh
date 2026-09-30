#!/usr/bin/env bash
# AI 리뷰 잡 전제: 사내 러너에서 api.anthropic.com 에 통신되나? (CI 묶음 잡 `mr-warnings` — 경고형)
# 종전 `.gitlab-ci.yml` `ai-connectivity` 잡의 본문을 그대로 옮겼다. 막히면 CI AI리뷰 잡 불가.
# 필요: curl
# `set -eo pipefail` — 러너가 인라인 스크립트에 걸던 설정이다. 파일로 옮기면 따라오지 않아 여기서 건다.
set -eo pipefail
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 -X POST \
  -H "content-type: application/json" -d '{}' \
  https://api.anthropic.com/v1/messages || echo "000")
echo "api.anthropic.com 응답: $CODE  (4xx=통신 성공(인증만 실패) / 000=방화벽 차단)"
case "$CODE" in
  4*) echo "OK — 필요 시 AI 리뷰 잡을 사내 러너에서 돌릴 수 있다";;
  *)  echo "차단 — 러너 아웃바운드 방화벽/프록시 확인 필요";;
esac
