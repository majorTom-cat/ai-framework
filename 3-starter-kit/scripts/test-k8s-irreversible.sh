#!/usr/bin/env bash
# `scripts/ci-job-k8s-irreversible.sh` 자기시험. CI `self-tests` 가 자동으로 줍는다.
# 지켜야 할 것: 지우는 명령(delete·--prune·replace --force·helm uninstall)은 CI·scripts·k8s·deploy 어디에 있어도 1,
#   apply·rollout restart·주석 속 낱말은 0 — 주석까지 잡으면 이 검사를 설명하는 줄이 매번 걸려 아무도 안 믿는다.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
TARGET="$(pwd)/scripts/ci-job-k8s-irreversible.sh"
[ -f "$TARGET" ] || { echo "⛔ 대상이 없다: $TARGET"; exit 1; }

OK=0; FAIL=0
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

# case <설명> <기대종료코드> <파일경로(루트 기준)> <내용>
case_() {
  local R="$T/r$((OK+FAIL))"
  mkdir -p "$R/$(dirname "$3")" || exit 1
  printf '%s\n' "$4" > "$R/$3"
  OUT=$(K8S_SCAN_ROOT="$R" bash "$TARGET" 2>&1); RC=$?
  if [ "$RC" = "$2" ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); echo "  ⛔ FAIL: $1 (종료 $RC, 기대 $2)"; printf '%s\n' "$OUT"; fi
}

echo "── 대조군: 지우지 않는 명령은 통과"
case_ 'apply 만'                0 .gitlab-ci.yml '    - kubectl -n "$NAMESPACE" apply -f k8s/app.yaml'
case_ 'rollout restart'         0 .gitlab-ci.yml '    - kubectl -n "$NAMESPACE" rollout restart deployment/app'
case_ '줄 머리 주석의 delete'   0 .gitlab-ci.yml '    # kubectl delete pvc data — 하지 마라'
case_ '줄 끝 주석의 --prune'    0 scripts/deploy.sh 'kubectl apply -f k8s/ # --prune 은 안 쓴다'
case_ '빈 저장소'               0 README.md 'x'

echo "── 지우는 명령은 막는다"
case_ 'CI 의 kubectl delete'    1 .gitlab-ci.yml '    - kubectl -n "$NAMESPACE" delete pvc data'
case_ 'apply --prune'           1 .gitlab-ci.yml '    - kubectl apply --prune -l app=x -f k8s/'
case_ 'replace --force'         1 scripts/deploy.sh 'kubectl replace --force -f k8s/postgres.yaml'
case_ 'helm uninstall'          1 deploy/run.sh 'helm uninstall bnsone'
case_ 'k8s 폴더 안 스크립트'     1 k8s/reset.sh 'kubectl delete ns review'
case_ '줄 끝 delete'            1 scripts/x.sh 'kubectl -n ns delete'

echo "── 관리 도구 예외(ALLOW_SCRIPTS)는 «scripts/ 바로 아래 그 이름»만 건너뛴다"
grep -qx 'ALLOW_SCRIPTS=""' "$TARGET" && OK=$((OK+1)) || { FAIL=$((FAIL+1)); echo "  ⛔ FAIL: 킷 원본의 ALLOW_SCRIPTS 가 비어 있지 않다(예외는 배포처 현지화 몫)"; }
# 예외 목록을 채운 사본으로 돌린다 — 환경변수로 열지 않는 이유: CI 변수 하나로 검사 전체를 끌 수 있게 된다.
cp "$TARGET" "$T/allow.sh" || exit 1
sed -i.bak 's/^ALLOW_SCRIPTS=""$/ALLOW_SCRIPTS="reset.sh tool.py"/' "$T/allow.sh" || exit 1
grep -qx 'ALLOW_SCRIPTS="reset.sh tool.py"' "$T/allow.sh" || { echo "⛔ 사본에 예외 목록을 못 넣었다 — 판정 불능"; exit 1; }
TARGET="$T/allow.sh"
case_ '예외 이름(scripts/ 바로 아래)'   0 scripts/reset.sh 'kubectl delete pvc data'
case_ '예외 이름 둘째(.py)'             0 scripts/tool.py 'kubectl -n ci delete pod x'
case_ '같은 이름이라도 하위 폴더면 막음' 1 scripts/sub/reset.sh 'kubectl delete pvc data'
case_ '같은 이름이라도 k8s/ 면 막음'     1 k8s/reset.sh 'kubectl delete pvc data'
case_ '목록에 없는 이름은 막음'          1 scripts/reset2.sh 'kubectl delete pvc data'
case_ '예외가 있어도 CI 의 delete 는 막음' 1 .gitlab-ci.yml '    - kubectl delete pvc data'

echo "────────  $OK OK / $FAIL FAIL"
[ "$FAIL" -eq 0 ]
