# addyosmani/agent-skills 분석 — 참조 정본

> **분석 기준일: 2026-07-10** · 출처: https://github.com/addyosmani/agent-skills (전체 clone 후 전수 열람, 최신 커밋 `6bcfeb9` 2026-07-09 — 활발히 유지보수 중) · 라이선스: MIT
> **무엇인가:** Addy Osmani(Google Chrome 팀 엔지니어링 리더, 『Software Engineering at Google』 계열 실천의 대중화자)가 만든
> **"AI 코딩 에이전트용 시니어 엔지니어링 스킬 팩"** — 개발 생명주기 전체(Define→Plan→Build→Verify→Review→Ship)를 24개 스킬로 인코딩.
> **용도:** 우리 스킬 체계(`3-starter-kit/.claude/skills/` 8종, 골든 패스 가이드 §4)를 다듬거나 확장할 때 이 문서를 먼저 참조.
> 부분 차용(à la carte)이 정답이며 통째 도입은 라우터 충돌을 낳는다(→ §7 주의).

---

## 1. 한 줄 요약

**"AI 에이전트는 기본적으로 최단 경로(스펙·테스트·리뷰 생략)를 탄다 — 시니어 엔지니어의 규율을 스킬(워크플로)로 강제한다."**
우리 Team Dev Mode가 *팀 협업 절차*(카드→개발→머지→검수)를 스킬로 만든 것이라면, 이 팩은 *엔지니어링 품질 규율*(스펙 먼저, 테스트 먼저, 측정 먼저, 의심 먼저)을 스킬로 만든 것이다. 층이 달라서 **경쟁이 아니라 상호보완**이다.

## 2. 저장소 구조

```
skills/          24개 스킬 (23 라이프사이클 + 1 메타 라우터) — SKILL.md 파일당 평균 ~290줄, 최대 461줄
agents/          4개 리뷰 페르소나 (code-reviewer · security-auditor · test-engineer · web-performance-auditor)
.claude/commands/ 8개 슬래시 명령 (/spec /plan /build /test /review /webperf /code-simplify /ship)
references/      7개 체크리스트 (definition-of-done · testing · security · performance · a11y · observability · orchestration)
hooks/           SessionStart(메타스킬 주입) + sdd-cache(문서 fetch의 HTTP 304 재검증 캐시)
evals/           스킬당 평가 케이스 24개 + 3층 평가 러너 (★이 repo의 독자적 기여 — §6)
docs/            도구별 설치 가이드 (Cursor·Gemini·Codex·Copilot·Windsurf·OpenCode…) + 경쟁 팩 비교
```

- **멀티 도구 배포가 1급 관심사**: Claude Code 플러그인 마켓플레이스 + `npx skills add`(70+ 에이전트) + Gemini/Codex/Antigravity 네이티브 플러그인. 같은 스킬 마크다운을 도구별 어댑터(`.claude/` `.gemini/` `.codex-plugin/` `commands/*.toml`)로 감쌌다.
- 스킬 단위 부분 설치 지원: `npx skills add addyosmani/agent-skills --skill <이름>`.

## 3. 핵심 설계 ① — 스킬 해부학 (전 스킬 공통 6절 구조)

```
Frontmatter(name + description "무엇 + Use when 트리거")
Overview → When to Use(+ NOT to use) → Process(번호 단계)
→ Common Rationalizations(★) → Red Flags → Verification(증거 체크리스트)
```

- **★Common Rationalizations 표 = 이 팩의 가장 독자적인 장치.** "에이전트가 단계를 건너뛸 때 대는 핑계"를 반박과 쌍으로 박아둔다:

  | 핑계 (에이전트가 실제로 하는 말) | 반박 |
  |---|---|
  | "테스트는 코드 되고 나서 쓸게" | 안 쓴다. 사후 테스트는 행동이 아니라 구현을 테스트한다 |
  | "이건 너무 단순해서 스펙 불필요" | 단순한 작업도 완료 기준은 필요하다. 두 줄짜리 스펙이면 된다 |
  | "다시 한 번만 테스트 돌려서 확실히 하자" | 코드가 안 바뀌었으면 같은 명령 재실행은 아무것도 더하지 않는다 |

  → 우리 `adversarial-review`의 false-done 체크리스트(A~H)·CLAUDE.md의 "이미 부정된 방법 재등장 금지"와 정확히 같은 목적을, **스킬 파일 안에 표준 절(節)로 내장**한 형태. 골든 패스 가이드 §4.3의 "❌ 금지 목록" 패턴의 상위호환이다(금지 + *왜*까지).
- **Verification 절이 전 스킬 필수**: "Seems right는 증거가 아니다 — 테스트 출력·빌드 결과·런타임 데이터" = 우리 `done-means-observed-working` 교훈과 동일 사상.
- 크기 규율: SKILL.md 500줄 이하, 참조 파일 1단계 깊이까지, "스크립트 실행은 컨텍스트 0·인라인 코드는 매 로드마다 과금" — Claude Code 공식 가이드와 일치(우리 `claude-code-docs-analysis.md` §4).

## 4. 핵심 설계 ② — 메타스킬 라우터 + 상시 행동 규칙

`using-agent-skills`(메타스킬)가 SessionStart 훅으로 **매 세션 자동 주입**되어 두 가지를 한다:

1. **라우팅 플로차트**: 작업 유형 → 스킬 매핑 ("뭘 원하는지 모름→interview-me, 새 기능→spec-driven, 깨짐→debugging…").
2. **Core Operating Behaviors 6종** (스킬 무관 상시 규칙 — 사실상 CLAUDE.md 역할):
   - **가정을 표면화하라** — "ASSUMPTIONS I'M MAKING: 1…2…3… → 지금 고쳐주거나, 이대로 진행한다" 형식 강제
   - **혼란을 능동 관리** — 모순 발견 시 추측으로 진행 금지, STOP하고 질문
   - **아첨 금지, 반박하라** — "Of course!" 하고 나쁜 아이디어를 구현하는 게 실패 모드. 구체 수치로 반대("~200ms 느려짐")
   - **단순성 강제** — "1000줄 짰는데 100줄이면 됐다 = 실패"
   - **범위 규율** — 시킨 것만. 이해 못 한 주석 삭제 금지, 인접 리팩토링 금지
   - **검증하라, 가정 말고** — 프로젝트 전체 기준선은 `references/definition-of-done.md`

## 5. 핵심 설계 ③ — 명령 8종과 두 가지 실행 모드

| 명령 | 원칙 한 줄 | 비고 |
|---|---|---|
| `/spec` | 코드 전에 스펙 | SPECIFY→PLAN→TASKS→IMPLEMENT 4단계 **각각에 사람 검토 게이트** |
| `/plan` | 작은 원자 작업 | 산출 규약: `tasks/plan.md` + `tasks/todo.md` (하류 명령이 이 경로를 기대) |
| `/build` | 한 번에 한 슬라이스 | 작업 1개: RED→GREEN→회귀→빌드→커밋→정지 |
| **`/build auto`** | 승인 1회, 이후 자율 | ★스펙 존재 필수(없으면 거부) + 깨끗한 git 기준선 확인 + **작업당 커밋**(롤백 보장) + 모호/고위험(auth·마이그레이션·결제·revert 불가)이면 정지. "사람을 *작업 사이*에서 뺄 뿐, 검증에서 빼지 않는다" |
| `/test` | 테스트가 증거 | TDD 스킬 + 브라우저면 DevTools MCP |
| `/review` | 코드 건강 개선 | 5축 리뷰(정확성·가독성·아키텍처·보안·성능), 심각도 라벨(Nit/Optional/FYI), ~100줄 change sizing |
| `/code-simplify` | 영리함보다 명료함 | Chesterton's Fence(왜 있는지 모르는 건 못 없앤다) |
| **`/ship`** | 빠른 것이 안전한 것 | ★페르소나 3종 **병렬 fan-out**(한 턴에 동시 스폰) → 메인이 병합 → **GO/NO-GO + 롤백 계획(필수)**. Critical 1건이면 기본 NO-GO |

- 승인 판정이 엄격하다: `/build auto`는 "approve/go/yes"만 승인으로 치고 **"looks reasonable, I guess" 같은 얼버무림은 미승인 취급** — 게이트의 언어까지 설계.

## 6. 핵심 설계 ④ — 페르소나 3층 모델과 evals (이 팩만의 것)

**3층 구성**: 스킬 = *how*(워크플로) / 페르소나 = *who*(관점+보고서 양식) / 명령 = *when*(진입점·조합).
- 철칙: **"페르소나는 페르소나를 부르지 않는다"** — 조합은 명령·사람의 몫. 유일하게 승인된 오케스트레이션 = `/ship`식 병렬 fan-out(독립 관점 → 메인 병합). "라우팅만 하는 메타 오케스트레이터"는 명시적 안티패턴(정보 손실 + 2배 토큰).
- `doubt-driven-development` 스킬: 비자명한 결정마다 **fresh-context 반박 전용 리뷰어**를 스폰 — CLAIM→EXTRACT(추론 벗겨 산출물만)→DOUBT(반증 편향 리뷰)→RECONCILE→STOP(3사이클 상한). "긴 세션은 가정을 조용히 '사실'로 굳힌다"가 문제 인식. = 우리 adversarial-review·critic 루프백과 같은 아이디어의 in-flight(진행 중) 판.

**evals 3층 — 스킬 품질을 CI로 측정 (조사한 스킬 팩 중 유일):**

| 층 | 검사 | 실행 |
|---|---|---|
| 1 구조 | frontmatter·필수 절·명령 패리티 | CI, 무료 |
| 2 트리거·라우팅 | 긍정 프롬프트가 그 스킬을 top-k에 올리나 / 부정 프롬프트에선 **주인 스킬이 이기나** / 스킬 설명끼리 75%+ 유사 = 충돌 에러 | CI, 무료 (TF-IDF 어휘 근사) |
| 3 행동 | headless claude로 실행 → **최종 산문이 아니라 실행 트레이스(도구 호출 포함)를 채점** ("실패 테스트를 고치기 *전에* 돌렸나") | 온디맨드, 토큰 비용 |

- Anthropic skill-creator v2의 `evals.json` 스키마를 그대로 채택 + Tier 2(카탈로그 라우팅 충돌 검사)는 자체 고안. 신규 스킬은 eval 파일 동봉이 규칙(긍정 3+ 부정 2+ 행동 1+).
- → 우리의 "검사 묶음을 앞단에" 철학을 **스킬 자체에 적용**한 것: 스킬이 늘어날수록 서로 트리거를 잠식하는 문제를 기계로 잡는다.

## 7. 경쟁 팩과의 위치 (docs/comparison.md — 자체 비교가 정직한 편)

| | **agent-skills** | **Superpowers** (obra) | **mattpocock/skills** |
|---|---|---|---|
| 핵심 | SDLC 전 단계 + 메타 라우터 | 자율·긴 호흡 방법론(서브에이전트 2단 리뷰 + worktree 격리) | 한 전문가의 일상 `.claude` 툴킷 |
| 강점 | 검증 폭(단계별 사람 체크포인트, 병렬 리뷰) | 선행 추론 깊이·자율 위임 | 저의식(low-ceremony) 일상 루프, /grill-me·/tdd |
| 실측 | 동일 과제 비교실험(Om Mishra): agent-skills가 더 빨리 착수 + 검증 패스 7회(vs 5)로 기능 밖 호환성 문제까지 검출, Superpowers는 선행 아키텍처 추론 우위 — "과제에 맞게 골라라" | | |

★**공식 경고: 두 팩을 동시에 활성 라우터로 쓰지 마라** — 명령명 충돌(/tdd 2곳 정의)·라우팅 경쟁·TDD 철학 충돌로 예측불능. **주 라우터 하나 + 개별 스킬만 à la carte 차용**이 권장.

## 8. 우리 설계(Team Dev Mode·starter-kit)와의 관계 — 가져올 것 / 안 가져올 것

**층이 다르다 (충돌 없음):**
- 우리 스킬 8종(/todo /dev /fix /done /module /docs /change /log) = **팀 협업 절차** (GitLab 카드·소유 경계·머지·검수) — agent-skills에는 이 층이 아예 없다(도구·팀 중립이라 이슈 보드도, 모듈 소유권도, 검수자도 없음).
- agent-skills 24종 = **작업 품질 규율** (스펙·TDD·리뷰 축·보안·성능) — 우리 /dev의 5번(구현)·6번(테스트) *안쪽*을 채우는 내용.

**차용 후보 (우선순위순):**
1. **Common Rationalizations 표 형식** — 우리 스킬(/dev·/done)의 "❌ 금지" 목록을 "핑계+반박" 쌍으로 승격. false-done 재발 방지와 직결되고, 비용 0(마크다운 몇 줄).
2. **가정 표면화 블록** ("ASSUMPTIONS I'M MAKING → 고쳐주거나 진행") — /dev 1단계(스펙 확인)의 "질문 목록"에 추가할 출력 형식. 게이트 승인의 질을 올린다.
3. **evals Tier 2 아이디어** — 스킬이 8종을 넘어 자라면 설명 충돌·트리거 누락을 기계로 검사(스크립트는 MIT라 가져다 써도 됨). 지금 8종 규모에선 과잉.
4. **`/ship`의 병렬 fan-out + GO/NO-GO+롤백 양식** — 우리 CI의 AI 리뷰 잡(Playbook §9 #7, P2)을 설계할 때 페르소나 분리(리뷰·보안·테스트)와 병합 양식을 참고.
5. **doubt-driven의 "fresh-context 반박 리뷰어" 절차** — second-brain의 adversarial-review 스킬과 상호 대조해 좋은 쪽 채택.
6. 개별 스킬 파일 직접 참조: `code-review-and-quality`(5축·심각도 라벨), `references/definition-of-done.md`, `security-checklist.md` — 본보기 모듈·CI 설계 시 체크리스트 원천.

**안 가져올 것 / 주의:**
- **메타 라우터(using-agent-skills) 통째 도입 금지** — 우리 starter-kit CLAUDE.md의 "작업 절차(스킬로만)" 절이 이미 라우터다. 둘을 겹치면 §7의 경고 그대로 충돌. 차용은 개별 스킬 내용만.
- 사람 게이트 위치가 다르다: agent-skills는 **단계마다** 사람 체크포인트(개인 워크플로 전제), 우리는 **머지 전 기계 + 배포 후 검수**(Ship/Show — 승인 대기 없음). 우리 철학이 팀 속도 전제이므로 유지 — /dev의 게이트 2개(스펙·go)와 agent-skills의 /spec 4게이트를 섞지 말 것.
- 스킬당 분량이 크다(평균 ~290줄, 6,952줄 총량): 전부 설치하면 트리거 목록만으로도 컨텍스트 압박. 골든 패스 §4.4 "처음부터 스킬 수십 개" 안티패턴에 해당 — 필요한 것만.
- behavioral evals는 아직 provisional(픽스처 없는 케이스는 증거로 못 씀 — 자체 인정, #352).

## 9. 한 문장 평가

Google 엔지니어링 문화(Hyrum's Law·Beyonce Rule·Chesterton's Fence·trunk-based·~100줄 리뷰 단위)를 에이전트 워크플로로 옮긴 **가장 체계적인 공개 스킬 팩**이며, 특히 **anti-rationalization 표준절 + evals 3층**은 우리 레일이 그대로 배울 가치가 있다 — 단, 팀 협업 층(우리 Team Dev Mode)이 없으므로 대체재가 아니라 **/dev 안쪽을 채우는 부품 공급처**로 쓴다.
