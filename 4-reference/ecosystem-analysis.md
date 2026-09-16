# Claude Code 생태계 분석 — 내장 기능·공식 플러그인·커뮤니티·MCP (2026-07-10)

> **목적**: "우리가 만든 스킬 8종이 이미 내장된 것과 중복인가? 활용 안 한 내장 기능이나 시중 플러그인은 없나?"를 전수 대조.
> **조사 3갈래**: ①공식 문서 기준 내장 기능 전수 인벤토리 ②도입 판단 직결 항목의 원문 정밀 재검증 ③커뮤니티 생태계 웹 조사(GitHub 스타·최근 커밋 실측).
> **신뢰도 표기**: ✅ = 공식 문서 원문 재확인됨 · ◇ = 1차 조사만(중요 결정 전 해당 페이지 재확인 권장).
> 스킬 팩 4종(addyosmani/agent-skills·anthropics/skills·GitLab 공식 플러그인·pr-review-toolkit)은 `agent-skills-analysis.md`에서 기판정 — 여기서 재론하지 않는다.

---

## 1. 결론 3줄

1. **중복 제작 없음.** 우리 8종(/todo /dev /fix /done /module /docs /change /log)은 사내 GitLab·카드 흐름·게이트에 맞춘 것이라 내장/시중 어느 것도 대체하지 못한다. 유일한 접점은 /done이 내장 `/code-review`를 *호출*하는 구조 — 올바른 재사용이다.
2. **실질 갭은 3개뿐**: ①구조화 GitLab 조작(MCP — glab 텍스트 파싱 대비 오류율↓) ②보안 *스캔* 층(`/security-review` — security-guidance는 *가이드* 층) ③CLAUDE.md 자체의 유지관리(claude-md-management). 전부 P1~P2 후보이지 필수는 아님.
3. **즉시 킷에 반영한 것 2건**: Windows `CLAUDE_CODE_GIT_BASH_PATH`(우리 check-push.sh가 bash 훅이라 미설정 시 조용히 죽는 함정), 내장 명령 치트(/rewind 등)를 ONBOARDING에 추가. (§8 반영 내역)

---

## 2. 내장 슬래시 명령·번들 스킬 ↔ 우리 킷 대조

### 이미 활용 중 (킷에 반영돼 있음)

| 내장 기능 | 우리 킷에서의 위치 |
| --- | --- |
| `/code-review` ✅ | /done 4단계가 호출 (diff 리뷰, Important 이상 수리 후 재검증) |
| 세션 이름·재개 (`claude -n` / `--resume`) | "이슈 하나 = 세션 하나" 규칙 (CLAUDE.md·ONBOARDING) |
| `/compact` + SessionStart(compact) 훅 | 압축 직후 핵심 규칙 자동 리마인드 (settings.json) |
| permissions allowlist/deny·acceptEdits | settings.json (Windows에선 이게 유일한 로컬 강제층) |
| security-guidance 플러그인 ✅ | enabledPlugins로 커밋 (편집·커밋 시 보안 가이드 층) |
| PreToolUse 훅 | check-push.sh (공통 영역 push 전 확인 요구) |

### 알아두면 좋은 내장 — ONBOARDING에 치트 추가함

| 명령 | 검증 내용 | 판정 |
| --- | --- | --- |
| `/rewind` ✅ | **파일+대화 체크포인트 되돌리기** (3모드: 둘다/대화만/파일만). ⚠️ **Bash로 한 변경(rm·mv 등)은 추적 안 됨**, git과 무관한 로컬 세션 체크포인트 | AI가 잘못 뒤엎었을 때 첫 수단 — 전원 알아야 |
| `/context` ◇ | 토큰 사용량·비용 시각화 | 긴 세션 관리용 |
| `/simplify` ✅ | 번들 스킬 — 정리·재사용·효율화만 (버그 검사 없음) | 리팩토링 카드에서 유용 |
| `/security-review` ✅ | 내장 명령 — git diff 보안 검사 (스캔 층) | 인증·업로드 등 민감 카드 마무리 때 |
| `/batch` ✅ | 번들 스킬 — 5~30개 파일 독립 worktree 병렬 변경 | 대량 마이그레이션·일괄 수정 때. ⚠️ 모듈 소유 경계를 넘는 batch는 금지 규칙과 충돌하니 자기 모듈 안에서만 |

### 팀에 무관·부적합 판정

| 기능 | 판정 이유 |
| --- | --- |
| `/schedule`(Routines) ✅ | **클라우드(Anthropic 인프라) 실행** — 사내 GitLab 중심 환경에 부적합. 주기 작업은 GitLab CI 스케줄로 |
| Agent Teams ✅ | 실존(v2.1.178+)하나 **실험 단계**(환경변수 opt-in·세션 재개 미지원) — 프로덕션 비권장, 관찰만 |
| `/review`(GitHub PR)·commit-commands | GitHub 지향 — 우리는 GitLab MR(/done이 커버) |
| `/loop` `/goal` `/fork` `/export` `/statusline` 등 ◇ | 개인 취향 영역 — 팀 표준으로 강제할 것 없음 |

### headless `claude -p` — GitLab CI 공식 지원 확인 ✅

**공식 문서에 GitLab CI/CD 가이드가 별도로 존재**(gitlab-ci-cd 페이지): `claude -p "..." --permission-mode acceptEdits --allowedTools ...` 패턴, `ANTHROPIC_API_KEY` 마스킹 변수 필요(Bedrock/Vertex OIDC 대안 있음). → 리더 가이드 Day 4의 "MR AI 리뷰 잡" P2가 공식 지원 경로임이 확인됨. 러너에서 api.anthropic.com 통신 가능해야 한다는 전제는 동일.

---

## 3. 공식 마켓플레이스 (claude-plugins-official — ★31.9k, 200+ 플러그인)

| 카테고리 | 내용 | 우리 판정 |
| --- | --- | --- |
| **LSP 코드 인텔리전스** (11개 언어) ✅ | typescript-lsp·pyright-lsp·gopls-lsp 등. **각 언어 서버 바이너리 별도 설치 필요**. Windows 동작은 언어별 미보장 ◇ — 설치 후 `/plugin` Errors 탭 확인 | **P2** — 스택 확정(Day 1) 후 해당 언어 것만. grep/read 절감 + 편집 후 자동 타입에러 보고 |
| **MCP 번들** — `gitlab` 포함 ✅ | github·gitlab·atlassian·linear·notion·figma·slack·sentry 등 | `gitlab`: 실존하나 **self-hosted 설정법 문서 미기재** — 설치 후 사내 인스턴스 실테스트 필요 ◇. 나머지 SaaS 계열은 무관 |
| **보안** — security-guidance ✅ | 편집→턴 끝→커밋 3층 보안 *가이드* | **사용 중** (킷 settings.json) |
| **워크플로** — commit-commands·pr-review-toolkit | GitHub PR 지향 | 불필요(GitLab)·기판정(P2) |
| **출력 스타일** — explanatory·learning | 교육적 설명 모드 | 신입 온보딩 때 개인 선택지로만 |
| **개발 도구** — plugin-dev·agent-sdk-dev·skill-creator | 플러그인/스킬 제작 지원 | 리더가 스킬 다듬을 때 참고 |

공식 관리 커뮤니티 마켓(claude-plugins-community, 400+, 자동 검증 통과분)도 존재 — `/plugin marketplace add`로 추가.

---

## 4. 커뮤니티 생태계 (GitHub 실측 기준)

### 주요 디렉터리 (발견용 — 판정은 원본 repo로)

| 이름 | 규모 | 용도 |
| --- | --- | --- |
| hesreallyhim/awesome-claude-code | ★49.7k | 사실상 표준 색인 |
| vercel-labs/skills (`npx skills`) | ★25.7k | 크로스 에이전트 스킬 설치 CLI |
| davila7/claude-code-templates | ★28.6k | 템플릿·컴포넌트 브라우징 |
| claudemarketplaces.com 등 웹 애그리게이터 | 자칭 수만 개 | SEO성 — 발견용으로만 |

### 분야별 판정 (상세 근거는 조사 원문 — 여기선 결론만)

| 분야 | 최유력 후보 | 판정 |
| --- | --- | --- |
| git 워크플로 | obra/superpowers (생태계 최대 스킬 프레임워크) | 통짜는 /dev와 정면 겹침 — **개별 스킬 채굴만 P2** (worktree 격리·2단계 리뷰: 스펙 준수→코드 품질·병렬 에이전트 디스패치) |
| 코드 리뷰 | code-review(공식)·coderabbit(SaaS) | 전자는 GitHub 지향, **후자는 사내 코드 외부 전송이라 배제** |
| 테스트 | nizos/tdd-guard (★2.25k, 활발, Node 기반=Windows OK) | **P2** — 훅으로 TDD 실시간 강제. 강력하나 팀 전원 작업 방식 변경이라 합의 후 파일럿 |
| 문서 동기화 | claude-md-management (공식) | **P2** — CLAUDE.md 품질 감사·세션 학습 캡처. /docs(코드↔문서)와 층이 달라 겹침 없음 |
| 이슈 트래커 | — | SaaS 계열 전부 무관 (self-hosted GitLab은 §5 MCP로) |
| 세션 로그·핸드오프 | thedotmack/claude-mem (★86.7k, 압도적 1위) | **P2** — 개인·자동·로컬 DB라 /log(팀·수동·커밋)와 층이 다름. 데이터 로컬 유지=사내 OK. 컨텍스트 주입 오버헤드 실측 후 |
| 보안 스캔 | anthropics/claude-code-security-review (공식) | **P1~P2** — `/security-review` 명령은 로컬 즉시 사용 가능, GitHub Action 부분은 GitLab CI로 이식 필요. ⚠️ 프롬프트 인젝션 미방어 → 신뢰된 MR만 |
| 통짜 프레임워크 | BMAD-METHOD(★50.3k)·claude-flow(★63.8k)·SuperClaude | **전부 불필요** — 우리 프레임워크와 정면 경쟁, 전환 비용 > 이득. 스타 수 ≠ 우리 적합도 |
| 핸드오프 플러그인 | Remember(공식)·agent-handoff·cc-sessions | 불필요 — /log·HANDOFF 관행이 커버. cc-sessions는 7개월 커밋 정체 |
| 패턴 참고 | EveryInc compound-engineering (★23.0k) | 도입 아닌 **참고** — "교훈→docs/solutions→다음 계획 입력" 루프는 우리 retro 사상과 동형 |

---

## 5. MCP 서버 (팀 개발 직결만)

| 서버 | self-hosted | 요점 |
| --- | --- | --- |
| **zereight/gitlab-mcp** (★2.0k, 활발 — 커뮤니티 GitLab MCP 사실상 표준) | **지원** (`GITLAB_API_URL`+PAT · OAuth · 무료판/사내 설치 가능) | **도구 261개**(2026-09-16 재조사 · 2026-07 조사 때 170개) — MR·이슈·파이프라인·위키·릴리스·워크아이템 등. `GITLAB_TOOLSETS`·`GITLAB_TOOLS`·`GITLAB_DENIED_TOOLS_REGEX` 로 고르고 `GITLAB_PERMISSION_MODE`=`readonly`/`modify`/`full` 로 묶는다. glab 텍스트 파싱보다 구조화·안정적 → /todo·/done 오류율↓ 후보. ⚠️**받쳐 주는 최소 GitLab 버전 표가 없다** — 구버전 인스턴스는 실테스트 1회로만 확인된다. ⚠️**전부 켜면 컨텍스트 낭비** — 공개 측정들이 MCP 를 CLI 대비 토큰 **4~32배**로 보고한다(도구 정의가 호출 전부터 상주). ⚠️**사내 PAT 를 외부 npm 패키지에 넘긴다**(context7 행과 같은 결의 고지 대상) |
| GitLab 공식 MCP (인스턴스 내장 · 18.3 실험 → **18.6+ 베타**) | 지원하나 **Premium/Ultimate + Duo 필요** | 사내 GitLab이 조건 충족하면 zereight 대체 검토. ★**조건은 `glab api version` 한 줄로 잰다**(`version`·`enterprise`) — 2026-09-16 실측 사내 인스턴스 = **16.4.1 · `enterprise:false`** 라 **두 칸 다 미달·현재 불가** |
| postgres-mcp·sentry-mcp(self-hosted 지원)·Figma Dev Mode MCP | 각각 조건부 | 해당 인프라를 실제 쓰는 시점에만 |

---

## 6. Windows 전원 팀 — 도입 전 필수 확인 ★

- **bash 스크립트 훅을 쓰는 플러그인은 Windows에서 잘 깨진다** (공식 이슈 다수: 백슬래시 경로 오해석 #18527·#21878, **`CLAUDE_CODE_GIT_BASH_PATH` 미설정 시 cmd.exe로 실행돼 실패 #16602**, 숨은 jq 의존 #14817).
- **우리 킷의 check-push.sh도 bash 훅이다** → 전원 시스템 환경변수 `CLAUDE_CODE_GIT_BASH_PATH`(보통 `C:\Program Files\Git\bin\bash.exe`) 표준 설정. **ONBOARDING 첫날 셋업에 반영됨.**
- 플러그인 채택 기준: **Node/바이너리 기반 우선**(tdd-guard·claude-mem·npx형 MCP는 안전), bash 훅 플러그인은 파일럿 1인 검증 후 배포.
- Chrome 브라우저 통합은 Windows 미지원(WSL 포함) ✅. LSP는 언어별 Windows 바이너리 확인.

---

## 7. 최종 판정표

| 등급 | 대상 | 이유 한 줄 |
| --- | --- | --- |
| **즉시 (킷 반영됨)** | `CLAUDE_CODE_GIT_BASH_PATH` 셋업 | 우리 bash 훅이 조용히 죽는 함정 차단 |
| | 내장 명령 치트 (/rewind·/context·/simplify·/security-review·/batch) | 이미 깔려 있는 도구를 몰라서 못 쓰는 낭비 제거 |
| **P1 (골격 구축 때 리더가 결정)** | zereight/gitlab-mcp | /todo·/done의 glab 파싱을 구조화 도구로 — 사내 인스턴스 실테스트 1회 후. ⚠️**2026-09-16 재조사로 등급이 내려갔다 — 현재 권고는 «그대로 둔다»**: 공식판은 `18.6+`·Premium/Ultimate·Duo 라 사내(`16.4.1`·무료판)에서 **불가** · 커뮤니티판은 **최소 버전 표가 없고** 도구 **261개** · 이미 `glab` 로 도는 절차(킷 기준 스킬 19개·호출 141곳)를 갈아타는 비용이 든다 |
| | `/security-review`의 CI 이식 (MR AI 리뷰 잡과 함께) | 가이드 층(security-guidance)에 없는 스캔 층 — 공식 GitLab CI 가이드 존재 확인됨 |
| **P2 (운영하며 필요 시)** | LSP 플러그인(스택 언어) · claude-md-management · tdd-guard · claude-mem · superpowers/compound 패턴 채굴 · GitLab 공식 MCP(티어 충족 시) | 각각 §3~4 참조 |
| **불필요·배제** | 통짜 프레임워크(BMAD·claude-flow 등) · GitHub 지향(commit-commands·Remember·agent-handoff) · 외부 SaaS(coderabbit·aikido·42crunch — **사내 코드 유출**) · cc-sessions(정체) · doc-sync류(성숙도↓) · /schedule(클라우드) · Agent Teams(실험) | 표 각 행 참조 |

## 8. 이번에 킷에 반영된 것

1. `3-starter-kit/ONBOARDING.md` 첫날 셋업 — Windows `CLAUDE_CODE_GIT_BASH_PATH` 환경변수 단계 추가 (훅 무음 실패 차단)
2. `3-starter-kit/ONBOARDING.md` 명령 표 아래 — 내장 명령 치트 1줄 추가
3. `3-starter-kit/README.md` 사용법 4단계 — Windows 환경변수 언급
4. 리더 가이드 Day 4 — Windows 주의 ③→④ 확장(환경변수), P2 블록에 gitlab-mcp·/security-review CI 이식·LSP를 이 문서 포인터와 함께 추가
5. `/done` 스킬 4단계 — 민감 diff(인증·권한·업로드·비밀값·외부 입력)면 `/security-review` 병행 실행 (스캔 층을 후보가 아닌 절차로 승격)
6. `3-starter-kit/README.md` — "도입 후보" 표 신설: 각 후보의 켜는 법 1줄 + 기본 미포함 이유 (리더가 재조사 없이 켤 수 있게)
