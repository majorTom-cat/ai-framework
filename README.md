# ai-framework — AI 협업 개발 프레임워크

> 사람과 AI(Claude Code 등)가 함께 프로젝트를 진행하기 위한 방법론(AI Working Framework)과,
> **소규모 팀(개발 4~5인 + 기획/검수 1인)이 각자 AI 에이전트로 협업 개발하는 실행 설계(Team Dev Mode)**.
> 2026-07 작성 — 협업 방식 설계 논의 + Claude Code 공식 문서 전수 분석 + 외부 스킬 팩·**생태계(내장 명령·플러그인·MCP) 전수 대조** + **협업 시뮬레이션 3회로 검증·보강** (겪은 사례는 별도 문서가 아니라 킷·가이드 본문에 녹여져 있음).

---

## 폴더 구성

```
1-framework/    받은 정본 — 방법론 (STEP 0~11, 모든 프로젝트 공통)
2-team-dev/     Team Dev Mode — 팀 협업 개발의 실행 설계 (설계도)
3-starter-kit/  ★실물 파일 — 새 repo에 통째로 복사 (CLAUDE.md·.claude/·ONBOARDING) — 시뮬 3회 실증됨
4-reference/    참조 자료 — 공식 문서 분석·스킬 팩·생태계 분석 (재조사 대신 이걸 참조)
```

| 파일 | 무엇인가 |
| --- | --- |
| `1-framework/AI_Working_Framework_v1_0.md` | 본편 — STEP 0~11 생명주기, 원칙, 표준, STEP별 실행 정의(부록 A) |
| `1-framework/AI_Working_Framework_Onboarding_1Page.md` | 3분 요약본 (신규 합류자용) |
| `1-framework/AI_Working_Framework_Playbook_SoloMode.md` | 1인 프로젝트용 조정판 |
| `1-framework/AI_Working_Framework_Playbook_ScaleMode.md` | 대규모·다팀용 조정판 |
| `2-team-dev/AI_Working_Framework_Playbook_TeamDevMode.md` | 설계 이력·청사진(당시의 왜) — 모듈 소유·셀프 머지·스키마 자동 전파·검수 흐름·AI 운영 규칙. **현행 규칙 정본은 킷(`3-starter-kit`)의 CLAUDE.md·스킬** |
| `2-team-dev/AI_Working_Framework_Guide_GitLab.md` | 전원/비개발자용 — 카드 등록→개발→검수→완료 클릭 순서 |
| `2-team-dev/AI_Working_Framework_Guide_Leader.md` | 공통 개발자용 — 골격 구축 Day 1~5(프롬프트 포함) + 운영 루틴 |
| `2-team-dev/AI_Working_Framework_Guide_GoldenPath.md` | 공통 개발자용 — 본보기 모듈·생성기·스킬 체계(`/dev` 등) 구축법 (Day 6~) |
| `3-starter-kit/` | ★**실행 파일 실물** — 팀 CLAUDE.md, `.claude/`(권한 settings·rules·팀 스킬 세트·push 훅), ADR 템플릿, 역할별 ONBOARDING 1장. repo 만들면 복사해서 시작 |
| `4-reference/claude-code-docs-analysis.md` | Claude Code 공식 문서 34페이지 전수 분석(2026-07-10 기준) — **새 방법론·설계 검토 시 재분석 대신 이걸 먼저 참조**, 중요 결정만 해당 페이지 재확인 |
| `4-reference/agent-skills-analysis.md` | addyosmani/agent-skills(24종 SDLC 스킬 팩) 전수 분석(2026-07-10 기준) — 스킬 체계를 다듬거나 확장할 때 참조. 차용 후보(anti-rationalization 표·가정 표면화·evals·/ship fan-out)와 도입 금지 항목(메타 라우터 통째 도입) 정리 |
| `4-reference/ecosystem-analysis.md` | **내장 명령·공식 마켓·커뮤니티 플러그인·MCP 전수 대조**(2026-07-10 기준) — "이미 있는 걸 중복 제작 안 했나, 안 쓰는 좋은 게 없나". 결론: 중복 없음, 실질 갭 3개(gitlab MCP·보안 스캔 층·CLAUDE.md 관리)는 P1~P2, Windows bash 훅 함정은 킷에 즉시 반영됨 |
| `4-reference/ecc-skills-sh-analysis.md` | **skills.sh(Vercel 스킬 디렉토리)·ECC(Everything Claude Code ★239k) 전수 분석**(2026-08-11 기준) — ECC clone 전수 열람 + 평판·보안 감사 증거. 판정: 둘 다 통짜 신뢰 불가(랭킹 조작·스캐너 우회·스킬 예산 4배 초과 전부 실증), 차용 후보 12개(Node 훅 채굴·skills CLI 사내 배포·plan-canvas 등)와 배제 목록 정리. **재조사 대신 이걸 참조** |
| `4-reference/team-ai-collab-evidence.md` | **외부 증거 대조**(2026-07-11) — 설계 선택 8개를 실팀 사례·연구(METR·DORA·GitClear·Faros)·프레임워크 실패담과 대조 + 출처 역검증. 판정: 구조 6개 지지·**셀프 머지는 반박우세**(고위험 Ask 레인 권고)·시뮬 검증은 증거부족. 미도입 검증 실천 14개 목록 |
| `4-reference/framework-design-decisions.md` | **프레임워크 설계 결정 로그**(프로젝트 ADR과 별개) — "이거 왜 이렇게 했지 / 추가할까?"를 재논쟁 없이 참조. 현재: DD-01 세팅은 새 스킬 안 만듦(scaffold/start 담당)·DD-02 권한은 커밋으로 배포(AI는 settings.json 못 고침)·DD-03 검증은 파일럿 실역할계정으로(bnsone 전)·함정(PowerShell 5.1 UTF-8 등). 프레임워크 결정 시 여기 추가·대체 |
| `4-reference/sian-hub-setup.md` | **화면 시안 허브** 세팅(공통 개발자 1회) — git-sync 정적 서버로 비개발자가 화면 시안(HTML 후보)을 브라우저에서 보고 고르게. 매니페스트·배포토큰·인증서·트러블슈팅 |
| `4-reference/sian-scenarios.md` | 시안 허브·채택의 **예상 시나리오·자주 있는 상황**(체크박스 중복·결정 번복·git-sync 지연·인증서·"허브≠완성 앱" 등) |

## 누가 무엇을 읽나

| 역할 | 꼭 읽을 것 |
| --- | --- |
| 📘 기획/검수 (비개발자) | GitLab 실전 가이드 하나 (10분) |
| 👩‍💻 개발자 | TeamDevMode 2절(전체 그림) + GitLab 가이드 3절 — 나머지 규칙은 CLAUDE.md가 AI에 자동 적용 |
| 🛡️ 공통 개발자 | TeamDevMode 전체 + 공통 개발자 실전 가이드 |

## Team Dev Mode 한 줄 요약

**"기능 하나 = 폴더 하나 = 사람 하나(화면+API+DB 통째 소유), 머지는 CI가 허락하면 셀프(대다수 사람 승인 없음 ·
고위험 = 경고 레인 — AI 경고 리뷰+증적 3종, 셀프 승인 표준·동료 승인 선택), main은 자동 배포되어 검수자가 화면으로 확인, 규칙·절차·안전장치는 repo에 커밋된
파일(CLAUDE.md·rules·skills·훅)이 전원의 AI에게 자동 적용."**

## ⚠️ 이 문서들을 다 읽을 필요 없다 — 구현되면 문서는 은퇴한다

이 문서들은 **설계도**다. 골격·본보기·스킬이 실제로 만들어지면 내용이 repo 안의 *실행되는 파일*로 녹아들고, 그 후엔 읽지 않아도 된다:

| 문서 | 구현되면 이렇게 녹아듦 |
| --- | --- |
| Playbook §3 (구조) | repo 폴더 구조 그 자체 |
| Playbook §5·§6 (관문·스키마) | CI 설정 + 훅 + docker-compose — 기계가 실행 |
| Playbook §8 (AI 규칙) | CLAUDE.md + .claude/rules — AI가 자동으로 읽음 |
| 골든 패스 가이드 | 본보기 모듈 코드 + 생성기 + 스킬 파일 |
| 공통 개발자 가이드 | 공통 개발자가 1회 실행하면 역할 종료 (구축 매뉴얼) |

**끝까지 사람이 읽는 것은 2개뿐**: 이 README(색인)와 GitLab 실전 가이드(비개발자·전원용).
개발자는 문서 대신 — 규칙은 CLAUDE.md가 AI에게 주입, 절차는 `/dev`·`/done`이 안내, 정석은 본보기 모듈을 베낀다.

## 다음 단계

1. 팀 소개: 문서 설명 대신 **파일럿 시연**(카드 등록 → `/done` → 자동 배포) — TeamDevMode 0절 참고
2. 골격 구축: 공통 개발자 가이드 **Day 1부터** (스택·모듈 이름 결정 → 뼈대 → CI/CD → 규칙 → 강제 장치 → 파일럿)
3. 이 폴더를 GitLab에 올려 팀 공유
