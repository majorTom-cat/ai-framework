#!/usr/bin/env bash
# check-push 훅 회귀 테스트 — `bash scripts/test-check-push.sh`
# 왜 있나: 이 훅은 2026-07-30 하루에 네 번 뚫린 이력이 있고(경위 _reference/push-guard.md), 확장할 때마다
#   "예전에 잡히던 게 조용히 안 잡히는" 회귀가 난다. 케이스를 repo에 두어 다음 사람이 재현·재실행하게 한다.
# 규약: 훅은 **ask 아니면 무음**만 낸다(allow·deny·비정상 종료 금지) — 이 스크립트가 그것도 함께 검사한다.
# 인자는 JSON 안에 들어갈 **이스케이프된** 명령 문자열이다(실제 개행은 \n, 따옴표는 \").
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/check-push.sh"
pass=0; fail=0

t() { # $1=ASK|SILENT  $2=기대 사유 조각(ASK일 때, - 면 무시)  $3=명령
  OUT=$(printf '{"tool_input":{"command":"%s"}}' "$3" | bash "$HOOK" 2>/dev/null); RC=$?
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

echo "──────── $pass OK / $fail FAIL"
[ "$fail" -eq 0 ] || exit 1
