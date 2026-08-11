# skills.sh · Everything Claude Code(ECC) 분석 — 참조 정본

> **분석 기준일: 2026-08-11** · 조사 3갈래 병렬: ①ECC 전체 clone 전수 열람(HEAD `9b08128`, 조사 당일 커밋 — 재확인 시 이 해시로 clone) ②skills.sh + CLI(vercel-labs/skills) 소스·상위 스킬 실물 확인 ③커뮤니티 평판·보안 감사 증거 수집.
> **신뢰도 표기**: ✅ = 원문·소스·API 실측 · ◇ = 주장/2차 인용만(중요 결정 전 재확인).
> **용도**: 이 둘을 다시 조사하지 말고 이 문서를 참조. 기판정(`agent-skills-analysis.md`·`ecosystem-analysis.md`·DD-01~05)과 정합 확인 완료 — **뒤집힌 기판정 없음**.

---

## 1. 결론 3줄

1. **ECC(★239k)는 통짜 프레임워크 배제 기판정이 그대로 유효 + 실증 근거가 추가됐다**: 풀 설치 시 스킬 773개의 이름·설명만 ~42.5k 토큰으로 **Claude Code 스킬 목록 예산(컨텍스트의 ~1%)의 약 4배를 초과, 사용자 자신의 프로젝트 스킬까지 라우팅에서 실종**(자기네 이슈 #2694 실측 ✅). GitLab 지원 전무. **단, 훅 스크립트가 전부 Node(=Windows OK)라 파일 단위 채굴 가치는 확실** — 후보 §5.
2. **skills.sh(Vercel)는 발견(discovery)용으로만**: 설치 카운트는 인증 없는 텔레메트리라 조작 트리비얼 ✅, 보안 감사(Gen·Socket·Snyk 3사)는 Trail of Bits가 전부 우회 실증 ✅ → 랭킹·"Safe" 라벨 둘 다 신뢰 신호 아님. **리포를 사람이 직접 읽고 포크해 들여오는 것만 유효한 방어**(ToB 공식 권고).
3. **뜻밖의 수확 2개**: ①CLI `npx skills add`는 **self-hosted GitLab·SSH·로컬 경로 설치를 공식 지원** — 킷 리포를 그대로 소스로 쓰는 "사내 스킬 배포 도구" 후보(P2). ②상위권 스킬 중 mattpocock(tdd 38줄·handoff 16줄·grilling 22줄)·anthropics frontend-design(55줄)은 린 컨텍스트와 같은 결 — 실물 검토 가치.

---

## 2. skills.sh — Vercel 스킬 디렉토리

### 정체·메커니즘 ✅

- 운영 = **Vercel**(2026-01-20 changelog 발표). 인덱스 스킬 **~120만 개**(6월 ~67만 → 2개월 2배). 리더보드 All-Time/Trending/Hot.
- **제출·심사 절차 없음** — `skills` CLI의 익명 텔레메트리(`add-skill.vercel.sh/t`, 인증 없는 HTTP 1건)로 자동 등재·집계. 소스(`src/telemetry.ts`) 확인: **설치 카운트 조작은 curl 반복이면 됨** ✅. 벤더 스킬(lark·azure)이 상위권 대량 점유가 방증.
- 표준 = **agentskills.io**(Anthropic이 만든 Agent Skills 포맷의 오픈 스펙, 채택 40+: Codex·Gemini CLI·Cursor·Copilot 등). skills.sh는 그 위의 배포·랭킹 레이어. **Claude Code 스킬 포맷과 100% 동일 — 우리 킷 스킬은 이미 이 표준**.
- Packs = 스킬 묶음 1명령 설치. 단 **Vercel 계정 종속**(팀 단위 소유) → 우리에겐 불필요(같은 효과 = 킷 리포 + `skills add` 1줄).

### 설치 CLI: vercel-labs/skills ✅

- ★28.6k(7-10 대비 +3k)·v1.5.22(8-05)·8-10 push — 매우 활발. 지원 에이전트 76개.
- 디스크 동작: 정본을 `.agents/skills/`에 복사 → 각 에이전트 폴더(`.claude/skills/` 등)에 **심링크**. `--copy`로 독립 복사(⚠️ **Windows 팀은 심링크 이슈 소지 → `--copy` 검토**). 프로젝트/전역(-g) 스코프.
- **사내 사용 완전 지원**: `npx skills add https://gitlab...` · `ssh://git@사내호스트/...`(git credential 재사용) · `./로컬경로`. 발견 경로에 `.claude/skills/` 포함 → **지금 킷 리포가 그대로 설치 소스가 됨**. 비공개 소스는 리포 식별자 텔레메트리 제외, 완전 차단 `DISABLE_TELEMETRY=1`. CI 친화(`-s <skill> -a claude-code -g -y`).

### 보안 — 랭킹도 감사도 믿지 마라 ✅

- 감사(/audits) = Gen Trust Hub·Socket·Snyk 자동 스캔 합산. CLI도 설치 시 표시하나 **fail-open**(3초 타임아웃, 실패해도 설치 진행). 다수 "Pending". 공식 문서도 "보장 불가, 직접 검토하라".
- **Trail of Bits(2026-06-03) 3사 전부 우회 실증**: .docx(zip) 내 악성 은닉 · 소스 깨끗 + **컴파일된 .pyc에 env 탈취**(3사 모두 "safe" 판정) · 개행 10만 개로 스캐너 절단 · "사내 npm 미러 설정" 위장 인젝션. 결론 원문: "어떤 스캐닝도 악성 스킬을 신뢰성 있게 못 잡는다 — **신뢰 가능한 컬렉션을 자체 큐레이션하라**". Snyk 별도 연구: ClawHub 표본 36%에서 프롬프트 인젝션.
- → 운영 규칙: **skills.sh에서 찾은 스킬은 리포를 열어 읽고, 쓸 것만 킷/사내 리포로 포크해 들여온다**(외부 직설치 금지). 우리 "외부 SaaS 배제·à la carte" 철학과 일치.

### 상위 스킬 실측 (All-Time, 설치 수 표기 기준) ✅

| 스킬 | 저자 | 실물 | 판정 |
|---|---|---|---|
| find-skills (2.9M) | vercel-labs | 141줄, 스킬 검색 도우미 | 사실상 skills.sh 마케팅 — 불요 |
| grill-me (824K)→grilling | mattpocock | 7줄 셸 + 본체 22줄 — 계획을 라운드별 집요 인터뷰 | **/design·/card의 질문 게이트와 비교 가치** |
| frontend-design (765K) | **anthropics 공식** | 55줄 단일 파일 — "AI풍 디자인" 회피 지침, 밀도 높음 | **/ui·시안 흐름 보강 후보** |
| tdd (654K) | mattpocock | 38줄 + 참조 2파일, seam 기반 TDD | **품질 최상 — /dev 안쪽 부품 후보** |
| handoff (564K) | mattpocock | 16줄, 세션 인수인계 문서 생성 | **/log·HANDOFF 관행과 직접 비교** |
| improve-codebase-architecture (677K) | mattpocock | 71줄, 얕은 모듈 탐지→HTML 리포트 | ⚠️ Tailwind/Mermaid CDN 지시(폐쇄망 주의) |

- mattpocock 스킬군(리포 ★213k) 구조 = "짧은 셸(7~16줄) + 참조 문서 분리" — **우리 밀도 규약과 같은 결**. 단 상호 참조 많음(grill→grilling, tdd→code-review, CONTEXT.md 전제) → 낱개보다 세트 전제 설계임을 감안해 발췌.
- 신뢰 축 정리: 포맷 정본 = agentskills.io / 큐레이션 = anthropics/claude-plugins-official(39개, ECC 미등재 ✅) / 발견 = skills.sh. claudemarketplaces.com류는 제3자 SEO — 발견용으로만(기판정 유지).

---

## 3. ECC (affaan-m/ECC) — 실물 검토

### 메타·건강 ✅

- ★239,363 · fork 36.3k · MIT · npm `ecc-universal` v2.2.0 · 생성 2026-01-18 → 7개월 24만 스타(폭발 구간 1~4월 = 저자 X 바이럴 스레드 90만 뷰◇, 6월 이후 감속). 문서 15개 언어(ko-KR 64파일).
- 커밋 2,378 중 저자 64% = **실질 단일 유지자**(버스 팩터) ✅. 단 조사 당일에도 커밋 — 방치 아님. HN 대형 스레드 무(제출 전부 2~5포인트) — 무대는 X/유튜브/SEO 블로그.
- **Anthropic 공식 무관계** ✅: 공식 마켓 미등재(marketplace.json 직접 확인), 연결고리는 해커톤 우승뿐. "Anthropic 해커톤 우승자"는 행사 수상이지 제품 보증 아님. 저자 스타트업(Itô) 연동이 2.1에 들어가기 시작 — 중립적 기록.
- 인벤토리 실측: **agents 68 · skills 285 · commands 94 · 훅 등록 22건(스크립트 52개) · rules 122파일 — README 주장과 일치, 숫자 부풀림 없음** ✅. 단 하니스별 사본(`.cursor/` `.kiro/`…)까지 합치면 SKILL.md 773개로 드리프트 실재(자인, doctor.js로 관리 시도).

### 실사용 평판 — 핵심 증거 3개

- **컨텍스트 비대(✅ 제3자 실측, #2694 open)**: 773 스킬의 frontmatter만 ~17만 자 ≈ 42.5k 토큰 — 스킬 목록 예산(~1%)의 4배 초과 → 목록이 잘려 **ECC 자기 스킬 + 사용자 프로젝트 커맨드까지 라우팅 실종**. 비교: superpowers 14스킬 + 프로젝트 커맨드 전부 합쳐 ~1.6k 토큰. **"스킬 축적은 반패턴" 규약의 최상급 반면교사 표본 — 인용용**.
- **Claude Code 업데이트 파손(✅ #1454)**: 2.1.x 스키마 변경으로 **훅 27개 전원 사망** — 자동화 계층이 조용히 무력화된 채 상당 기간 배포. + 차단형 훅이 자기네 래퍼 버그로 무력(#2697 — `run-with-flags.js`가 exitCode 유실), matcher `*` 훅 조용히 탈락(#2748), `ecc status` 상시 오보(#2750). **개별 스크립트는 좋아도 그들의 래퍼 체인은 버린다**.
- **제3자 보안 감사(✅ dev.to/ClawGuard, 2026-06)**: 본체는 트로이목마 아님. 단 설치가 `~/.claude/` **전역** 훅 기록(모든 세션에서 실행), 에이전트 75%가 Bash 권한, 서명 없는 자동 업데이트, 자동 로드 513파일 = 인젝션 표면. **야생 악성 클론 실재**(가짜 다운로드 페이지 + LuaJIT 드로퍼). 기업 차단 사유 4종이 이슈로 공식 제기(#2502).
- 긍정 측: 수치 딸린 before/after는 **유통 자체가 안 됨**(조사 실패 아니라 부재 ◇). 실사용자가 실명 지목한 부품 = code-review 에이전트(신뢰도 80% 필터), `/strategic-compact`, `/consult`. "설치가 아니라 패턴 채굴이 실제 소비 형태"라는 관찰이 커뮤니티 회의론자한테서도 나옴.

### 메커니즘 실물 (차용 판단의 근거)

| 층 | 실물 | 평가 |
|---|---|---|
| 세션 지속 | `scripts/hooks/session-end.js`(Stop마다 요약 축적)·`pre-compact.js`·`session-start.js`(**재주입 8,000자 하드캡 + 항목 상한 instinct 6·learned 6·각 220자 + 잘림 마커**) | ★설계가 밀도 예산 철학과 정합 — §5-1 |
| 지속학습 v2 | 훅이 전 툴콜을 observations.jsonl 기록("스킬은 50~80% 발동, 훅은 100%") → 백그라운드 Haiku가 instinct(trigger/confidence/evidence YAML) 승격 → `/evolve` | 파이프라인은 과잉(기본 비활성인 데 이유 있음, #2746 글로벌 오염 버그). **스키마 형식만 참고** |
| 규율 훅 | `block-no-verify.js`(508줄 — `--no-verify`·`-n`·`core.hooksPath` 우회 차단) · `config-protection.js`(린터 설정 약화 차단) · `gateguard-fact-force.js`(41KB — 파일별 첫 수정 차단, importer·스키마·지시 인용 요구. "'확실해?'에 LLM은 항상 '응' — 조사 행위가 인지를 만든다") · `pre-bash-commit-quality.js` | **"규칙의 기계화" 그 자체** — §5-2·3·5 |
| 컨텍스트 관리 | `suggest-compact.js`(transcript usage 레코드 합산 = **실측 기반** `/compact` 타이밍: 200k 창 160k 도달 시) · `context-budget` 스킬(에이전트>200줄·스킬>400줄·룰>100줄·CLAUDE.md 체인>300줄·MCP 툴당 ~500토큰이면 비대) | 실측 컴팩션 = 저장소 최고 독창 메커니즘. 수치 기준은 density-check와 직교 — §5-4·7 |
| 검증 | verification-loop(6단계 빌드→…→diff) · **tdd-workflow의 "플랜 = 비신뢰 입력" 절**(플랜 내 명령 허용목록 대조·인젝션은 데이터로 기록) · plan-canvas(루프백 :4517, 사람이 브라우저에서 요소 찍어 주석+Approve — 의존성 0) | §5-8·9 |
| 룰 | 밀도 규율 없음 — 대신 모듈식 프로파일(minimal~developer)로 후퇴. rules-core만 545줄/17.3KB | 우리 방식(밀도 예산)이 더 앞섬 — 차용 없음 |
| 크로스 하니스 | 단일 소스 아님 — 하니스별 디렉터리 병행 유지(사본+변환 스크립트) = 드리프트 구조적 | 차용 없음 |
| AgentShield | **이 리포에 없음** — 외부 npm `ecc-agentshield` 래퍼. CLAUDE.md(시크릿·인젝션)·settings.json(과도 allowlist)·mcp.json·hooks·agents 스캔. "1282 tests·102 rules"는 미검증 ◇ | npx 단독 실행 → GitLab CI 이식 가능 — §5-6 |
| GitLab | **전무**(git-workflow 스킬에 문자열 한 줄뿐). gh·GitHub Actions 전제 | 플랫폼 결합부는 전부 자체 유지 |

---

## 4. 우리 킷과의 관계

- **층 진단**: ECC = "개인 파워유저의 백과사전"(범용 규율 + 하니스 최적화), 우리 = "팀 협업 절차 + 린 컨텍스트". agent-skills 때와 동일하게 **대체재가 아니라 부품 공급처** — 단 agent-skills보다 신뢰도가 낮아(단일 유지자·래퍼 버그·감사 지적) **파일 단위 채택 시 반드시 자체 재검증**(G류 함정 등재 전제).
- ECC #2694는 CLAUDE.md "규칙 축적 반패턴"·골든 패스 §4.4("처음부터 스킬 수십 개")의 **외부 실증 사례**로 인용 가치 — 스킬이 많아지면 라우팅이 조용히 죽는다는 걸 수치로 보여줌.
- Prisma AI 차단(G-10)·DD-04(미리보기 게이트)처럼 "파괴적=사람" 철학과 겹치는 장치가 ECC에도 있음(gateguard·block-no-verify) — 방향 일치 확인.

## 5. 차용 후보 (우선순위순 — 전부 "파일/아이디어 단위", 통짜 없음)

1. **세션 지속 훅 3종의 설계 패턴** (`session-end/pre-compact/session-start.js`): Stop마다 기계 요약 축적 → 시작 시 **하드캡(8,000자)+항목 상한+잘림 마커** 재주입. HANDOFF 커밋 문화의 자동화 보완재. 전부 Node = Windows OK. 코드보다 설계 차용.
2. **`block-no-verify.js`** — 단독 508줄, 기존 check-push.sh 옆에 추가 등록만. 컨텍스트 비용 0. 셀프 머지 체제에서 "훅 우회 금지"의 기계화.
3. **`config-protection.js`** — 린터/포매터 설정 약화 차단. ⚠️ 그들의 래퍼(#2697) 없이 **스크립트만 직접 등록**.
4. **`suggest-compact.js`** — transcript usage 실측 기반 /compact 제안. 단독·의존성 0.
5. **gateguard 개념** — "/fix·/dev의 사전조사(카드 읽기·영향 파악)를 훅으로 강제"의 참고 사례. 41KB 원본은 과잉 — 아이디어만 경량 재구현 대상.
6. **`npx ecc-agentshield scan`을 GitLab CI 잡으로** — 우리는 settings.json·훅·CLAUDE.md를 커밋하므로 스캔이 직접 유효. ⚠️ 외부 npm — 버전 핀 + 1회 소스 검토 후(§2 보안 교훈 그대로 적용). ecosystem-analysis의 "보안 스캔 층 갭(P1~P2)"을 메우는 또 하나의 선택지(공식 /security-review와 대상이 다름 — 이건 **설정 파일** 스캔).
7. **context-budget 수치 기준 흡수** — density-check(줄당 문자)에 직교 축(파일당 줄수·MCP 툴당 토큰)만 추가 검토.
8. **plan-canvas** — 비개발 기획/검수자가 브라우저에서 계획·HTML을 찍어 주석+승인, 의존성 0·루프백 전용·Node. 시안 허브/검수 흐름의 시각적 보완 후보(⚠️ #2702 localStorage 버그).
9. **tdd-workflow의 "플랜 = 비신뢰 입력" 체크리스트** — 카드 본문·플랜 파일을 스킬 입력으로 넘기는 우리 구조에 인젝션 방어 문안으로 이식.
10. **instinct 스키마**(trigger/confidence/evidence/scope) — AI-CONTEXT·/log 항목 형식 참고용만.
11. **skills CLI를 사내 스킬 배포 도구로**(P2) — 킷 리포를 `npx skills add ssh://사내GitLab/...`로 설치. 지금은 "clone이 곧 배포"(DD-02)라 불요하나, **킷 스킬을 여러 repo에 배포하는 시점**에 재검토(Windows는 `--copy`).
12. **mattpocock tdd/handoff/grilling + anthropics frontend-design 실물 발췌 검토** — /dev 안쪽·/log·/design 질문 게이트·/ui 각각의 비교 대상.

## 6. 배제·주의 (명시)

| 대상 | 이유 |
|---|---|
| ECC 통짜 설치(플러그인 포함) | 스킬 예산 4배 초과 실측(#2694)·전역 훅·자동 업데이트 — 기판정 강화 |
| ECC 오케스트레이션 층(68 에이전트·orch-*·AGENTS.md) | 제2의 메타 라우터 — "라우터는 하나"(agent-skills §7) 위반 |
| unified-memory / Memory Vault | 전역 npm 런타임 + MCP 상주 전제 — 인프라 과잉 |
| continuous-learning 파이프라인 | 기본 비활성·글로벌 오염 버그(#2746)·Windows 경로 미검증 |
| run-with-flags 등 래퍼 체인·tmux 훅 | 차단 무력화 버그(#2697)·Windows 불가 |
| GitHub 전제 전부(github-ops·Actions·gh 의존) | 우리는 GitLab |
| skills.sh 랭킹·"Safe" 라벨을 채택 근거로 쓰기 | 조작·우회 실증 — 리포 직접 읽기만 유효 |
| skills.sh Packs | Vercel 계정 종속 |
| 외부 스킬 직설치(포크 없이) | ToB 권고 위반 — 읽고 포크해 들여온다 |

## 7. 원출처 (재확인용)

- ECC: github.com/affaan-m/ECC (`9b08128`) · 이슈 #2694(스킬 예산)·#1454(훅 전멸)·#2697(래퍼)·#2502(기업 차단 사유) · 보안 감사: dev.to Jörg Michno "We audited the viral 213k-star ECC repo"(2026-06-12)
- skills.sh: skills.sh(/audits·/packs·/docs) · github.com/vercel-labs/skills · agentskills.io · Vercel changelog 2026-01-20
- 보안: Trail of Bits "The sorry state of skill distribution"(2026-06-03) · Snyk ToxicSkills
- 스킬 실물: github.com/mattpocock/skills · github.com/anthropics/skills · anthropics/claude-plugins-official(공식 큐레이션 39개)
- 조사 시 clone은 세션 스크래치패드(휘발) — 재검토 시 위 해시로 재clone.
