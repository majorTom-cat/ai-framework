#!/usr/bin/env bash
# /dev·/fix 머리 자동 조회 — `bash scripts/card-head.sh view60|view40|todo|notes|tail <카드번호>`
# 왜 있나: 맥에서 스킬 머리 `!` 조회는 울타리에 막혀 늘 `OSStatus -26276` 이다(rules/gitlab-cli.md). 맥은 조회를 건너뛰고 한 줄만 낸다.
# 그 밖의 OS 는 예전처럼 glab 을 부른다. 분기를 여기서 하는 이유: 머리 `!` 줄에 조건문을 섞으면 스킬 실행이 거부된다.
# 번호가 숫자가 아니면(인자 없이 불렀을 때 포함) «오류» 한 줄 — 스킬 본문의 «오류면 멈춘다»가 걸리게. HEAD_OS 는 시험용 덮어쓰기.
mode="$1"; id="$2"
os="${HEAD_OS:-$(uname -s 2>/dev/null)}"
case "$id" in ''|*[!0-9]*) echo "⚠️ 오류: 카드 번호가 숫자가 아니다 ('$id') — 멈추고 번호를 다시 받아라"; exit 0;; esac
case "$mode" in view60|view40|todo|notes|tail) ;; *) echo "사용법: bash scripts/card-head.sh view60|view40|todo|notes|tail <카드번호>"; exit 0;; esac
if [ "$os" = Darwin ]; then
  echo "(맥: 자동 조회 건너뜀 — 멈추지 말고 AI 가 Bash 로 glab issue view $id 를 직접 조회한다. 빈 카드 아님)"
  exit 0
fi
case "$mode" in
  view60) glab issue view "$id" 2>&1 | sed -n -e '1,60p' -e '61s/.*/⚠️ 잘렸다 — 아래 «남은 항목»을 근거로 삼고, 필요하면 전문을 다시 읽어라/p';;
  view40) glab issue view "$id" 2>&1 | sed -n -e '1,40p' -e '41s/.*/⚠️ 여기서 잘렸다 — 아래 «남은 항목»을 근거로 삼고, 필요하면 전문을 다시 읽어라/p';;
  todo)   glab issue view "$id" 2>&1 | sed -n 's/^ *- \[ \] /□ /p';;
  notes)  glab issue view "$id" --comments 2>&1 | sed -n '/^comments\/notes:/,$p' | tail -40;;
  tail)   glab issue view "$id" --comments 2>&1 | tail -40;;
esac
