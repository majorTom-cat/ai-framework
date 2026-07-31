# Claude Code 공식 문서 전체 분석 — 참조 정본

> **분석 기준일: 2026-07-10** · 출처: https://code.claude.com/docs (34개 페이지 전수 + best-practices)
> **용도:** 방법론·설계를 추가/변경할 때 매번 재분석하지 말고 이 문서를 먼저 참조.
> **주의:** Claude Code는 기능 변화가 빠르다 — 이 문서로 방향을 잡고, **중요 결정 전엔 해당 페이지 하나만 재확인**(전체 재분석 불필요). 문서 인덱스: https://code.claude.com/docs/llms.txt

---

## 1. 핵심 원칙 (best-practices 페이지의 뼈대)

- **컨텍스트 창이 가장 중요한 자원** — 차면 성능이 떨어지고 규칙을 잊는다. 모든 모범 사례가 여기서 파생.
- **검증 루프를 AI에게 줘라**: 테스트·빌드·스크립트 등 "통과/실패 신호"가 있으면 AI가 스스로 반복 수정. 없으면 사람이 검증 루프가 된다. 증거(테스트 출력·스샷)를 제시하게 하라.
- **탐색 → 계획 → 구현 → 커밋** 4단계. 단, diff를 한 문장으로 설명 가능하면 계획 생략.
- **구체적 프롬프트**: 파일 지목, 제약 명시, 기존 패턴 참조("HotDogWidget.php를 보고 따라 해").
- 자주 교정하게 되면 → `/clear` 후 배운 것을 반영한 더 나은 프롬프트로 재시작 (2회 교정 실패가 기준).
- 흔한 실패: 잡탕 세션(무관한 작업 섞기), 반복 교정, 비대한 CLAUDE.md, 검증 없는 신뢰, 무한 탐색.

## 2. 컨텍스트·메모리 (memory · claude-directory · large-codebases)

**CLAUDE.md 로딩 규칙 (정확한 동작):**
- 로드 순서: 관리형(managed) → `~/.claude/CLAUDE.md` → 프로젝트 루트 `./CLAUDE.md`(또는 `.claude/CLAUDE.md`) → `CLAUDE.local.md`. 전부 **연결(concatenate)**되며 서로 덮어쓰지 않음 → 모순되면 임의로 하나를 고름(중복 금지 이유).
- 상위(조상) 폴더의 CLAUDE.md는 시작 시 전부 로드. **하위 폴더 CLAUDE.md는 그 폴더 파일을 Read할 때만** 로드 — 쓰기 전용 작업에선 안 뜨고, **compaction 후 재주입 안 됨**(루트만 재주입).
- 권장 크기: **파일당 200줄 이하.** 길면 규칙이 소음에 묻힘.
- `@path/파일` 임포트 문법: 참조 파일을 통째로 로드(최대 4단계 재귀). **AGENTS.md 혼용 패턴 = CLAUDE.md 첫 줄에 `@AGENTS.md`** (역방향 아님). 임포트는 컨텍스트 절약이 안 됨(전부 로드).
- HTML 주석 `<!-- -->`은 주입 전 제거됨 — 관리자 메모용 공짜 채널.

**`.claude/rules/` (경로 규칙):**
- `paths:` frontmatter(글롭, `src/**/*.{ts,tsx}` 형식)가 있으면 **그 경로 파일을 만질 때(읽기·쓰기 모두) 자동 로드**. 없으면 시작 시 로드. 실행 위치 무관 → 모듈 규칙에 폴더 CLAUDE.md보다 우월.

**auto memory:** 기본 켜짐, `~/.claude/projects/<repo>/memory/` — **개발자 개인·PC 로컬**(팀 공유 안 됨). 팀 지식은 커밋된 CLAUDE.md/rules로 승격해야 함.

**커밋 지도**: 커밋 O — `CLAUDE.md`, `.claude/settings.json`, `.claude/rules|skills|agents|hooks`, `.mcp.json`(repo 루트), `.claude/agent-memory/`. 커밋 X — `settings.local.json`, `CLAUDE.local.md`, `~/.claude.json`.

**대형 repo:** ⚠️ **프로젝트 `.claude/settings.json`은 "켠 폴더"의 것만 적용** — 부모에서 상속 안 됨 → "항상 repo 루트에서 실행" 규칙의 근거. `permissions.additionalDirectories`는 파일 접근만 주고 그 폴더의 CLAUDE.md/rules는 로드 안 함.

**진단 명령:** `/context`(컨텍스트 내용물) · `/memory`(로드된 규칙) · `/permissions`(발효 중 권한) · `/hooks` · `/doctor` · `claude --safe-mode`(전 커스터마이즈 끄고 bisect).

## 3. 설정·권한 (settings · permissions · permission-modes)

**설정 우선순위(높→낮):** managed → CLI 인자 → `.claude/settings.local.json` → `.claude/settings.json`(프로젝트, 커밋) → `~/.claude/settings.json`(개인). 단 **권한 규칙은 병합**되고 deny가 어느 층에 있든 이김.

**권한 문법:**
- 3목록 `allow`/`deny`/`ask`. 평가: **deny → ask → allow, 먼저 맞는 것 승** — deny에 예외 불가(넓은 deny가 좁은 allow를 이김). 허용 목록은 포지티브로 설계.
- `Bash(npm test *)` — 공백+`*`는 단어 경계, `*`는 공백 포함 임의 문자. 복합 명령(`&&`,`;`,`|`)은 **각 서브명령이 독립적으로** 매칭돼야 함. `timeout`·`nice` 등 래퍼는 벗겨서 매칭, `npx`·`docker exec`는 안 벗김.
- 경로 규칙(gitignore 문법): `//abs`, `~/`, `/settings파일기준`, `상대`. **Windows 경로는 POSIX 정규화** (`C:\x` → `/c/x`, 전 드라이브는 `//**/...`).
- ⚠️ **워크스페이스 신뢰**: 커밋된 settings의 allow·additionalDirectories는 각자 **최초 1회 신뢰 다이얼로그 수락 후** 발효 (deny/ask는 무조건 적용).
- ⚠️ `Bash(rm *)` 류 deny는 **문자열 매칭**이라 `/bin/rm`·`find -delete`로 우회됨 — 강한 보장은 PreToolUse 훅/샌드박스.
- 보호 경로(`.git`, `.claude`, lockfile류)는 어떤 allow로도 자동 승인 불가.
- `/fewer-permission-prompts` — 사용 기록에서 허용 목록 자동 생성.

**모드:** `default`/`acceptEdits`/`plan`/`auto`/`dontAsk`/`bypassPermissions`. 
- `acceptEdits` — 파일 편집+기본 파일명령 자동 승인. 팀 기본값으로 적합, `"permissions": {"defaultMode": "acceptEdits"}`.
- `auto` — 분류기 모델이 위험한 것만 차단(기본 브랜치 push는 허용, 강제 push·prod 배포·시크릿 유출은 차단). ⚠️ **프로젝트 settings의 `defaultMode: "auto"`는 무시됨**(개인 `~/.claude/settings.json`에만) + Team 플랜은 Owner가 켜야 함. auto 진입 시 넓은 allow 규칙(`Bash(*)`)은 드롭됨.
- `bypassPermissions` — 컨테이너/VM 전용. 호스트 PC 금지.
- `dontAsk` — CI용(allow 목록 외 자동 거부).

**기타 키:** `enabledPlugins`, `env`, `attribution`(커밋 서명 문구), `cleanupPeriodDays`(트랜스크립트 보존일 — **평문 저장**이라 회사 코드면 단축 고려), `statusLine`, `disableAllHooks`(개발자가 로컬로 훅 끌 수 있음 → 최종선은 CI), `$schema: https://json.schemastore.org/claude-code-settings.json`.

## 4. 스킬 (skills · features-overview)

- **커맨드와 스킬은 통합됨** — `.claude/skills/<이름>/SKILL.md` = `/이름`. 디렉터리명이 명령명.
- **어디에 뭘 두나**: 항상 알아야 할 사실 → CLAUDE.md / 경로별 사실 → rules / **절차(단계 있는 워크플로) → 스킬** ("CLAUDE.md의 한 절이 절차로 자라면 스킬로 옮겨라"). 스킬 본문은 호출 시에만 로드.
- **frontmatter 주요 필드:** `description`(+`when_to_use`, 합쳐 1,536자 상한 — 트리거 문구 앞에), `argument-hint`, `arguments: [a,b]`(→`$a`), `disable-model-invocation: true`(**사람만 호출, 목록 컨텍스트 비용 0** — 배포·머지류 필수), `user-invocable: false`(AI 전용 배경지식), `allowed-tools`(스킬 활성 중 도구 사전승인), `disallowed-tools`, `model`, `effort`, `context: fork`(서브에이전트로 실행 — 대화 이력 없이, 자기완결 태스크만), `agent`(fork 시 에이전트 타입), `hooks`(스킬 수명 동안), `paths`(글롭 게이트).
- **동적 주입:** 줄 첫머리 `` !`명령` `` — **AI가 읽기 전에 실행**되어 출력이 인라인됨(멀티라인은 ```! 펜스). 브리핑·상태 조회에 최적.
- 치환자: `$ARGUMENTS`, `$0`~, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_SESSION_ID}`.
- **작성 원칙(공식):** 500줄 이하, 참조 파일은 1단계 깊이까지, 체크리스트를 응답에 복사시키는 패턴 공식 지원, 자유도 조절(취약한 단계는 "정확히 이 명령만"), 검증 루프("통과할 때까지"), 진행 중 지침은 "1회 단계"가 아니라 "상시 지침"으로 서술(스킬 본문은 재독되지 않음). compaction 시 스킬당 5,000토큰까지만 재부착.
- 프로젝트 스킬이 내장 스킬(`/code-review` 등)을 **이름으로 오버라이드** 가능.
- `skill-creator` 플러그인: 스킬 A/B 평가·트리거 튜닝.

## 5. 훅 (hooks-guide · hooks 레퍼런스)

- **훅 = 보장, CLAUDE.md = 권고.** "매번 반드시"는 훅으로.
- **주요 이벤트:** `SessionStart`(matcher: startup|resume|clear|compact — stdout이 컨텍스트 주입, `initialUserMessage`로 첫 턴 자동 제출 가능), `UserPromptSubmit`(stdout/additionalContext 주입, 30s), `PreToolUse`(matcher=도구명 정규식; `permissionDecision: allow|deny|ask` + `updatedInput`으로 인자 재작성), `PostToolUse`, `Stop`(`decision: "block"` + reason → AI가 계속 작업; `stop_hook_active` 처리 필수, 연속 8회 상한), `SubagentStop`, `ConfigChange`(설정 변경 감사/차단), `PreCompact`/`PostCompact`, `InstructionsLoaded`, `WorktreeCreate` 등 ~30종.
- **타입:** `command`(스크립트) · `prompt`(Haiku 1회 호출) · `agent`(도구 쓰는 검증자, 실험적) · `http`(외부 POST) · `mcp_tool`. `async: true` = 논블로킹.
- 종료코드: **exit 2 = 차단**(stderr가 AI에게 전달돼 자가수정) / exit 0 + JSON stdout = 구조화 출력.
- matcher는 **문자열**("Edit|Write") — 배열이면 settings 전체가 무효.
- PreToolUse의 deny는 bypassPermissions 모드도 이김. 단 훅 자체는 settings 편집으로 끌 수 있음(ConfigChange 훅으로 감사).
- 유용 패턴: 보호 파일 차단(PreToolUse+경로 검사), 테스트 출력 축약(updatedInput으로 `| grep FAIL` 부착 — 토큰 절약), compaction 후 규칙 재주입(SessionStart matcher "compact"), Stop 자가검증.

## 6. 서브에이전트 (sub-agents)

- `.claude/agents/<이름>.md` 커밋 = 팀 공유. frontmatter: `tools`, `model`, `permissionMode`, `skills`(전체 내용 사전 로드), `memory: project`(**커밋되는 에이전트 학습** — 팀 리뷰어가 반복 이슈를 축적), `isolation: worktree`, `background`.
- ⚠️ **내장 Explore/Plan 서브에이전트는 CLAUDE.md를 안 읽음** — 위임 프롬프트에 규칙 재명시 필요. 커스텀/general-purpose는 읽음.
- 호출: 자연어, `@agent-이름`, `claude --agent 이름`(세션 전체 페르소나).

## 7. 플러그인 (plugins · discover-plugins)

- 구성 가능물: skills, agents, hooks, `.mcp.json`, `.lsp.json`, **`monitors/monitors.json`**(백그라운드 모니터 — 명령의 stdout 한 줄 = 세션 알림 주입. **glab 폴링→멘션 실시간화에 사용 가능, 게이트 없음**), `bin/`(PATH 추가).
- **단일 repo 팀 = `.claude/` 직접 커밋이 공식 정답.** 플러그인은 다중 repo 재사용·monitors·bin 필요할 때만. `/team-onboarding`은 문서 생성기(배포 수단 아님).
- `security-guidance@claude-plugins-official`: AI가 자기 변경을 **별도 fresh 컨텍스트로** 3층 보안 리뷰(편집 시 패턴 → 턴 끝 diff → 커밋 시 심층). `enabledPlugins`로 커밋 가능. 차단은 안 함(교정 지시). ⚠️Windows는 venv 단계 스킵 — 심층 리뷰는 SDK 있어야.
- 코드 인텔리전스 플러그인(`typescript-lsp@claude-plugins-official`): 타입 언어에서 grep/read 절감 + 편집 후 자동 타입에러 보고.

## 8. 세션·워크트리·병렬 (sessions · worktrees · agents · agent-teams)

- 세션 = cwd 기준 저장(JSONL, 30일). **`claude -n 이름`으로 명명 → `claude --resume 이름`** (이름 없는 세션은 resume 핸들 안 됨).
- **세션 피커에 GitLab MR URL 붙여넣기 검색 지원**(self-hosted 포함) — "이 MR 만든 세션 찾기". `--from-pr` 자동 링크는 `gh pr create` 기준(GitLab은 피커 검색으로).
- `/clear` 후에도 이전 대화는 저장·복구 가능. 같은 세션을 두 터미널에서 동시 resume 금지(트랜스크립트 섞임).
- **워크트리**: `claude --worktree 이름` → `.claude/worktrees/`에 `origin/HEAD` 기준 생성, 종료 시 무변경이면 자동 삭제. `.worktreeinclude`(gitignore 문법)로 `.env` 등 복사. ⚠️워크트리마다 `npm install` 별도, **compose 포트 충돌은 미해결**(포트 파라미터화 필요), ⚠️Windows는 v2.1.205+ 필수(정션 삭제 버그). `--worktree "#N"`은 GitHub 전용.
- **에이전트 팀(멀티 세션 협업)은 실험적·기본 꺼짐** — 세션 resume 불가, Windows Terminal 분할 미지원, 토큰 대량. 소규모 팀엔 서브에이전트로 충분(공식 문서도 동일 입장).
- 병렬 계층: 서브에이전트(조사·리뷰) < agent view(`claude agents`) < 워크플로 < 팀.

## 9. 자동화·CI (headless · gitlab-ci-cd · code-review · routines · goal · scheduled-tasks)

**headless:** `claude -p "프롬프트"` — CI·스크립트용. `--bare`(훅·스킬·CLAUDE.md 자동탐색 끄고 재현성 — CI 권장), `--output-format json`(**`total_cost_usd` 포함** — 실행당 비용 추적), `--json-schema`(구조화 출력), `--allowedTools`, `--permission-mode dontAsk`.

**GitLab CI/CD 공식 통합 (beta, GitLab 관리):**
- **self-hosted GitLab 동작** — 특별 설치물 없이 `.gitlab-ci.yml` 잡 + 마스킹된 `ANTHROPIC_API_KEY` CI 변수 + `curl claude.ai/install.sh`. ⚠️러너에서 **api.anthropic.com(및 설치 시 claude.ai) egress 필요** — 사내망 방화벽 확인, 또는 CLI 프리베이크한 러너 이미지.
- MR 이벤트 트리거(`rules: merge_request_event`)는 **웹훅 리스너 없이** 가능 — MR마다 자동 리뷰 코멘트 잡의 근거. `@claude` 댓글 반응은 노트 웹훅→파이프라인 트리거 API를 직접 배선해야(리스너 필요).
- API 조작(코멘트·MR)은 `CI_JOB_TOKEN` 또는 api 스코프 PAT.

**관리형 Code Review 서비스는 GitHub 전용** (Team/Enterprise + GitHub App). GitLab 팀 대안 = 로컬 `/code-review` + CI에서 `claude --bare -p` 리뷰 잡. `REVIEW.md`로 리뷰 기준 주입하는 패턴은 로컬에도 이식 가능.

**Routines(클라우드 자동화)는 GitHub repo 전용 + Anthropic 클라우드 실행**(사내망 접근 불가) — self-hosted GitLab 팀은 사용 불가.

**`/goal 조건`**: 매 턴 후 작은 모델이 조건 평가, 충족까지 계속. 조건에 측정 가능한 종료 상태 + 검증 명령 + 턴 상한. headless와 조합 가능.

**`/loop`·크론**: 세션 열려 있는 동안만, 최대 30분 지터, 7일 만료 — 타이트한 SLA엔 부적합(그건 plain cron + `claude --bare -p`).

## 10. 보안·Windows (security · sandboxing)

- **Windows에는 네이티브 샌드박스 없음** (Seatbelt=macOS, bubblewrap=Linux/WSL2) → Windows 호스트에선 **권한 규칙이 유일한 로컬 강제층**. 샌드박스 원하면 WSL2 또는 devcontainer.
- 의심스러운 bash 명령은 allowlist에 있어도 재확인 프롬프트가 뜸(명령 주입 방어 — "프롬프트 0"은 약속 불가).
- ⚠️Windows: WebDAV·`\\*` 경로 허용 금지(권한 우회 경로).
- 자격증명: macOS는 Keychain, **Windows/Linux는 파일 권한 보호뿐**. 트랜스크립트는 평문(`cleanupPeriodDays`).
- 팀 보안 공식 권고: 승인된 권한 설정을 버전 관리로 공유 + `ConfigChange` 훅으로 세션 중 설정 변경 감사 — 우리 설계와 일치.

## 11. 비용·모니터링 (costs)

- 벤치마크: 평균 ~$13/dev/활성일, 90%가 $30/일 미만. 1~5인 조직: 유저당 200-300k TPM 권장.
- `/usage` — 스킬·서브에이전트·MCP별 사용량 귀속. Console 워크스페이스 지출 한도 설정 가능.
- 절감 지렛대: `/clear` 습관, CLAUDE.md 200줄 이하+스킬 분리, CLI(glab)가 MCP보다 컨텍스트 효율적, 테스트 출력 축약 훅, 서브에이전트 model: haiku, `/effort`.

## 12. 우리 설계(Team Dev Mode)에 이미 반영된 결정

| 공식 문서 근거 | 우리 반영 |
| --- | --- |
| 프로젝트 settings는 켠 폴더만 적용 + 하위 CLAUDE.md 로딩 구멍 | "항상 repo 루트에서 실행" + 모듈 규칙은 `.claude/rules/` (paths 글롭) |
| AGENTS.md 임포트 방향 | CLAUDE.md 첫 줄 `@AGENTS.md` (혼용 시) |
| 절차는 스킬로, disable-model-invocation | `/todo /dev /fix /done /module /docs /change /log` 8종 |
| `` !`명령` `` 동적 주입 | /todo·/dev·/fix의 glab 자동 주입 |
| acceptEdits + allowlist 커밋, 신뢰 수락 | starter-kit settings.json + 온보딩 절차 |
| 훅=보장 (PreToolUse ask, SessionStart compact 재주입, ConfigChange) | check-push.sh + settings.json 훅 |
| security-guidance 플러그인 | enabledPlugins로 커밋 |
| 세션 명명 + MR URL 검색 | `claude -n issue-N` 규칙 |
| GitLab CI 통합(MR 이벤트) | Playbook §9 #7 AI 리뷰 잡 (P2) |
| 플러그인 monitors | 멘션 실시간화 P3 경로 |
| Windows 제약 3종 | Playbook §8·리더 가이드 Day 4 경고 |
| 에이전트 팀 스킵, Routines 사용 불가 | 설계에서 제외 (근거 기록) |
