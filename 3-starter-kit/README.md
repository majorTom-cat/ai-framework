# Starter Kit — 새 repo에 통째로 복사하는 실물 파일

> 문서(설계도)가 아니라 **실행 파일**이다. 프로젝트 repo를 만들면 이 폴더의 내용을 repo 루트에 복사한다.
> 공통 개발자 가이드 Day 3~5의 산출물 시작점 — 여기서 시작해 프로젝트에 맞게 다듬는다.
> ✅ **협업 시뮬레이션 3회로 실증·보강됨** — 발견된 결함 51테마가 전부 이 킷의 문서·스킬 본문에 반영된 상태다 (별도 사례 문서 없음 — 킷 자체가 결과물).

## 사용법 (공통 개발자, 5분)

1. 이 폴더의 `CLAUDE.md`, `.claude/`, `docs/`, `_reference/`, `scripts/`, `test/`, `.gitlab/`, `.gitlab-ci.yml`, `.gitignore` 을 **새 repo 루트에 복사**
   - ⛔**`_reference/`·`scripts/`를 빠뜨리지 마라** — `CLAUDE.md`가 `_reference/`의 실전 노트 전부를 본문에서 가리키므로 빠지면 새 repo에서 전부 깨진 링크가 되고, `.gitlab-ci.yml`의 `density-check` 잡이 `bash scripts/check-density.sh`를 실행하므로 빠지면 **매 MR마다 그 잡이 실패**한다(`allow_failure`라 빨간불 없이 조용히 죽어 아무도 모른다).
   - `docs/` 안에 **`_STEP_INDEX.md`(진행 지도)와 `00_Guide/`(사람이 읽는 가이드 3종: GitLab 실전·공통 개발자·ClaudeCode + 시안 허브 문서 2종: sian-hub-setup·sian-scenarios + 검수 서버 세팅 1종: review-server-setup)가 이미 들어 있다** — 별도로 챙길 것 없이 통째로 복사되면 된다. (가이드 3종의 정본은 `../2-team-dev/`, `review-server-setup.md`의 정본은 `../4-reference/`판 — 킷 동봉본과 어긋나면 정본이 맞으니 로직만 다시 가져오고 **사내 상수는 플레이스홀더로 유지**한다)
   + `ONBOARDING.md`(개발자·공통 개발자 첫날/매일)는 **`docs/00_Guide/`에 들어 있다**(단일본 — README 링크가 거길 가리킨다. ※과거 루트 사본은 드리프트해서 7-23 제거 — 사본을 늘리지 말 것)
   + `repo-README.md` 를 repo 루트에 **`README.md`** 로 복사 — 팀이 clone 후 처음 여는 **역할별 지도**(어느 문서를 볼지 안내). 프로젝트 이름만 채운다
2. 전체 파일에서 플레이스홀더 치환 — **표기 규약: `<꺾쇠>`=지금 치환하는 설치 값 / `{중괄호}`=실행 시점 값(치환 금지, AI가 그때 채움)**:
   - `<기획자아이디>` → 기획 담당 GitLab 아이디 (스펙 상이·docs 관련 @멘션 알림용). **검수 전담자는 없다** — 검수자는 카드마다 "검수" 필드로 지정하고 비면 담당자(구현자)가 검수하므로, 고정 플레이스홀더를 두지 않는다
   - `<모듈a>`~`<모듈d>` → 실제 모듈 이름 / `<본보기모듈>` → 본보기 모듈 이름
   - **`<기동명령>`** → 로컬 앱 기동 명령 (CLAUDE.md '실행·테스트' 절이 전 문서 명령의 정본)
   - `<검수서버URL>` → 자동 배포 주소 (★검수자가 자기 자리에서 접속할 **공용 주소**. 아직 없으면 임시로 localhost를 넣되 **"공용 주소 전환" 카드를 바로 발행** — 위반 상태를 카드 없이 방치 금지)
   - `<시안허브URL>` → 화면 시안 열람 주소 (CLAUDE.md ★실행 절·`/ui 시안`이 사용. 세팅은 인스턴스에 1회 — `docs/00_Guide/sian-hub-setup.md`. 아직 없으면 리터럴로 두면 `/ui 시안`이 세팅부터 안내한다)
   - `<사내GitLab주소>` (ONBOARDING의 glab 로그인 · **`.claude/settings.json` 의 `sandbox.network.allowedDomains` 도 같은 자리다**) / `<팀채팅주소>` → 실제 채팅 채널
   - **CLAUDE.md 모듈 소유 표** → 팀 태울 때 소유자 기입 (본보기 모듈 이관 포함 — 비워두면 /card 배정·/start 진단 불능)
   - `.claude/hooks/check-push.sh`의 **공통 영역 감지는 파일 경로 기준**이다(테이블 이름이 아니다 — `src/shared/`·`.claude/`·`db/migrations/`·`CLAUDE.md`·CI/컨테이너 설정·lockfile·middleware). repo 폴더 구조가 킷과 다르면 그 `grep -iE` 패턴의 **경로**를 실제 구조에 맞게 고쳐라. ※테이블명 치환은 필요 없다 — 스크립트에 테이블 이름은 없다
   - **`.claude/rules/*.md`의 `paths:` 글롭** → 실제 repo 폴더 구조에 맞게 (구조가 다르면 규칙이 조용히 죽는다)
   - `.claude/rules/migrations.md`의 `<확장자>` → 마이그레이션 도구 표준(.sql/.ts 등).
     **DB·마이그레이션 없는 스택이면**: rules/migrations.md 삭제 + CLAUDE.md '스키마·데이터' 절 제거 + /done 2단계 제거
   - package-lock.json 은 **스켈레톤에 커밋**해 둔다 (untracked 로 방치하면 카드 무관 커밋에 휩쓸린다)
3. `.gitignore` 는 **동봉된 것을 그대로 쓴다**(`CLAUDE.local.md`·`.claude/settings.local.json`·`.env*`·세션 잠금·`docs/inbox/_tmp/` 가 들어 있다) — 손으로 더할 것 없음
4. 커밋. **각 팀원은 clone 후 repo 루트에서 `claude` 첫 실행 → 신뢰 수락** — 그래야 권한·훅이 발효된다
   (Windows 전원: ONBOARDING 첫날 셋업의 **`CLAUDE_CODE_GIT_BASH_PATH` 환경변수 포함** — 없으면 bash 훅이 조용히 안 돈다)

## 들어 있는 것

| 파일 | 역할 |
| --- | --- |
| `CLAUDE.md` | 팀 공통 규칙 — 전원의 AI가 매 세션 자동으로 읽음 |
| `ONBOARDING.md` | 역할별 첫날 셋업 + 매일 일하는 순서 (개발자·공통 개발자용 1장 — 역할별 별책 가이드 3종은 `docs/00_Guide/`) |
| `.claude/settings.json` | 권한 허용목록(승인 클릭 제거) + 훅 등록 + 보안 플러그인 |
| `.claude/rules/*.md` | 경로별 규칙 — 그 경로 파일을 만질 때 AI에 자동 로드 |
| `.claude/skills/` | 스킬 **19종**(개발 13: start·todo·card·dev·fix·ui·inspect·done·module·docs·change·log·adr + 공통 개발자 6: design·scaffold·setup-gitlab·assign-module·metrics·overhaul) — 팀 표준 절차. **예시·결과 표의 정본 = repo-README 스킬 표** |
| `.claude/hooks/check-push.sh` | push 전 공통 영역 변경 감지 → 확인 요구 (Claude Code `PreToolUse` 훅 전용 — git/husky 훅이 아니다) |
| `_reference/*.md` | `_reference/` 실전 노트 전부 — **CLAUDE.md·CI가 본문에서 가리킨다**(자동 로드 ❌) |
| `scripts/check-density.sh` | 규칙 문서 밀도 검사 — **CI `density-check` 잡이 실행**(로컬: `bash scripts/check-density.sh`) |
| `docs/adr/0000-템플릿.md` | 결정 기록(ADR) 템플릿 — 되돌리기 어려운 결정을 반 장으로 남김 |
| `.gitlab/issue_templates/카드.md` | 카드(이슈) 양식 — 정본 참조·수용 기준(검수/CI 태그)·**검수(지정자)**·의존·검수 방법 필드 고정 |

## 아직 비어 있는 것 (골격 구축 때 채움)

- `npm run gen:module` / **`npm run reseed`**(검수 서버 재시드 — 공통 개발자 운영용) / **`npm run inspect`**(화면 검사 하네스 — /inspect 가 호출, Playwright 계열. 새 실패 유형을 발견할 때마다 검사를 추가해 복리로 키움) 스크립트 (공통 개발자 가이드 Day 1·5·골든 패스 §3)
- **플래그 프리뷰 미들웨어** (`?preview={플래그명}` — 요청 단위 플래그 해제, Day 1 골격) + **버전 푸터**(커밋 해시·배포 시각 — 검수자가 "내가 보는 게 최신인지" 확인)
- `rules/module-*.md` 의 실제 내용 (본보기 모듈 완성 후 소유자가 채움)
- husky pre-push, 스냅샷 테스트, CI (공통 개발자 가이드 Day 2·4)

## 도입 후보 — 킷이 기본 포함하지 않는 이유와 켜는 법 (`../4-reference/ecosystem-analysis.md` 근거)

| 후보 | 켜는 법 (1줄) | 기본 미포함 이유 |
| --- | --- | --- |
| gitlab MCP (zereight/gitlab-mcp) | `claude mcp add gitlab -- npx -y @zereight/mcp-gitlab` + `GITLAB_API_URL`·PAT, **`GITLAB_TOOLSETS`·`GITLAB_PERMISSION_MODE`(readonly/modify/full)로 필요 도구만** | ★**켜기 전에 `glab api version` 으로 `version`·`enterprise` 를 재라.** **공식**(인스턴스 내장) MCP 는 **18.6+ & Premium/Ultimate & Duo** 라 무료판·구버전이면 **불가**. 커뮤니티판은 무료판·사내 설치가 되지만 **받쳐 주는 최소 버전 표가 없어** 실테스트 1회는 여전히 필요하고, **도구 261개**(2026-09-16 재조사 · 2026-07 조사 때 170개) 전부 켜면 컨텍스트 낭비 — MCP 는 같은 일에 CLI 보다 토큰 **4~32배**라는 측정이 여럿이다. ★**이미 `glab` 로 도는 절차가 있으면 갈아타는 비용부터 세라**(킷 기준 스킬 19개·호출 141곳) |
| LSP 플러그인 (예: typescript-lsp) | `/plugin install typescript-lsp@claude-plugins-official` **+ `npm i -g typescript-language-server typescript`**(플러그인은 바이너리를 동봉하지 않는다 — 빼면 첫 호출이 `ENOENT`로 죽는다. 2026-08-26 실측) | 스택 확정 후에만 유효, Windows 바이너리 언어별 확인 필요 |
| playwright MCP | `claude mcp add playwright -s user -- npx -y @playwright/mcp@latest` | 호출 때마다 **cwd에 `.playwright-mcp/`**(스냅샷·콘솔 로그)를 만든다 — `.gitignore`(팀이 안 쓰면 개인 `~/.config/git/ignore`)에 넣지 않으면 커밋에 딸려 간다. 2026-08-26 실측 |
| context7 MCP (라이브러리 문서) | `claude mcp add context7 -s user -- npx -y @upstash/context7-mcp` | **질의가 외부 호스트로 나간다** — 사내 프로젝트에서 켜는 것은 오너 고지 대상. 개인 범위(`-s user`)로만, 프로젝트 범위는 `.claude/settings.json`=공통 영역이라 공지 절차를 탄다 |
| claude-md-management (공식) | `/plugin install claude-md-management@claude-plugins-official` | CLAUDE.md가 어느 정도 자란 뒤에 가치 — 초기엔 노이즈 |

> **CI의 보안·중복·변조·AI리뷰 층은 "후보"가 아니라 필수(P1)** — 사람 리뷰가 없는 구조에서 유일한 자동 안전망이라 공통 개발자 가이드 **Day 2**에서 골격과 함께 세운다. (여기 "도입 후보"는 없어도 굴러가는 선택지, CI 안전망은 그렇지 않다.)
