#!/usr/bin/env bash
# 승인 실행(사용자 1회) — 게이트 ▶ → 파이프라인 종결초록 → 머지 → main 종결초록
# 사용: bash approve.sh <repo경로> <MR번호>
# ★환경변수 SKIP_MAIN_WAIT=1 이면 **머지까지만 하고 돌려준다** — main 파이프라인 초록 대기를 건너뛴다.
#   왜: 머지되는 순간 사람의 일은 끝났는데, 그 뒤 main 검사를 기다리느라 오너가 8분을 더 붙잡혔다
#   (2026-09-07 실측: bnsone 승인 22분 중 main 대기가 8분 · 오너 「너무 느린데」). 확인 자체는
#   포기하지 말고 **호출한 쪽이 뒤에서 지켜보다 빨간불일 때만 알린다.**
# ★수정(2026-08-12): 게이트 잡은 앞 단계가 끝나야 manual 이 된다 — 시작 시 한 번만 찾으면 놓친다.
#   대기 루프가 '게이트대기'를 만나면 그 자리에서 눌러야 진행된다(옛 스크립트는 이 분기가 없어 15분을 헛기다렸다).
# ★수정2(2026-08-12 저녁): MR 파이프라인 ID 를 시작 시 한 번만 잡으면, 그 사이 새 커밋이 push 되면
#   (셀프승인 라벨 반영용 빈 커밋이 대표적) 옛 파이프라인의 종결초록을 보고 머지를 시도해 405 가 난다.
#   → 대기 루프가 매 회 MR head 파이프라인을 재조회하고, 바뀌었으면 그쪽으로 갈아탄다(파일럿 !156 실측).
set -u
REPO="${1:?repo 경로}"; MR="${2:?MR 번호}"
cd "$REPO" || exit 1

head_pipe() { # MR 의 현재 head 파이프라인 ID (없으면 빈 문자열)
  glab api "projects/:id/merge_requests/$1" </dev/null 2>/dev/null \
    | python3 -c "import json,sys;p=(json.load(sys.stdin).get('head_pipeline') or {});print(p.get('id') or '')" 2>/dev/null
}

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

wait_verdict() { # $1=파이프라인ID $2=라벨 [$3=MR번호 → 매 회 head 재조회] → 종결초록이면 0
  local pid="$1" label="$2" mr="${3:-}" v="" retried="" played=0 np=""
  for i in $(seq 1 45); do
    if [ -n "$mr" ]; then
      np=$(head_pipe "$mr")
      if [ -n "$np" ] && [ "$np" != "$pid" ]; then
        echo "  ↻ 새 파이프라인 감지($pid → $np) — 그쪽을 기다린다"
        pid="$np"; retried=""; played=0
      fi
    fi
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

PIPE=$(head_pipe "$MR")
# ★빈 커밋 push 직후엔 head_pipeline 이 잠깐 null 이다 — 최대 6회(1분) 재시도 (8-14 실측: 즉시 exit 1 로 죽음)
for i in 1 2 3 4 5 6; do [ -n "$PIPE" ] && break; sleep 10; PIPE=$(head_pipe "$MR"); done
[ -z "$PIPE" ] && { echo "⛔ MR 파이프라인 조회 실패(1분 재시도 후)"; exit 1; }
echo "MR !$MR 파이프라인: $PIPE"
echo "── 게이트 즉시 실행 시도(이미 manual 이면)"; play_gates "$PIPE"
echo "── MR 파이프라인 완료 대기(게이트 뜨면 그때 실행 · head 바뀌면 갈아탐)"
wait_verdict "$PIPE" "MR" "$MR" || exit 1

echo "── 머지"
MERGED=""
for i in 1 2; do
  OUT=$(glab api --method PUT "projects/:id/merge_requests/$MR/merge" -f should_remove_source_branch=true </dev/null 2>&1)
  printf '%s' "$OUT" | grep -q '"state":"merged"' && { MERGED=1; echo "  머지됨"; break; }
  echo "  머지 재시도 대기: $(printf '%s' "$OUT" | head -c 120)"; sleep 15
  NP=$(head_pipe "$MR")
  if [ -n "$NP" ] && [ "$NP" != "$PIPE" ]; then
    echo "  ↻ 머지 사이에 새 파이프라인($NP) — 다시 기다린다"
    PIPE="$NP"; wait_verdict "$PIPE" "MR" "$MR" || exit 1
  fi
done
# 405 Method Not Allowed 의 대표 원인 = head 커밋의 파이프라인이 아직 안 끝났다(위에서 갈아탐).
[ -z "$MERGED" ] && { echo "⛔ 머지 실패 — head 파이프라인 $(head_pipe "$MR") 상태를 웹에서 확인"; exit 1; }

if [ "${SKIP_MAIN_WAIT:-}" = "1" ]; then
  echo "── main 파이프라인 대기 건너뜀(SKIP_MAIN_WAIT=1) — 호출한 쪽이 뒤에서 확인한다"; exit 0
fi
echo "── main 파이프라인 판정"; sleep 10
MPIPE=$(glab api "projects/:id/pipelines?ref=main&per_page=1" </dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['id'])" 2>/dev/null)
[ -z "$MPIPE" ] && { echo "⛔ main 파이프라인 조회 실패 — glab ci status 로 확인"; exit 1; }
echo "main 파이프라인: $MPIPE"
wait_verdict "$MPIPE" "main" || exit 1
echo "✅ 완료 — main 종결초록."
