#!/usr/bin/env bash
# 승인 실행(사용자 1회) — 게이트 ▶ → 파이프라인 종결초록 → 머지 → main 종결초록
# 사용: bash approve.sh <repo경로> <MR번호>
# ★수정(2026-08-12): 게이트 잡은 앞 단계가 끝나야 manual 이 된다 — 시작 시 한 번만 찾으면 놓친다.
#   대기 루프가 '게이트대기'를 만나면 그 자리에서 눌러야 진행된다(옛 스크립트는 이 분기가 없어 15분을 헛기다렸다).
set -u
REPO="${1:?repo 경로}"; MR="${2:?MR 번호}"
cd "$REPO" || exit 1

play_gates() { # 현재 manual 잡 전부 ▶ (없으면 조용)
  local pid="$1" n=0
  while read -r jid jname; do
    [ -z "${jid:-}" ] && continue
    echo "    ▶ $jname"
    glab api --method POST "projects/:id/jobs/$jid/play" </dev/null >/dev/null 2>&1 \
      && n=$((n+1)) || echo "      ⚠️ play 실패($jname) — 웹에서 확인"
  done < <(glab api "projects/:id/pipelines/$pid/jobs?per_page=100" </dev/null | python3 -c "
import json,sys
for j in json.load(sys.stdin):
    if j['status']=='manual': print(str(j['id'])+' '+j['name'])
" 2>/dev/null)
  return 0
}

wait_verdict() { # $1=파이프라인ID $2=라벨 → 종결초록이면 0
  local pid="$1" label="$2" v="" retried="" played=0
  for i in $(seq 1 45); do
    v=$(node scripts/pipeline-verdict.cjs "$pid" </dev/null 2>/dev/null | head -1)
    echo "  [$label $i] ${v:-조회실패}"
    case "$v" in
      종결초록) return 0;;
      게이트대기)
        if [ "$played" -lt 3 ]; then played=$((played+1)); echo "  게이트 발견 — 실행"; play_gates "$pid"
        else echo "  ⛔ 게이트를 3회 눌렀는데도 대기 — 중단(웹에서 확인)"; return 1; fi;;
      실패)
        if [ -z "$retried" ]; then
          retried=1; echo "  실패 잡 1회 재시도"
          glab api "projects/:id/pipelines/$pid/jobs?scope[]=failed&per_page=100" </dev/null | python3 -c "
import json,sys
for j in json.load(sys.stdin):
    if not j.get('allow_failure'): print(str(j['id'])+' '+j['name'])
" 2>/dev/null | while read -r jid jname; do echo "    재시도: $jname"; glab api --method POST "projects/:id/jobs/$jid/retry" </dev/null >/dev/null 2>&1; done
        else echo "  ⛔ 재시도 후에도 실패 — 중단(수동 확인)"; return 1; fi;;
    esac
    sleep 20
  done
  echo "  ⛔ 15분 내 미완료(마지막: ${v:-없음}) — 중단"; return 1
}

PIPE=$(glab api "projects/:id/merge_requests/$MR" </dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)['head_pipeline']['id'])" 2>/dev/null)
[ -z "$PIPE" ] && { echo "⛔ MR 파이프라인 조회 실패"; exit 1; }
echo "MR !$MR 파이프라인: $PIPE"
echo "── 게이트 즉시 실행 시도(이미 manual 이면)"; play_gates "$PIPE"
echo "── MR 파이프라인 완료 대기(게이트 뜨면 그때 실행)"
wait_verdict "$PIPE" "MR" || exit 1

echo "── 머지"
MERGED=""
for i in 1 2; do
  OUT=$(glab api --method PUT "projects/:id/merge_requests/$MR/merge" -f should_remove_source_branch=true </dev/null 2>&1)
  printf '%s' "$OUT" | grep -q '"state":"merged"' && { MERGED=1; echo "  머지됨"; break; }
  echo "  머지 재시도 대기: $(printf '%s' "$OUT" | head -c 120)"; sleep 15
done
[ -z "$MERGED" ] && { echo "⛔ 머지 실패 — 웹에서 확인"; exit 1; }

echo "── main 파이프라인 판정"; sleep 10
MPIPE=$(glab api "projects/:id/pipelines?ref=main&per_page=1" </dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['id'])" 2>/dev/null)
[ -z "$MPIPE" ] && { echo "⛔ main 파이프라인 조회 실패 — glab ci status 로 확인"; exit 1; }
echo "main 파이프라인: $MPIPE"
wait_verdict "$MPIPE" "main" || exit 1
echo "✅ 완료 — main 종결초록."
