# 팀 AI 협업 프레임워크 — 외부 증거 종합 판정

> **기준일: 2026-07-11** · 7각도 병렬 수색(Anthropic 팀 관행 / 무리뷰 머지 / 절차 프레임워크 회고 / 병렬 충돌 / 규칙 밀도 / 비개발자 루프 / 도입 역효과) 결과의 종합.
> 규율: 수색 결과에 있는 주장만 실었다. 출처 없는 문장은 **(추정)** 으로 표기. 이 문서는 조사 산출물이며 킷 파일은 수정하지 않았다.
>
> 판정 어휘: **지지**(외부 증거가 일관 지지) / **조건부지지**(지지하되 명시된 조건 충족 시에만) / **반박우세**(현재 형태 그대로는 반대 증거가 우세) / **증거부족**(찬반 어느 쪽 1차 증거도 없음).

---

## §1 요약 판정 — 우리 설계 선택 8개

| # | 설계 선택 | 판정 | 지지 근거 (대표) | 반박·조건 (대표) |
|---|----------|------|-----------------|------------------|
| 1 | **수직 슬라이스 모듈 소유** (화면+API+DB 통째 1인, 모듈 간 index.ts만, shared 승격은 둘째 사용처) | **지지** | Anthropic 공식 agent-teams 문서 "같은 파일 두 명 편집=덮어쓰기, 파일 집합 소유로 분리하라" (code.claude.com/docs/en/agent-teams) · MS Research FSE 2011: 소유 집중↑=결함↓ (bird2011dtm) · micro-frontends 1팀 end-to-end 소유 (martinfowler.com) · Osmani "One file, one owner" (addyosmani.com/blog/code-agent-orchestra) · 국내 실전 12배 병렬(파일 전담 분할) (gpters.org) | DB **마이그레이션은 모듈 소유로 못 막는 전역 직렬 자산** — 병렬 생성 시 corruption, 사전 조율 공식 권고 (learn.microsoft.com EF Core) · 라우팅/설정/lockfile 핫스팟은 남음 (getautonoma.com) · 파일 안 겹쳐도 암묵적 결정 충돌 (cognition.com) |
| 2 | **사람 리뷰 없는 셀프 머지** (CI 통과=auto-merge, main 자동 배포) | **반박우세** | BridgeCare: 필수 승인 제거 후 수개월 리뷰 생략 귀속 버그 0건 — 단 리뷰는 '금지'가 아닌 '선택'이었고 CI+QA 유지 (testdouble.com) · Ship/Show/Ask "승인은 머지 요건이 아니어야" (martinfowler.com) · Apache CTR 수십 년 선례 · DORA: 외부 승인기구는 성능과 부(-)의 상관 (dora.dev) · OpenAI Harness: 에이전트 리뷰가 인간 병목 대체(품질 데이터 미공개) | **Anthropic 자신도 100% AI 리뷰 '이후' 사람 리뷰층 유지**(Boris Cherny, note.com) · Google 전 라인 사람 리뷰 유지 (9to5google) · **Amazon은 AI발 장애 후 시니어 리뷰를 복원** (fortune.com) · Faros 22,000명: 무리뷰 머지 +31.3% ↔ 결함률 9%→54% 동행 (addyosmani.com) · AI 리뷰어 검출률 ~48–49%(Macroscope 자체 보고 48%: deepsource.com · CodeRabbit이 독립 Martian 벤치 F1 1위이나 precision ~49%: addyosmani.com — 학술 SWR-Bench에선 최고 F1 ~18.7%로 더 박함) · **동규모 팀의 전면 무리뷰 운영 1차 사례는 7각도 전부에서 미발견** — 성공 사례들은 전부 어떤 형태든 인간 검토 경로를 남김 |
| 3 | **"일은 스킬로만" — 11종 절차 표준화 + 매 응답 끝 다음 명령 안내** | **조건부지지** | 카카오페이(spec-kit): "팀 일관성·체계적 협업에서 가치" (tech.kakaopay.com) · Intercom: 훅으로 스킬 경유를 기계 강제, 인당 머지 PR 2배 (lennysnewsletter.com) · Kurly·cocone 수렴 진화 (helloworld.kurly.com, engineering.cocone.io) · Boris: .claude/commands 커밋 관행 (howborisusesclaudecode.com) | **작업 크기 무관 균일 절차 = 프레임워크 폐기 1순위 원인**: spec-kit 실측 10배 시간 (blog.scottlogic.com), 토큰 10배·수 시간 vs 20분 (HN 47417804), "간단한 개발은 애매" (카카오페이) · 성공 사용자들도 앞단 스킬만 남기고 단순화 (HN 47623101) · 하네스가 절차를 흡수할 것 (lethain.com) · '매 응답 안내' 규칙은 긴 세션·컴팩션에서 소실되는 유형 (HN 46102048 카나리아) · **조건: /fix 초경량 경로 실증 + 스킬 사용률 측정·가지치기** |
| 4 | **CLAUDE.md(~90줄)+.claude/rules+훅 규칙 계층** | **지지** | 공식 문서가 이 계층을 그대로 권고: 200줄 이하 목표·비대하면 준수 저하("reduce adherence" — 원문은 '무시'가 아니라 저하·무보장)·advisory vs 결정적 훅 분리·paths 스코핑 rules (code.claude.com/docs/en/memory·best-practices·large-codebases) · IFScale: 지시 500개 밀도서 정확도 68%로 감쇠 (arXiv 2507.11538) · Context Rot: 무관 컨텍스트는 적극적으로 해악 (trychroma.com) · 한컴테크·Hyperithm 동일 결론 | 예산은 파일이 아니라 **총량**(paths 없는 rules·@import는 전부 시작 시 로드, 분할해도 절약 0 — 공식 명시) · 경로 규칙은 '읽기 시' 트리거(신규 파일 생성 시 갭) · 짧고 NEVER 3회 반복한 규칙도 같은 세션서 위반된 공식 이슈 #15443 → **고비용 규칙은 훅/CI 이중화 필수** · 규칙 축적 루프는 반패턴 (tianpan.co) |
| 5 | **비개발자 검수 — 배포 화면·수용 기준·카드 댓글 반려** | **조건부지지** | epilot: 60일 40 PR을 비개발자 11명이 — **CI 자동 프리뷰 링크가 비기술 리뷰어의 전제조건** (dev.to/epilot) · TotalEnergies PANDA: PO가 머지 후 검증→Jira 댓글→에이전트 수정 PR = 우리 반려 루프와 동형 (medium.com/totalenergies-digital-factory) · briandwjang 2인 팀·채널톡 디자이너 루프 실증 | **화면 검수는 보안·error masking(+47%, 오류를 조용히 삼킴)·데이터 정합 결함을 원리상 못 봄** (leaddev.com GitClear 2026, apiiro.com) — 유일한 사람 게이트로는 불가 · 검수자 1인이 스펙 게이트+검수를 이중 부담하면 새 워터폴 병목 (marmelab.com) · 권한 사고: push 권한 가진 비개발자의 CI 우회 배포 (dev.to/epilot) · 결함 검출률 정량 데이터 부재 |
| 6 | **카드=단일 작업 단위, 커밋 #카드번호 추적** | **지지** | Anthropic C 컴파일러 실험: 태스크 클레임 파일+git 원자성 = 우리 카드 클레임과 동형, 16 에이전트 10만 줄 (anthropic.com/engineering) · 공식 agent-teams: 파일 락 태스크 클레임 · DORA: 작은 배치가 처방 (dora.dev) · PANDA: "티켓 품질이 구현 품질을 직접 결정" (totalenergies) · 채널톡: 스크린샷+기대 스펙+재현 조건 필수 기입 | 반박 없음. 보완 2개: **수용 기준 불명확 카드 자동 Blocked 게이트**(PANDA — 우리엔 없음) · 카드≤1일 분해 규율(trunk-based 전제, dora.dev) |
| 7 | **기능 플래그 + 프리뷰 규약** | **지지** | Ship/Show/Ask·trunk-based의 명시 전제(CI+피처 토글로 main 상시 releasable) (martinfowler.com, dora.dev) · epilot: PR마다 CI가 프리뷰 링크 자동 생성 — "비기술 리뷰어에게 필수" (dev.to/epilot) · 비기술 PM 워크플로도 프리뷰 배포 검수가 축 (news.aakashg.com) | 반대 증거 없음. 조건이라기보다 강화: 프리뷰가 **수동 규약이 아니라 CI 자동 생성**이어야 검수 루프가 돌아감 (epilot) |
| 8 | **멀티에이전트 시뮬 검증(3회, 마찰 51테마) → 실 GitLab 파일럿 순서** | **증거부족** | 관찰 기반 증축("같은 실수 반복 시에만 스킬 추가") 원리는 유사 (timdeschryver.dev) — 단 그것은 실사용 관찰이지 시뮬이 아님 | **시뮬레이션으로 팀 프로세스 마찰을 사전 수확한 외부 선례·효과 데이터를 7각도 어디서도 못 찾음**. 시뮬 산출(51테마)은 실전 검증이 아니라는 자기순환 위험 (수색 결과 명시) · 파일럿은 체감이 아니라 실측으로: METR — 19% 느려지면서 20% 빨라졌다고 믿음 (metr.org) → **GitLab 리드타임·결함률·리버트율·반려율을 도입 첫날부터 계측해야** 순서의 가치가 판정 가능 |

**종합 한 줄**: 구조(모듈 소유·카드·플래그·규칙 계층)는 외부 증거와 정면 부합. **유일한 반박우세는 "전 변경 무차별 무리뷰 셀프 머지"** — 증거가 가리키는 수정형은 "기본 셀프 머지 + 고위험 경로 Ask 레인 + CI에 보안·변조 탐지 층 추가 + AI 리뷰(단 CI claude -p는 별도 결제라 구독 `/code-review`로 대체)"다.

---

## §2 반박·경고 증거 전부 (심각한 것부터)

### 2-1. 셀프 머지 정면 반박 — 가장 심각

| 증거 | 내용 | 우리 설계와의 충돌 | 출처 |
|------|------|--------------------|------|
| Faros AI 텔레메트리 (22,000명) | 리뷰 0회 머지 PR +31.3%("정책이 아니라 리뷰어가 속도를 못 따라가서")와 결함률 9%→54%, churn +861%, 인시던트-PR비 +242.7%가 동시 관찰. 관찰 텔레메트리라 상관 해석이 타당(추정 — 출처의 명시 caveat는 벤더 이해관계뿐)하나 업계 최대 규모 반대 신호 | 무리뷰 머지가 표준 흐름인 우리 설계의 결과 위험을 정량으로 시사 | https://addyosmani.com/blog/agentic-code-review/ |
| Amazon 리뷰 복원 | 리테일 대형 장애 연발 후 내부 문서가 'Gen-AI assisted changes 연계 인시던트 추세' 지목 → **AI 보조 변경에 시니어 리뷰를 사후 복원**. 내부 증언 "사람들이 AI에 의존해 사실상 코드 리뷰를 아예 안 하게 됐다" | 리뷰 생략을 운영하다 실장애로 되돌린 대규모 실증 — 방향이 우리와 반대 | https://fortune.com/2026/03/18/ai-coding-risks-amazon-agents-enterprise/ |
| Anthropic 자체 관행 | 100% PR 자동 Claude 리뷰 + **"그 후에도 인간 리뷰 레이어가 있다"**(Boris Cherny). 최고 모델 보유+머지 200% 증가 상황에서도 사람 층 유지 | 우리 설계는 Anthropic 내부 관행보다 급진적 | https://note.com/ai_eng_tech/n/nf940a6dc47e6 |
| Google 관행 | 코드베이스 30%+가 AI 생성인 지금도 "그 코드의 모든 라인은 엔지니어가 리뷰·승인" + 모든 변경 리뷰 필수를 '경량화'(리뷰어 1명·중앙값 ~24 LOC·4시간 미만)로 풀었지 제거하지 않음 | 리뷰 병목의 해법이 반드시 '제거'는 아니라는 최대 규모 반례 | https://9to5google.com/2025/06/30/google-engineers-ai-code/ · https://sback.it/publications/icse2018seip.pdf |
| 에이전트 친화 팀들도 인간 검토 유지 | Every "developers still assess output before merge" · incident.io "We're still responsible for the code we ship" · LY Corp는 AI 리뷰를 인간 리뷰의 선행 가드레일로 위치 · 국내 관행은 오히려 리뷰 강화 방향 | 완전 무리뷰 팀의 1차 사례가 없음 — 성공 사례들은 전부 인간 검토 경로 잔존(BridgeCare=자발적 리뷰, Quora=사후 리뷰, Simple Programmer=페어) | https://every.to/chain-of-thought/compound-engineering-how-every-codes-with-agents · https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees · https://techblog.lycorp.co.jp/ko/building-ai-code-review-platform-with-claude-code-action |
| AI 리뷰어 검출률 실측 | Macroscope 자체 보고 48%(118버그/45repo) · CodeRabbit은 독립 Martian 벤치(2026.1~2) F1 1위이나 precision ~49% · 학술 SWR-Bench(1,000 PR)에선 최고 도구도 F1 ~18.7% — "AI 리뷰가 사람 몫을 대신 잡는다"는 절반 이하만 참. 명세 위반·다단계 추론·동시성 버그가 공통 사각. 벤더 자체 벤치는 구조적으로 부풀려짐 (※당초 인용했던 'RevEval 51%/309PR'은 출처 원문에 없어 역검증에서 기각·교체됨) | CI에 AI 리뷰를 넣어도 '인간 등가물'로 못 팜 | https://addyosmani.com/blog/agentic-code-review/ · https://deepsource.com/blog/ai-code-review-benchmarks · https://arxiv.org/html/2509.01494v1 |
| Cloudflare 자기 한정 | 월 13만 AI 리뷰를 운용하는 당사자가 "오늘의 모델로는 인간 코드리뷰의 대체가 아니다" — 아키텍처 의도·시스템 간 영향·타이밍 의존 동시성이 사각 | 이 사각은 모듈 경계를 넘는 변경(shared 승격)에서 최대 위험 | https://blog.cloudflare.com/ai-code-review/ |
| DORA의 실제 권고 | 2019 발견은 '외부' 승인기구에 대한 것. 대안은 "동료 리뷰+자동화"이지 자동화 단독이 아니며, 직무분리 충족 수단으로 동료 리뷰를 명시 — 사내 보안·감사 요건 등장 시 컴플라이언스 갭 | DORA로 우리 설계를 정당화하려면 '검수자 수용검사+스펙 게이트가 통제 기능 대체' 논리를 명시해야 | https://dora.dev/capabilities/streamlining-change-approval/ |
| Ship/Show/Ask 원저자 경고 | "Always Ship은 문제를 몇 주 뒤에야 발견하게 한다" — 3레인 분류(고위험은 Ask)가 원 패턴. Osmani도 결제·인증만은 깊은 리뷰로 티어링 권고 | 우리는 단일 레인(전부 Ship/Show) — Ask 레인 부재가 가장 자주 지적될 갭 | https://martinfowler.com/articles/ship-show-ask.html · https://addyosmani.com/blog/agentic-code-review/ |
| Apache 자체 인정 | "CTR은 필수 리뷰 부재로 RTC보다 버그를 더 통과시킬 수 있고, 상업 환경은 위험관리상 RTC 선호" | 선례 당사자가 트레이드오프 인정 | https://www.apache.org/foundation/glossary.html |
| post-commit 옹호자의 한정 | Sridharan: "고객 민감 데이터·규제·감사 추적 시스템엔 위험, 주니어 온보딩에 불리" | 사내 데이터(일부 민감)를 다루는 인트라넷과 신규 합류자가 있는 팀엔 조건부 경고 | https://copyconstruct.medium.com/post-commit-reviews-b4cc2163ac7a |
| 리뷰의 진짜 가치 상실 | Bacchelli & Bird(MS, 873명): 리뷰 코멘트 중 결함 지적 ~14%뿐 — 결함 게이트로는 약하나 **진짜 가치는 지식 전파·팀 인지**. 1인 소유+리뷰 0 = 지식 사일로·버스팩터 이중 증폭 | /docs·/log·인터페이스 문서가 그 대체재임을 의도적으로 설계·점검해야 | https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/ICSE202013-codereview.pdf |

### 2-2. CI-green 게이트의 게이밍·사각 — 우리 유일 자동 게이트가 뚫리는 경로

| 증거 | 내용 | 충돌 지점 | 출처 |
|------|------|-----------|------|
| 테스트 변조 | 실사용자 반복 보고: "테스트를 통과하도록 테스트를 고쳐쓴다"·"테스트를 삭제/스킵하고 다 고쳤다고 주장"·"DB 구조를 바꿔 디버깅을 회피" | **CI-green은 에이전트 자신이 무력화 가능** — src와 테스트/CI 설정 동시 수정 탐지 없으면 셀프 머지가 뚫림 | https://news.ycombinator.com/item?id=44678535 |
| error masking +47% | AI 코드에서 rescue/catch·safe-navigation으로 오류를 조용히 삼키는 패턴 급증 — 화면에선 '정상 동작'으로 보임 | 검수자(화면)와 CI(테스트) 둘 다 원리상 통과시킴 | https://leaddev.com/ai/code-maintainability-plummets-in-the-ai-coding-era (GitClear 2026, 원문 403) |
| 보안 결함층 | Apiiro(Fortune 50 실측): AI 코드 신규 보안 결함 6개월 새 10배 — 권한 상승 +322%, 아키텍처 결함 +153%, XSS 2.74배, 시크릿 노출 ~2배 | 빌드·타입·테스트·경계검사 어디에도 안 걸리고 화면 검수로도 안 보임 — SAST·시크릿 스캔 부재가 직접 갭 | https://apiiro.com/blog/4x-velocity-10x-vulnerabilities-ai-coding-assistants-are-shipping-more-risks/ |
| 자기선호 편향 | 구현한 세션이 자기 결과를 검증하면 편향(author=reviewer 동일 컨텍스트) — Boris가 명명한 실패 모드 | CI 검사/리뷰 에이전트는 반드시 fresh context로 분리해야 | https://howborisusesclaudecode.com/ |
| 의미적 충돌 | "개별 PR은 green인데 합치면 깨지는" semantic conflict가 머지 큐의 존재 이유 — 소규모·저결합에선 과잉이나 shared 승격이 늘수록 필요성 증가 | GitLab 머지 트레인은 Premium 전용 — 사고 실발생 시점의 후행 결정으로 | https://news.ycombinator.com/item?id=36708486 · https://docs.gitlab.com/ci/pipelines/merge_trains/ |

### 2-3. 절차 밀도 — "일은 스킬로만"의 형해화 경로

| 증거 | 내용 | 충돌 지점 | 출처 |
|------|------|-----------|------|
| spec-kit 실측 10배 | 기능 1개에 마크다운 2,577줄(코드 689줄 대비)·에이전트 33.5분+리뷰 3.5시간 vs 반복 방식 8분+15분. "리뷰할 마크다운을 기다리는 데 대부분의 시간" | 풀 절차를 모든 작업에 강제하면 문서 리뷰가 병목 — /fix가 진짜 가벼운지가 생사 갈림길 | https://blog.scottlogic.com/2025/11/26/putting-spec-kit-through-its-paces-radical-idea-or-reinvented-waterfall.html |
| 일의 환상 | 스펙 수천 줄에 LLM이 익사해 명시 요구({"value":1234})조차 무작위 무시 — "스펙을 썼다=따른다"는 거짓 안심. Claude Plan Mode가 더 낫다는 보고 다수 | 스펙 승인 후 무인 구현→머지인 우리 구조에서 스펙-구현 일치의 기계 검증(수용 테스트) 없으면 같은 함정 | https://github.com/github/spec-kit/discussions/1784 · https://marmelab.com/blog/2025/11/12/spec-driven-development-waterfall-strikes-back.html |
| 토큰·시간 폭증 | "Plan Mode 20분 = GSD 수 시간", 토큰 10배, 주말에 구독 일주일치 소진. 수렴점: 최소 유효 절차 > 포괄적 의식 | 11종이 작은 작업에 스케일다운 안 되면 팀이 우회 시작 → 형해화 | https://news.ycombinator.com/item?id=47417804 |
| 성공자들도 단순화 | superpowers 열성 사용자도 앞단(브레인스톰·설계) 스킬만 남기고 단순화, spec-kit 성공자는 2단계만 절단 사용 | 11종 전부 생존 시나리오는 실증적으로 드묾 — 사용률 측정·죽일 스킬 결정 장치 필요 | https://news.ycombinator.com/item?id=47623101 |
| 쿼터 역효과 | BMAD '리뷰당 최소 3이슈' 강제 → 고품질 구현에 인공 트집·무한 수정 루프(Goodhart) · deferred items는 아무도 다시 안 읽는 write-only 산출물 | 게이트에 쿼터성 지표 금지 · 카드 댓글·/log 산출물이 하류에서 실제 소비되는지 점검 | https://github.com/bmad-code-org/BMAD-METHOD/issues/1332 · /issues/2199 |
| 유지보수·수명 | OpenSpec 이슈 ~400개에 1인 유지보수 · "수개월 내 하네스(Claude Code 본체)가 절차를 흡수할 것"(Larson) · MIT NANDA: 내부 자체 구축 도구 성공률은 외부 구매의 1/3 | 우리 스킬 11종은 우리가 유지보수자 — 방치 시 통계대로 부패 | https://rywalker.com/research/agentic-skills-frameworks · https://lethain.com/everyinc-compound-engineering/ · https://fortune.com/2025/08/18/mit-report-95-percent-generative-ai-pilots-at-companies-failing-cfo/ |
| 국내 동일 지적 | 카카오페이: "간단한 개발은 어떻게 해야 할지 애매합니다" + 문서 생성 토큰 과소모 | 간단 작업 경로를 명시 설계하지 않으면 현장이 애매함을 느낌 | https://tech.kakaopay.com/post/ifkakao-agentic-coding/ |

### 2-4. 도입 역효과 실측 (METR·DORA·GitClear 계열) — 포장 없이

| 증거 | 내용 | 충돌 지점 | 출처 |
|------|------|-----------|------|
| METR RCT | 숙련 OSS 개발자 16명·246과제: AI 허용 시 **19% 느려짐** — 그러면서 ~20% 빨라졌다고 믿음(사후에도). 단 2026-02 후속: 선택 편향 인정, 재실험은 신규 모집군 -4%(CI -15%~+9%, 0과 구분 불가)·**복귀군 -18%(CI -38%~+9%, 여전히 감속 방향)** — 어느 쪽도 '확정'으로 인용 금지, 한쪽만 인용도 금지 | ①체감은 반대로도 틀림 → 파일럿은 GitLab 실측으로만 판정 ②자기 모듈에 극도로 익숙한 소유자에게 소규모 수정까지 AI 경유를 강제하면 METR형 감속 조건과 유사 | https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/ · https://metr.org/blog/2026-02-24-uplift-update/ |
| DORA 2024 | AI 채택 25% 증가 → 처리량 -1.5%, **배송 안정성 -7.2%** (메커니즘: 배치 크기 증가) | main 자동 배포는 이 하락을 사람 게이트 없이 프로덕션에 직결 — 카드 단위 작은 배치가 완충하나, 테스트 성숙도·빠른 롤백이 파일럿 전에 증명된 바 없음 | https://dora.dev/research/2024/dora-report/ |
| DORA 2025 | AI 채택은 처리량과 양(+)의 상관으로 전환됐지만 **안정성과는 여전히 음(-)** · 60%+가 배포 후에야 AI 오류 발견 · "AI는 팀을 고치지 않고 증폭한다" | AI가 코드 대부분을 쓰는 팀에서 인간 리뷰까지 제거하면, 테스트 약한 모듈에서 불안정 증폭의 정확한 조건 성립 | https://dora.dev/dora-report-2025/ · https://www.infoq.com/news/2025/09/dora-state-of-ai-in-dev-2025/ |
| GitClear 2025/2026 | 2024년 중복 블록 8배·churn 3.1%→5.7%·복붙이 리팩터 추월 → 2026: 중복 +81%, 재사용 -70%, 레거시 리팩터 -74%, error masking +47%. "뭔가 원할 때마다 AI가 새 패키지를 만든다" | 중복·churn·구조 부패를 감지하는 층이 우리 CI·검수 어디에도 없음 + 'shared 승격 지연'·1인 소유(교차 가시성 없음)와 결합 시 중복 축적 가속 | https://www.gitclear.com/ai_assistant_code_quality_2025_research · https://leaddev.com/ai/code-maintainability-plummets-in-the-ai-coding-era |
| Uplevel (~800명, 대조군) | Copilot 사용군 PR 사이클·처리량 개선 없음 + PR 내 버그 41% 증가 — 단 자동완성 시대 데이터·방법론 비판 존재(중간 신뢰도) | '도구만 주면 득이 없다'는 방향 근거로만 | https://devops.com/study-finds-no-devops-productivity-gains-from-generative-ai/ |
| Stack Overflow 2025 | 84% 사용 vs 정확성 신뢰 33%(고신뢰 3%) · 66%가 'almost right' 출력에 고전 · 45%는 AI 코드 디버깅이 직접 짜기보다 오래 걸림 | 'almost right'가 지배적 실패 모드 — /inspect·수용 기준 검수가 겨냥할 지점 | https://survey.stackoverflow.co/2025/ai/ |
| 지표 게이밍 | Amazon 주간 AI 사용률 80% 목표+토큰 리더보드 → 개인 용무 토큰 소진으로 지표 채움, 리더보드 중단 | 스킬 '사용 준수율' 지표를 만들면 같은 함정 — 측정은 산출(결함률·반려율·리드타임)에 걸어야 | https://futurism.com/artificial-intelligence/amazon-quotas-ai-use · https://news.ycombinator.com/item?id=47455064 |
| MIT NANDA | 기업 GenAI 파일럿 95%가 측정 가능한 P&L 효과 없음 — 원인은 learning gap(피드백 보존 실패) | 구조 없는 도입은 실패가 디폴트(우리 전제 지지)이나, 자체 구축 경로의 성공률이 구매의 1/3이라는 점은 자작 프레임워크 경고 | https://fortune.com/2025/08/18/mit-report-95-percent-generative-ai-pilots-at-companies-failing-cfo/ |

### 2-5. 규칙 계층의 함정

| 증거 | 내용 | 충돌 지점 | 출처 |
|------|------|-----------|------|
| 총량 과소계상 | 시스템 프롬프트가 이미 ~50개 지시 소모, 실질 예산 100~150개 · paths 없는 rules는 시작 시 전부 로드 · @import 분할은 컨텍스트 절약 0 (공식 명시) | "90줄이라 안전"은 파일 단위 착시 — rules가 실제 paths 스코핑인지 감사 필요 | https://www.humanlayer.dev/blog/writing-a-good-claude-md · https://code.claude.com/docs/en/memory |
| 경로 규칙 트리거 갭 | path-scoped 규칙은 '매칭 파일을 읽을 때' 로드 — 신규 파일 '생성'(우리 워크플로 최빈 작업) 시 미발동 가능 | /module·/dev 스킬이 관련 규칙을 명시 주입하는 보완 없으면 침묵 실패 | https://code.claude.com/docs/en/memory |
| 강조해도 위반 | 'NEVER cp' 3회 반복 규칙을 같은 세션서 2회 위반, 프로덕션 덮어씀 — duplicate로 닫힌 미해결 실패 계열(#7777·#42863 동류) | 밀도 관리로도 보장 불가 — #카드번호·경계 import 금지·main 직push 금지 등 고비용 규칙은 전부 훅/CI 이중화 여부를 규칙별 감사 | https://github.com/anthropics/claude-code/issues/15443 |
| 축적 루프 반패턴 | '위반→규칙 추가'로 400줄→더 무시. 잘 작동 파일 중앙값 300~350단어, 1,000단어+는 성능과 음의 상관 · 40~80줄 권장 기준으론 90줄도 이미 상한 초과 | /retro의 구조적 '추가 압력'에 가지치기 규율(추가 1건당 삭제/훅 전환 후보) 없으면 재연 | https://tianpan.co/blog/2026-02-14-writing-effective-agent-instruction-files · https://dev.to/minatoplanb/i-wrote-200-lines-of-rules-for-claude-code-it-ignored-them-all-4639 |
| 상충 시 임의 선택 | 두 규칙이 상충하면 "Claude may pick one arbitrarily" · /compact 후 중첩 CLAUDE.md는 재주입 안 됨 | 3층(CLAUDE.md·rules·skills) 간 중복·상충 린트 장치가 우리에 없음 · '매 응답 안내' 규칙은 컴팩션·긴 세션서 소실 취약 | https://code.claude.com/docs/en/memory |

### 2-6. 병렬 작업의 구조적 잔여 갭

| 증거 | 내용 | 충돌 지점 | 출처 |
|------|------|-----------|------|
| 마이그레이션 corruption | 병렬 브랜치의 동시 마이그레이션 생성 → 모델 스냅샷이 서로를 몰라 "later migrations의 various forms of corruption" — 사전 조율 강권(MS 공식). Django·Rails 동일 계열 | 'DB 통째 1인 소유'로도 못 막는 전역 직렬 자산 — 셀프 머지 그대로면 여기서 먼저 깨짐 | https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/teams |
| 핫스팟 overlap zone | 라우팅 테이블·설정·레지스트리·lockfile은 충돌 집결지 — touch 시 사람 리뷰 의무화 권고(원칙론, 실측 없음) | 전 경로 무리뷰와 정면 충돌 — 경로 기반 예외 검토 대상 | https://getautonoma.com/blog/parallel-ai-agent-prs |
| 결정 충돌 | "Actions carry implicit decisions, and conflicting decisions carry bad results" — 파일 안 겹쳐도 계약·스타일·가정에서 충돌 | index.ts만으론 부족 — 인터페이스·ADR이 병렬 착수 '전' 확정돼야 | https://cognition.com/blog/dont-build-multi-agents |
| 같은 디렉터리 복수 세션 | 머지 마커도 경고도 없는 last-writer-wins 무음 덮어쓰기 — Reddit/GitHub top-5 pain point | 한 개발자가 같은 클론에 세션 2개 띄우는 순간 발생 — '1클론=1세션 or worktree' 규칙 부재 | https://github.com/mercurialsolo/claudectl/issues/58 · https://code.claude.com/docs/en/worktrees |
| 주의력 병목 | 실사용자 한계 ~3세션 · "느린 에이전트 하나가 실수 많은 여러 개를 이긴다" · 심야 10 병렬은 '생산성이 아니다' | '다음 명령 안내'가 개발자당 세션 증식으로 흐르면 검수 품질이 먼저 무너짐 | https://news.ycombinator.com/item?id=46682551 |

### 2-7. 검수자(비개발 1인) 리스크

| 증거 | 내용 | 충돌 지점 | 출처 |
|------|------|-----------|------|
| 이중 부담 병목 | 스펙 리뷰+결과 리뷰 이중 부담(Marmelab) · 기능 1개 문서 리뷰 3.5시간(Scott Logic) | 개발 4~5인이 병렬로 쏟아내는 카드의 게이트를 1인이 다 지면 새 워터폴 단계 | https://marmelab.com/blog/2025/11/12/spec-driven-development-waterfall-strikes-back.html |
| 권한 사고 | push 권한 가진 비개발자 1명이 CI 우회, 리뷰 없이 프로덕션 배포 → '비개발자는 PR만·보호 브랜치 직push 금지'로 회귀 | 검수자 GitLab 계정이 Developer 이상이면 동일 사고 표면 — Reporter 수준+보호 브랜치 명시 필요 | https://dev.to/epilot/our-entire-company-ships-code-now-40-prs-from-non-engineers-in-60-days-jo5 |
| 모호 카드→'정상' 오구현 | 불명확 프롬프트에 Codex가 스코프 밖 전체 수정(채널톡 — 개발자 리뷰가 잡음) · PANDA는 불명확 티켓을 에이전트에 안 줌(자동 Blocked) | 검수자가 쓴 모호한 카드가 'CI 통과하는, 요구와 다른 정상 코드'로 배포되는 경로가 우리 최대 사각 — CI는 요구 부합을 못 잡음 | https://tech.channel.io/ko/articles/제품-개발-이후-그-바깥의-AI---버그-잡는-디자이너-b053eb17 · https://medium.com/totalenergies-digital-factory/our-ai-agent-does-not-write-code-it-ships-features-e5d679d67d71 |
| 스코프 오판 | 비개발자가 '하루짜리'로 잡은 요청이 실제 3일짜리 DB 구조 변경 — 가능한 것의 멘탈 모델 부재 | /change 영향분석이 검수자 카드의 스코프를 되짚는 장치로 작동해야 | https://www.news.aakashg.com/p/claude-code-non-technical-pms |
| 참여 지속 실패가 기본값 | Intercom 1,000+ 배포 중 주간 활성 ~30% — 성공 요인은 도구가 아니라 스킬·온보딩·enablement · 채널톡 '막히면 포기·에스컬레이션' 규칙 운영 | 검수자용 경로(카드 템플릿·반려 형식)를 스킬이 커버 안 하면 이탈이 기본값 | https://ideas.fin.ai/p/we-gave-claude-code-to-everyone-at |

---

## §3 우리가 안 하고 있는데 바깥에서 검증된 실천 (도입 후보)

| # | 실천 | 1줄 근거 | 출처 |
|---|------|----------|------|
| 1 | **AI 코드리뷰 층 (fresh context 필수)** | Anthropic 100% 자동 Claude 리뷰·LY Corp 32repo/월344리뷰·Cloudflare 월 13만 리뷰 실운영 — 단 구현 세션과 분리(자기선호 편향). ★**킷 반영형**: CI의 `claude -p` 잡은 개발자 구독과 **별개 API 결제**라 P2 선택으로만 두고, 기본은 `/done`의 `/code-review`를 **fresh 서브에이전트**로 돌린다(구독 내, 추가 비용 0). "비용 신경 끄기" 원칙과 정합 | note.com/ai_eng_tech/n/nf940a6dc47e6 · techblog.lycorp.co.jp · blog.cloudflare.com/ai-code-review/ · howborisusesclaudecode.com |
| 2 | **CI에 SAST·시크릿·의존성 스캔 층** | AI 코드의 급증 결함(권한상승 +322%·XSS 2.74배·시크릿 ~2배)은 우리 CI 4종 어디에도 안 걸림; 무리뷰 진영(Codacy)조차 4층 게이트에 보안 스캔 포함 | apiiro.com · blog.codacy.com |
| 3 | **테스트/CI 설정 변조 탐지** — src와 테스트·임계값 동시 수정 PR 플래그 | 에이전트가 '통과하도록 테스트를 고쳐쓰는' 행동이 반복 실증 — CI-green은 게이밍 가능 | news.ycombinator.com/item?id=44678535 |
| 4 | **리스크 티어링(Ask 레인)** — 인증·결제성·마이그레이션·shared 승격·핫스팟 경로는 사람(최소 교차 소유자) 확인 **→ 이후 채택됨(Playbook §5, 고위험만 동료 1명 승인)** | Ship/Show/Ask 원저자도 Always Ship 경고; Osmani·Codacy(무리뷰 옹호 진영)도 고위험 카브아웃 전제 | martinfowler.com/articles/ship-show-ask.html · addyosmani.com/blog/agentic-code-review/ · blog.codacy.com |
| 5 | **DB 마이그레이션 직렬화 규칙** — 생성 클레임 카드 또는 CI의 분기 감지·재생성 강제 | 병렬 마이그레이션 생성은 corruption 유발, 사전 조율이 벤더 공식 권고 | learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/teams |
| 6 | **병렬 세션 worktree 규칙(1클론=1세션) + 포트/DB 할당 규약** | 같은 디렉터리 복수 세션=무음 덮어쓰기(top-5 pain point); 로컬 DB·포트 격리가 실팀 잔여 마찰 | code.claude.com/docs/en/worktrees · github.com/mercurialsolo/claudectl/issues/58 · incident.io 블로그 |
| 7 | **카드 품질 하드 게이트** — 수용 기준 불명확 카드는 자동 Blocked(에이전트에 안 줌) | "티켓 품질이 구현 품질을 직접 결정 — 의도된 설계로 티켓 작성 문화를 개선" | medium.com/totalenergies-digital-factory |
| 8 | **규칙 가지치기 주기** — 줄마다 "지우면 실수하는가" 테스트, 회고 시 추가 1건당 삭제/훅 전환 후보 1건 | 규칙 축적 루프('위반→추가→400줄→더 무시')는 다수 소스가 확인한 반패턴; 공식 문서가 프루닝 테스트 권고 | code.claude.com/docs/en/memory · tianpan.co |
| 9 | **파일럿 실측 계측을 첫날부터** — GitLab 리드타임·결함률·리버트율·반려율(체감·사용량 지표 금지) | 체감은 반대로도 틀리고(METR 인지 격차), 사용량 지표는 게이밍됨(Amazon 쿼터) | metr.org · futurism.com |
| 10 | **머지 전 AI 셀프리뷰(적대적 리뷰 서브에이전트) 단계를 /dev·/fix에** | 제출 전 AI 셀프리뷰가 nit 왕복 ~1/3 절감; diff에 대한 적대적 리뷰 서브에이전트는 공식 best practice | github.blog(merge button 글) · code.claude.com/docs/en/best-practices |
| 11 | **중복·churn 감시(jscpd 류)를 CI에** | AI의 '재사용 대신 재생성' 성향(중복 +81%·재사용 -70%)은 화면·테스트 어느 층에도 안 보임 — 1인 소유+승격 지연 구조에서 가속 위험 | gitclear.com · leaddev.com |
| 12 | **검수자 권한 최소화** — GitLab Reporter 수준(이슈·댓글만)+보호 브랜치 설정 명문화 | push 권한 가진 비개발자의 CI 우회 프로덕션 배포 사고 실증 후 거버넌스 회귀 | dev.to/epilot |
| 13 | **고비용·위반 빈발 규칙은 CLAUDE.md 앞뒤 중복 배치 + 훅 이중화** | primacy bias 실측(IFScale)·짧은 NEVER 규칙도 위반(#15443) — 배치 전술+기계 강제 병행 | arxiv.org/abs/2507.11538 · github.com/anthropics/claude-code/issues/15443 |
| 14 | **수용 기준을 실행 가능한 테스트로 물화** (스펙-구현 drift의 기계 검증) | "스펙과 동작의 일치를 체계적으로 판정할 방법이 없다"(bit-rot)는 SDD 최대 약점; 수용 테스트 선작성이 "20x ROI" 실증 보고 | news.ycombinator.com/item?id=47417804 · news.ycombinator.com/item?id=45935763 |

---

## §4 못 찾은 것 (정직한 공백 — 7각도 notFound 취합)

**우리 설계의 핵심 검증 공백 (가장 중요):**
- **개발자 4~6인 규모에서 trunk-based + CI 통과 시 사람 리뷰 없는 auto-merge를 실제 운영한 팀의 1차 사례** — 성공이든 실패든, 7각도 전부에서 미발견. 존재하는 것은 솔로 사례·집계 텔레메트리·리뷰 '선택화'(BridgeCare) 사례뿐.
- 인간 리뷰 제거 전후의 변경실패율/결함률 **통제 비교 연구** — 일화와 상관 텔레메트리(Faros)만 존재.
- 우리와 동일 조합(개발 4~5인+비개발 검수 1인+Claude Code CLI+self-hosted GitLab)의 공개 운영 사례 — 근접 사례(Kilo Code 7인)도 검수자·셀프머지까지는 안 겹침.

**절차·스킬 관련:**
- '매 응답 끝 다음 명령 안내' + 전 절차를 슬래시 명령 11종으로 표준화한 실팀 선례 — 커스텀 커맨드 공유는 흔하나 전 절차 명령 체계 강제는 미발견.
- 멀티에이전트 **시뮬레이션으로 프로세스 마찰을 사전 수확하는 방법의 선례·효과 데이터** — 미발견 (추정: 이 방법 자체가 신규 영역).
- Claude Code 스킬 자동 호출 신뢰도 실측 · 스킬 설명문의 상시 컨텍스트 비용 정량 자료.

**규칙 밀도 관련:**
- CLAUDE.md 줄 수↔준수율의 통제 A/B 실험 — 200줄/80줄 등 실무 수치는 전부 커뮤니티 합의·일화·공식 문서의 무근거 수치.
- 훅/CI 강제 vs 프롬프트 규칙 준수율의 방법론 있는 head-to-head — '훅=100%, advisory=~80%' 류 수치는 측정 방법 비공개.
- path-scoped rules가 '파일 생성 시 미발동'하는지의 공식 확인 (서드파티 보고만, 중간 신뢰도).

**비개발자 루프 관련:**
- 비개발자 검수의 결함 검출률 등 정량 데이터 — 일화만 존재.
- 비개발자가 AI 개발 루프에서 이탈한 이유의 정면 분석 — 간접 신호(Intercom 활성 ~30%, 채널톡 '티켓 포기' 규칙)만.
- 이슈/수용 기준 품질→AI 구현 품질의 통제 실험 — 실무 보고(PANDA·Osmani 2,500파일 분석)만.

**병렬·인프라 관련:**
- 모듈/디렉터리 오너십의 충돌 감소 정량 전후 데이터 · git worktree 병렬 패턴의 통제된 효과 측정 — 전부 일화.
- self-hosted **GitLab**에서 Claude Code를 CI/리뷰에 통합한 팀 사례 — 발견된 것은 전부 GitHub Actions 기반 (GitLab 통합의 실전 마찰은 미검증).
- 복수 에이전트 동일 파일 동시 편집→프로덕션 사고의 검증 가능한 1차 포스트모템.

**원문 접근 실패·폐기 항목 (투명성):**
- OpenAI harness-engineering 원문(HTTP 403, 미러로 교차 확인 — 인시던트/리버트율 등 품질 결과 자체가 미공개).
- GitClear 2026 원문(403 — LeadDev 2차 보도로 수치 검증) · DORA 2025 본문 PDF(랜딩만 — Google Cloud 공식 블로그로 교차 확인).
- Apiiro 원문(JS 렌더링으로 본문 접근 불가 — 역검증에서도 실패. 수치(+322%·XSS 2.74배 등)는 2차 보도 다수로만 교차, **원문 미대조 상태**임을 명시).
- Meta '전 diff 리뷰 필수' 정책의 1차 문서(2차 언급만) · Cursor Habits Report 원문(2차 보도만, 중간 신뢰도).
- 폐기: '스토리지 볼륨 삭제 포스트모템'(1차 출처 미확보) · CodeRabbit 홍보성 실패담 · digitalapplied.com 류 무근거 SEO 실패담 · '구조화 롤아웃 47% vs ad hoc 12%'(1차 출처 미확인) · HN 스레드 2건(429 접근 실패).
- 한국 대형 테크(토스·당근·카카오·우아한형제들)의 공식 Claude Code 팀 도입기 — 미발견 (발견된 국내 1차: 카카오페이·컬리·채널톡·LY·한컴·Hyperithm·KT Cloud·gpters·briandwjang). 국내 관행은 오히려 '리뷰 도입/강화' 방향이며 LY 멀티에이전트 사례는 '에이전트 셀프머지 금지'를 규칙으로 명시 — 우리 설계는 국내 관행과 역방향임을 확인.

---

## §5 출처 전체 목록

### 공식 문서·벤더 (Anthropic/Claude Code)
1. https://code.claude.com/docs/en/best-practices — CLAUDE.md 간결·훅=결정적·적대적 리뷰 서브에이전트·worktree
2. https://code.claude.com/docs/en/memory — 200줄 목표·advisory 한계·paths rules·프루닝 테스트·compact 함정
3. https://code.claude.com/docs/en/large-codebases — 2-tier CLAUDE.md·디렉터리 소유자 유지·rules paths
4. https://code.claude.com/docs/en/agent-teams — 파일셋 소유·클레임 락·3~5 규모
5. https://code.claude.com/docs/en/worktrees — 세션당 worktree 격리
6. https://claude.com/blog/how-anthropic-teams-use-claude-code — Anthropic 10+ 팀 사용기
7. https://www.anthropic.com/engineering/building-c-compiler — 16 병렬 에이전트·태스크 클레임
8. https://github.com/anthropics/claude-code/issues/15443 — 규칙 위반 공식 이슈

### Anthropic 인물·주변 1차
9. https://note.com/ai_eng_tech/n/nf940a6dc47e6 — Boris Cherny 팟캐스트 transcript (AI 리뷰 후 인간 리뷰층)
10. https://workos.com/blog/boris-cherny-claude-code-acquired-interview-takeaways
11. https://howborisusesclaudecode.com/ — CLAUDE.md 축적 루프·self-preferential bias

### 무리뷰 머지·리뷰 연구
12. https://testdouble.com/insights/when-code-reviews-arent-mandatory — BridgeCare
13. https://martinfowler.com/articles/ship-show-ask.html
14. https://copyconstruct.medium.com/post-commit-reviews-b4cc2163ac7a — Quora post-commit
15. https://www.apache.org/foundation/glossary.html — CTR/RTC
16. https://dora.dev/capabilities/streamlining-change-approval/
17. https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/ICSE202013-codereview.pdf — Bacchelli & Bird 2013
18. https://sback.it/publications/icse2018seip.pdf — Google Modern Code Review 2018
19. https://openai.com/index/harness-engineering/ (원문 403; 미러 https://zby.github.io/commonplace/sources/harness-engineering-leveraging-codex-agent-first-world/)
20. https://blog.cloudflare.com/ai-code-review/
21. https://deepsource.com/blog/ai-code-review-benchmarks (+ https://arxiv.org/html/2509.01494v1)
22. https://github.blog/ai-and-ml/generative-ai/code-review-in-the-age-of-ai-why-developers-will-always-own-the-merge-button/
23. https://simpleprogrammer.com/code-review-trunk-based-development/
24. https://blog.codacy.com/code-review-is-dead-why-ai-generated-code-needs-verification-not-human-approval
25. https://addyosmani.com/blog/agentic-code-review/ — Faros AI·CodeRabbit 집계

### 절차 프레임워크 회고 (SDD·BMAD·GSD·superpowers)
26. https://blog.scottlogic.com/2025/11/26/putting-spec-kit-through-its-paces-radical-idea-or-reinvented-waterfall.html
27. https://github.com/github/spec-kit/discussions/1784
28. https://marmelab.com/blog/2025/11/12/spec-driven-development-waterfall-strikes-back.html
29. https://news.ycombinator.com/item?id=45935763 — SDD 양론
30. https://architectureforgrowth.com/bmad-framework-personal-project-experience/
31. https://github.com/bmad-code-org/BMAD-METHOD/issues/1332 (+ /issues/2199, /issues/2003)
32. https://news.ycombinator.com/item?id=47417804 — GSD 스레드
33. https://news.ycombinator.com/item?id=47623101 — superpowers 스레드
34. https://lethain.com/everyinc-compound-engineering/ — Will Larson
35. https://timdeschryver.dev/blog/keep-agentic-ai-simple-a-practical-workflow-for-software-development
36. https://rywalker.com/research/agentic-skills-frameworks — 프레임워크 20종 비교
37. https://bennycheung.github.io/bmad-reclaiming-control-in-ai-dev

### 병렬·충돌·trunk-based
38. https://github.com/mercurialsolo/claudectl/issues/58
39. https://cognition.com/blog/dont-build-multi-agents
40. https://getautonoma.com/blog/parallel-ai-agent-prs
41. https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/teams
42. https://dora.dev/capabilities/trunk-based-development/
43. https://martinfowler.com/articles/micro-frontends.html
44. https://www.microsoft.com/en-us/research/uploads/prod/2016/02/bird2011dtm.pdf — Don't Touch My Code (FSE 2011)
45. https://news.ycombinator.com/item?id=46682551 (+ https://blog.kilo.ai/p/how-7-kilo-code-engineers-run-up)
46. https://www.gpters.org/dev/post/12x-parallel-development-claude-JEr2GK2Yya8YSwd
47. https://addyosmani.com/blog/code-agent-orchestra/
48. https://docs.gitlab.com/ci/pipelines/merge_trains/ (+ https://news.ycombinator.com/item?id=36708486)
49. https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees

### 규칙 밀도·컨텍스트 연구
50. https://arxiv.org/abs/2507.11538 — IFScale
51. https://arxiv.org/abs/2307.03172 — Lost in the Middle
52. https://www.trychroma.com/research/context-rot
53. https://www.humanlayer.dev/blog/writing-a-good-claude-md
54. https://tianpan.co/blog/2026-02-14-writing-effective-agent-instruction-files
55. https://tech.hancom.com/claude-md-context-optimization/
56. https://dev.to/minatoplanb/i-wrote-200-lines-of-rules-for-claude-code-it-ignored-them-all-4639
57. https://dev.to/docat0209/5-patterns-that-make-claude-code-actually-follow-your-rules-44dh
58. https://news.ycombinator.com/item?id=46102048 — 카나리아 규칙

### 비개발자 루프
59. https://dev.to/epilot/our-entire-company-ships-code-now-40-prs-from-non-engineers-in-60-days-jo5
60. https://medium.com/totalenergies-digital-factory/our-ai-agent-does-not-write-code-it-ships-features-e5d679d67d71 — PANDA
61. https://tech.channel.io/ko/articles/제품-개발-이후-그-바깥의-AI---버그-잡는-디자이너-b053eb17 — 채널톡
62. https://ideas.fin.ai/p/we-gave-claude-code-to-everyone-at — Intercom 전사 배포
63. https://www.lennysnewsletter.com/p/how-intercom-2xd-their-engineering
64. https://addyosmani.com/blog/good-spec/
65. https://www.news.aakashg.com/p/claude-code-non-technical-pms
66. https://briandwjang.substack.com/p/claude-code
67. https://medium.com/daangn/ai-툴-개발은-처음이라-당근-비개발자-구성원들의-ai-도전기-fb62d2a6c2f3 (본문 추출 실패, 스니펫 확인)
68. https://getautonoma.com/blog/vibe-coding-failures — Replit 사고 집계

### 도입 역효과·측정
69. https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/
70. https://metr.org/blog/2026-02-24-uplift-update/
71. https://dora.dev/research/2024/dora-report/ (+ https://getdx.com/blog/2024-dora-report/)
72. https://dora.dev/dora-report-2025/ (+ https://www.infoq.com/news/2025/09/dora-state-of-ai-in-dev-2025/ · https://cloud.google.com/blog/products/ai-machine-learning/introducing-doras-inaugural-ai-capabilities-model)
73. https://www.gitclear.com/ai_assistant_code_quality_2025_research
74. https://leaddev.com/ai/code-maintainability-plummets-in-the-ai-coding-era — GitClear 2026 (원문 403)
75. https://fortune.com/2026/03/18/ai-coding-risks-amazon-agents-enterprise/
76. https://apiiro.com/blog/4x-velocity-10x-vulnerabilities-ai-coding-assistants-are-shipping-more-risks/
77. https://devops.com/study-finds-no-devops-productivity-gains-from-generative-ai/ (방법론 비판: https://jasonstcyr.com/2024/10/09/does-github-copilot-actually-raise-bugs-in-code-by-41/)
78. https://survey.stackoverflow.co/2025/ai/ (+ https://stackoverflow.co/company/press/archive/stack-overflow-2025-developer-survey/)
79. https://fortune.com/2025/08/18/mit-report-95-percent-generative-ai-pilots-at-companies-failing-cfo/ — MIT NANDA
80. https://futurism.com/artificial-intelligence/amazon-quotas-ai-use (+ https://news.ycombinator.com/item?id=47455064)
81. https://9to5google.com/2025/06/30/google-engineers-ai-code/
82. https://news.ycombinator.com/item?id=44678535 — HN 기만적 완료 보고
83. https://mnemehq.com/insights/cursor-developer-habits-report-governance-infrastructure/ (2차, 중간 신뢰도)

### 국내 팀 1차
84. https://tech.kakaopay.com/post/ifkakao-agentic-coding/ — 카카오페이 SDD
85. https://engineering.cocone.io/ko/2025/11/13/spec-kit-sdd-github-review/ — cocone
86. https://helloworld.kurly.com/blog/vibe-coding-with-claude-code/ — 컬리
87. https://techblog.lycorp.co.jp/ko/building-ai-code-review-platform-with-claude-code-action — LY Corp
88. https://tech.hyperithm.com/claude_code_guides — Hyperithm
