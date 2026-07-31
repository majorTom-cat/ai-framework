# STEP 진행 지도 — <프로젝트이름>

> 각 STEP의 상태·요약을 한 줄로. **전체 상황은 여기만 보면 된다** — `docs/` 전체를 열지 말 것.
> 읽기 규칙: `.claude/rules/docs.md` "STEP별 분석" — 작업 세트 = 지금 STEP 원본 + 필요한 digest들, 세부는 근거링크로 그 절만 grep. **원본을 뭉텅이로 다 읽지 않기**가 핵심(그 외엔 필요한 만큼).

| STEP | 이름 | 상태 | 요약(digest) |
| --- | --- | --- | --- |
| 0 | Project Initialization (Charter) | ⏳ 대기 | — |
| 1 | Current State Analysis (현황 분석) | ⏳ 대기 | — |
| 2 | Problem Definition (문제 정의) | ⏳ 대기 | — |
| 3 | Requirement Definition (요구사항 정의) | ⏳ 대기 | — |
| 4 | Business Design (업무 설계) | ⏳ 대기 | — |
| 5 | UI/UX Design | ⏳ 대기 | — |
| 6 | Technical Design (기술 설계) | ⏳ 대기 | — (공통 개발자+개발팀) |
| 7 | Development (개발) | 카드 단위 반복 | 보드가 현황판 — `/module`(모듈 신설)→`/dev`·`/fix`(구현)→`/done`(머지). 문서 아닌 **카드가 추적** |
| 8 | Test (테스트) | 카드마다 | `/dev` 6단계 테스트 green(코드 층) + `/inspect`(화면 층) + CI test·boundaries 게이트 |
| 9 | Deploy (배포) | main 머지마다 자동 | CI deploy → 검수서버 — `/done`이 배포·화면 확인까지 안내 |
| 10 | Operation (운영) | 상시 | `/metrics`·`/log` 주간 루틴 + 장애 대응(공통 개발자 가이드 §운영) |

> ※ 프레임워크 원판의 STEP 11(회고, 선택)은 이 표에서 뺐다 — 주 1회 `/metrics` 회고 루틴이 그 역할을 대신한다(의도된 생략).

> **상태 어휘**: `⏳ 대기` / `🔄 진행` / `✅ 확정`.
> 새 STEP 문서가 오면: `/docs`로 해당 폴더에 배치 → `_digest.md` 작성 → 이 표의 상태·링크 갱신 (같은 커밋에서).
> (이 파일은 킷 템플릿이다 — `<프로젝트이름>`을 실제 이름으로 바꾸고, 없앴다면 `/docs`가 이 양식으로 다시 만든다.)
