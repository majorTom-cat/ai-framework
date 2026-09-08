#!/usr/bin/env bash
# check-push 훅 회귀 테스트 — `bash scripts/test-check-push.sh`
# 왜 있나: 이 훅은 2026-07-30 하루에 네 번 뚫린 이력이 있고(경위 _reference/push-guard.md), 확장할 때마다
#   "예전에 잡히던 게 조용히 안 잡히는" 회귀가 난다. 케이스를 repo에 두어 다음 사람이 재현·재실행하게 한다.
# 규약: 훅은 **ask 아니면 무음**만 낸다(allow·deny·비정상 종료 금지) — 이 스크립트가 그것도 함께 검사한다.
# 인자는 JSON 안에 들어갈 **이스케이프된** 명령 문자열이다(실제 개행은 \n, 따옴표는 \").
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/check-push.sh"
# ★훅 파일 자체가 없으면 전 케이스가 exit 127 로 무더기 FAIL 이 된다 — "검사가 깨졌다"로 오독된다.
#   미배포는 테스트 실패가 아니라 배포 문제다. 그렇게 말하고 끝낸다.
[ -f "$HOOK" ] || { echo "⛔ 훅이 없다: $HOOK"; echo "   이 저장소엔 check-push 훅이 아직 배포되지 않았다 — 테스트 실패가 아니라 미배포다."; echo "   킷의 .claude/hooks/check-push.sh 를 이 저장소에 복사한 뒤 다시 돌려라."; exit 1; }
pass=0; fail=0

# ★케이스는 **격리 저장소**에서 돌린다 — 훅의 공통영역 검사는 «현재 체크아웃의 origin/main...HEAD» 를 보므로,
#   이 저장소에서 그냥 돌리면 «공통 영역을 건드린 브랜치»에서만 SILENT 기대 케이스가 무더기로 깨진다
#   (파일럿 2026-08-26 실측: 같은 스크립트가 main에서 47/47, 동기 브랜치에서 42/47).
# ★git 이 없으면 훅의 공통영역 검사가 통째로 무음이 되어 «의존 명령 부재 = 초록»이 된다 — 통과로 세지 않는다
#   (CI 이미지에 git 이 없어 초록으로 보이던 실측이 있다).
command -v git >/dev/null 2>&1 || { echo "⛔ git 이 없다 — 이 회귀 테스트(공통영역 감지)는 git 이 있어야 성립한다"; exit 1; }
TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT
mkfixture() { # $1=저장소 이름  $2=work 브랜치에서 바꿀 파일 경로
  R="$TMPROOT/$1"; mkdir -p "$R"; ( cd "$R"
    git init -q -b main . && git config user.email t@example.com && git config user.name t
    git config core.hooksPath "$R/.nohooks"
    echo base > README.md && git add -A && git commit -qm base
    git update-ref refs/remotes/origin/main "$(git rev-parse main)"
    git checkout -qb work
    mkdir -p "$(dirname "$2")" && echo changed > "$2" && git add -A && git commit -qm change ) >/dev/null 2>&1
  printf '%s' "$R"
}
CLEAN=$(mkfixture clean src/modules/sample/x.ts)     # 공통 영역 아님 → 조용해야 한다
# ★**양성 케이스를 한 종류로 두지 마라** — bnsone 은 양성이 `.gitlab-ci.yml` 하나뿐이라 **인증 코어 9경로가 훅에서
#   통째로 빠져 있는데도 51케이스가 전부 초록**이었다(2026-09-04 실측). 공통 영역의 «갈래마다» 하나씩 둔다.
COMMON=$(mkfixture common .gitlab-ci.yml)            # 공통 영역(CI 설정) → ask 를 내야 한다
CHECKER=$(mkfixture checker scripts/check-density.sh)  # 검사기 자신 → ask (게이트를 느슨하게 하는 변경도 알린다)
SHARED=$(mkfixture shared src/shared/db.ts)          # 공용 코드 → ask
REPO="$CLEAN"

t() { # $1=ASK|SILENT  $2=기대 사유 조각(ASK일 때, - 면 무시)  $3=명령   ※$REPO 저장소에서 실행
  OUT=$(cd "$REPO" && printf '{"tool_input":{"command":"%s"}}' "$3" | bash "$HOOK" 2>/dev/null); RC=$?
  if [ "$RC" -ne 0 ]; then echo "FAIL(exit $RC): $3"; fail=$((fail+1)); return; fi
  case "$OUT" in *'"permissionDecision":"allow"'*|*'"permissionDecision":"deny"'*)
    echo "FAIL(철칙 위반 — ask 아님): $3"; fail=$((fail+1)); return;; esac
  if [ "$1" = SILENT ]; then
    [ -z "$OUT" ] && { pass=$((pass+1)); return; }
    echo "FAIL(뜨면 안 되는데 뜸): $3 → $OUT"; fail=$((fail+1)); return
  fi
  if printf '%s' "$OUT" | grep -q "$2"; then pass=$((pass+1)); else
    echo "FAIL(안 뜸/딴 판정 — 기대 '$2'): $3 → ${OUT:-무음}"; fail=$((fail+1)); fi
}

echo "── A. 훅 우회 감지 (--no-verify)"
t ASK '훅 우회' 'git commit --no-verify -m \"x\"'
t ASK '훅 우회' 'git commit -m \"fix: 한글 메시지\" --no-verify'        # 인용 인자 뒤 플래그
t ASK '훅 우회' 'git commit -m \"a;b\" --no-verify'                     # 인용문 안 구분자(I-3)
t ASK '훅 우회' 'git commit -m \"a|b\" --no-verify'
t ASK '훅 우회' 'git commit -m \"$(cat <<EOF\nfeat: x\nEOF\n)\" --no-verify'  # heredoc(I-1)
t ASK '훅 우회' 'git commit --no-verify;'                               # 종결자(I-1)
t ASK '훅 우회' '(git commit --no-verify)'                              # 서브셸
t ASK '훅 우회' 'if true; then git commit --no-verify; fi'              # 제어문
t ASK '훅 우회' 'HUSKY=0 git commit --no-verify'                        # 환경변수 접두(I-2)
t ASK '훅 우회' 'GIT_DIR=.git git commit --no-verify'
t ASK '훅 우회' 'sh -c \"git commit --no-verify\"'                      # 따옴표 경계
t ASK '훅 우회' 'git status && git push --no-verify'                    # 체이닝
t ASK '훅 우회' 'git add .\ngit push --no-verify'                       # 여러 줄
t ASK '훅 우회' 'git merge feature --no-verify'

echo "── B. 훅 무력화 (core.hooksPath · HUSKY=0)"
t ASK '무력화' 'git -c core.hooksPath=/dev/null commit -m \"y\"'
t ASK '무력화' 'git config core.hooksPath /tmp/nohooks'
t ASK '무력화' 'git config --global core.hooksPath /tmp/x'
t ASK '무력화' 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x'
t ASK '무력화' 'HUSKY=0 git commit -m \"x\"'
t ASK '무력화' 'env HUSKY=0 git commit -m \"x\"'

echo "── C. commit -n (push -n 과 구분)"
t ASK 'commit -n' 'git commit -n -m \"x\"'
t ASK 'commit -n' 'git commit -anm \"x\"'
t ASK 'commit -n' 'git commit -m \"fix\" -n'
t ASK 'commit -n' 'git -C /tmp/r commit -n -m \"x\"'

echo "── D. 오탐 회귀 — 조용해야 한다"
t SILENT - 'git commit -am \"x\"'
t SILENT - 'git commit --amend -m \"x\"'
t SILENT - 'git push -n origin main'                                    # push -n = dry-run(무해)
t SILENT - 'git push origin feature/commit-fix -n'                      # 브랜치명에 commit(M-3)
t SILENT - 'git log --grep=commit -n 20'
t SILENT - 'git commit -m \"release: v1.2 -next\"'                      # -next 는 -n 클러스터 아님
t SILENT - 'git push origin feature/a'
t SILENT - 'git status'
t SILENT - 'npm test'
t SILENT - 'git clean -n'
t SILENT - 'git add -n .'

echo "── E. 뒤 JSON 필드 누수 (M-2)"
OUT=$(printf '{"tool_input":{"command":"git status"},"description":"--no-verify 게이트 확인"}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass=$((pass+1)) || { echo "FAIL(description 누수): $OUT"; fail=$((fail+1)); }
OUT=$(printf '{"tool_input":{"command":"git diff --stat"},"description":"commit -n 3 확인"}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass=$((pass+1)) || { echo "FAIL(description 누수2): $OUT"; fail=$((fail+1)); }

echo "── F. 기존 게이트 회귀 (force·refspec) + 우선순위(I-4)"
t ASK 'force push' 'git push -f'
t ASK 'force push' 'git status && git push --force'
t ASK 'force push' 'git -c core.pager=x push --force-with-lease'
t ASK '+refspec' 'git push origin +HEAD:main'
t ASK 'force push' 'git commit --no-verify -m x && git push -f origin HEAD'   # ★force 문구가 우선
t ASK '+refspec' 'git commit -n -m x && git push origin +HEAD:main'
t SILENT - 'git push --follow-tags origin main'
t SILENT - 'git push --set-upstream origin feature/a'

echo "── G. 이상 입력 (fail-silent 확인)"
OUT=$(printf '' | bash "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(빈 입력)"; fail=$((fail+1)); }
OUT=$(printf 'not json' | bash "$HOOK" 2>/dev/null); RC=$?
{ [ -z "$OUT" ] && [ "$RC" -eq 0 ]; } && pass=$((pass+1)) || { echo "FAIL(비 JSON)"; fail=$((fail+1)); }

echo "── H. 공통 영역 감지 — 양성·음성 양쪽"
REPO="$COMMON"
t ASK '공통 영역' 'git push origin work'
t ASK '공통 영역' 'git push -n origin work'                 # dry-run 이어도 알린다
t ASK 'force push 감지' 'git push -f origin work'           # force 가 공통영역보다 우선
REPO="$CHECKER"
t ASK '공통 영역' 'git push origin work'                    # 검사기 자신 — 게이트를 느슨하게 하는 변경도 알린다
REPO="$SHARED"
t ASK '공통 영역' 'git push origin work'                    # 공용 코드
REPO="$CLEAN"
t SILENT - 'git push origin work'                           # 공통 영역이 아니면 조용

echo "── I. push 대상이 «지금 폴더»가 아닐 때 (2026-09-09 — 훅이 엉뚱한 저장소를 검사하던 구멍)"
# ★킷 동기는 워크트리에서 `git -C <경로> push` 로 올린다 — 예전 훅은 언제나 현재 폴더만 diff 해서
#   공통영역 저장소를 -C 로 올리면 무음, 깨끗한 저장소를 -C 로 올리면 오탐 ask 였다.
REPO="$CLEAN"
t ASK '공통 영역' "git -C $COMMON push origin work"          # 대상이 공통영역 → 현재 폴더가 깨끗해도 알린다
t ASK '공통 영역' "cd $COMMON && git push origin work"       # cd 형태도 같다
REPO="$COMMON"
t SILENT - "git -C $CLEAN push origin work"                  # 대상이 깨끗 → 현재 폴더가 공통영역이어도 조용(오탐 금지)

echo "──────── $pass OK / $fail FAIL"
[ "$fail" -eq 0 ] || exit 1
