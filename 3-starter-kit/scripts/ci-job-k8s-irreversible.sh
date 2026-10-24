#!/usr/bin/env bash
# 배포 설정 «되돌릴 수 없는 명령» 감시 — 차단형 (CI 묶음 잡 `repo-guards`)
# ★2026-10-24 오너 결정: `k8s/**` 의 ▶(사람 클릭)를 없앴다. `kubectl apply` 는 지우지 않는다 — 매니페스트에서
#   리소스를 빼도, PVC 를 줄여도 클러스터 쪽은 그대로 남거나 apply 가 실패할 뿐이고, 되돌리는 커밋이 같은 길로
#   다시 적용된다(배포처 bnsone 의 k8s 19개 전수 분류 · #707). 데이터가 사라지는 길은 «지우는 명령»뿐이다.
#   ⇒ 사람 대신 이 검사가 그 명령이 배포 경로(CI·스크립트·매니페스트 폴더)에 들어오는 것을 막는다.
# 잡는 것: kubectl 의 delete · apply --prune · replace --force / helm uninstall·delete (주석 줄·줄 끝 주석은 안 본다)
# 정말 필요하면 이 검사를 고치는 MR 로 — 이 파일은 고위험 경로(`scripts/ci-*.sh`)라 경고 리뷰를 탄다.
# 대상 루트 = $K8S_SCAN_ROOT(자기시험용), 없으면 저장소 루트.
set -eo pipefail
ROOT="${K8S_SCAN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SELF="ci-job-k8s-irreversible.sh"
TEST="test-k8s-irreversible.sh"
# 사람이 서버에서 손으로 돌리는 관리 도구(CI 가 안 부른다)의 이름 — `scripts/` 바로 아래 그 이름만 건너뛴다(공백 구분).
#   예: "reset-review-server.sh clean-ci-pods.py"(배포처 bnsone). CI·배포 잡이 부르는 스크립트는 넣지 마라 — 그게 이 검사가 막는 길이다.
ALLOW_SCRIPTS=""

FILES=()
[ -f "$ROOT/.gitlab-ci.yml" ] && FILES+=("$ROOT/.gitlab-ci.yml")
for d in scripts k8s deploy; do
  [ -d "$ROOT/$d" ] || continue
  while IFS= read -r f; do
    case "$(basename "$f")" in "$SELF"|"$TEST") continue ;; esac
    skip=""
    for a in $ALLOW_SCRIPTS; do [ "$f" = "$ROOT/scripts/$a" ] && skip=1; done
    [ -n "$skip" ] && { echo "ℹ️  관리 도구 예외(ALLOW_SCRIPTS): scripts/$(basename "$f")"; continue; }
    FILES+=("$f")
  done < <(find "$ROOT/$d" -type f)
done

HIT=""
for f in "${FILES[@]}"; do
  # 줄 머리 주석·«공백 뒤 #» 이후를 지운 다음 본다 — 이 검사를 설명하는 주석이 걸리지 않게.
  M=$(sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$f" \
    | grep -anE '(kubectl[^|;&]*([[:space:]]delete([[:space:]]|$)|--prune|replace[^|;&]*--force))|(helm[[:space:]]+(uninstall|delete)([[:space:]]|$))' || true)
  [ -n "$M" ] && HIT="${HIT}${f#$ROOT/}:
${M}
"
done

if [ -n "$HIT" ]; then
  echo "⛔ 배포 경로에 «되돌릴 수 없는 명령»이 있다 — 지운 리소스(PVC 의 데이터 등)는 revert 커밋으로 안 돌아온다:"
  printf '%s' "$HIT"
  echo "   → 지우기 대신 apply 로 끝나게 바꿔라(재기동은 rollout restart). 꼭 지워야 하면 사람이 서버에서 직접 하고, 배포 경로엔 넣지 마라."
  exit 1
fi
echo "되돌릴 수 없는 배포 명령 없음 — OK (검사 파일 ${#FILES[@]}개)"
