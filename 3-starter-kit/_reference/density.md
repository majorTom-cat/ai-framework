# 밀도 규약 — 왜 CLAUDE.md·스킬을 짧게 유지하나

> 자동 로드 ❌. CLAUDE.md 머리말이 이 파일을 가리킨다. 규칙 자체는 `scripts/check-density.sh`(+ CI `density-check` 잡)가 기계로 강제한다 — 이 문서는 "왜"만.

## 상한
- **CLAUDE.md ≤ 200줄, 줄당 ≤ 300자.**
- **스킬(`SKILL.md`) 줄당 ≤ 500자.**
- 검사: `bash scripts/check-density.sh`. CI는 MR에서 `density-check`(allow_failure=경고)로 초과 줄을 나열한다.

## 왜 줄 수뿐 아니라 "밀도(줄 길이)"인가
긴 줄에 규칙이 묻혀 세션이 못 보고 지나친다 — 2026-07-30 실측: 이 파일 안의 '공통 push 사전 공지'를 세션이 못 보고 무확인 push. compaction 시 CLAUDE.md만 재주입되므로(4-reference 설계) 부풀수록 "재주입돼도 묻힌다".

## 발동 규율 (add 1 = remove 1)
규칙을 **추가하는 그 순간**(어느 경로로든 — 킷 동기·규칙 수정 포함) **삭제/훅 전환 후보 1건을 함께 제시**한다. 없으면 "없음 — 이유" 명시. 빈칸·나중 미루기 금지: '회고 때 검토'는 그 회고가 없어 발동 안 됐다(실측). `check-density.sh`가 이 규율의 기계적 발동지점이다 — 초과가 쌓이면 매 MR이 그걸 보여준다.

## 초과가 났을 때
규칙은 짧게 남기고 **근거(날짜·경위·수치)는 압축하거나 `_reference/`로** 옮긴다 — 단 실측 예외는 지우지 말고 옮긴다. 자주 위반되는 고비용 규칙은 이 파일에 의존하지 말고 **훅/CI로 기계 강제**하라(예: push 가드 `_reference/push-guard.md`, 이 밀도 검사).

## 다른 AI 도구 혼용 팀
이 내용을 `AGENTS.md`로 옮기고 CLAUDE.md엔 `@AGENTS.md` 한 줄만 둔다(Cursor 등과 공유).
