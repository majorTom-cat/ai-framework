#!/usr/bin/env bash
# /todo 머리 자동 조회 — `bash scripts/todo-head.sh issues|todos`
# 왜 있나: 맥에서 스킬 머리 `!` 조회는 울타리에 막혀 늘 `OSStatus -26276` 이다(rules/gitlab-cli.md). 맥은 조회를 건너뛰고
# 한 줄만 낸다(오류 문구가 사용자 화면에 안 뜬다). 그 밖의 OS 는 예전처럼 glab 을 부른다. 분기를 스킬 머리 `!` 줄이 아니라
# 여기서 하는 이유: 머리에 조건문을 섞으면 스킬 실행이 거부된다(CLAUDE.md '스킬 frontmatter `!` 명령').
# HEAD_OS 는 시험용 덮어쓰기(test-todo-head.sh).
os="${HEAD_OS:-$(uname -s 2>/dev/null)}"
case "$1" in
  issues) n=30; set -- glab issue list --assignee=@me;;
  todos)  n=60; set -- glab todo list -P 100;;
  *) echo "사용법: bash scripts/todo-head.sh issues|todos"; exit 0;;
esac
if [ "$os" = Darwin ]; then
  echo "(맥: 자동 조회 건너뜀 — 아래 절차에서 AI 가 Bash 로 한 줄씩 직접 조회한다. 빈 목록 아님)"
  exit 0
fi
"$@" 2>&1 | head -"$n"
