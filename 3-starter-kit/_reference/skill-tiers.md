# 스킬 effort·model 배정 기준 (2026-08-08 · 2026-09-08 2차 개정)

> 자동 로드 ❌. 스킬 frontmatter의 `effort:`·`model:` 주석이 이 파일을 가리킨다. 목적: **누가 어떤 세션 설정으로 돌리든 위험 스킬은 같은 품질 바닥을 갖게** — 스킬 턴 동안만 적용되고 다음 턴에 세션 값으로 원복된다(공식: code.claude.com/docs/en/skills).

## 배정 원칙 4줄
1. **결과 게이트(CI·테스트·승인·증적)가 품질의 정본**이다 — effort/model은 "시도의 바닥"을 올리는 보조 수단. 게이트 없는 품질을 이걸로 대신하려 하지 마라.
2. **실패 비용 × 판단 밀도**로 등급을 정한다. 절차 나열·조회형은 올려봤자 비용만 든다.
3. `model:`은 **fail-soft**(조직 allowlist에 없으면 무시 → 세션 모델 유지)라 안전하지만, 그래서 **산문 소프트 플로어("경량이면 멈춰라")가 백스톱으로 반드시 동반**돼야 한다 — 정본은 CLAUDE.md '모델·effort 소프트 플로어' 한 곳(스킬 본문에 재서술 금지. 플로어가 더 높은 `/overhaul`만 예외로 그 스킬에 한 줄). 모델명 대신 별칭(opus)만 쓴다 — 전체 ID는 썩는다. **모델은 문맥에 보이므로 AI 가 판정할 수 있다.**
4. ★**`effort:`는 «최소»가 아니라 «덮어쓰기»다**(공식: "Overrides the session effort level" · 값 `low`~`xhigh`·`max` · 스킬이 도는 동안만). **그래서 판단이 무거운 스킬은 전부 핀으로 값을 박고, AI 는 effort 를 판정하지 않는다**(오너 결정 2026-09-08). 세션값이 필요하면 `echo $CLAUDE_EFFORT`(Bash·훅에 노출, 공식) — 문맥에는 안 보이니 짐작 금지.

## 2026-09-08 왕복 경위 — 핀 제거 → 산문 판정 → 핀 복귀
- **아침**: `effort: high` 핀 6개를 뺐다(기본값이 high 라 무효고, xhigh 세션을 끌어내리기만 한다는 판단). 바닥은 「세션 effort 가 medium 이하면 멈춰라」 산문 규칙으로 옮겼다.
- **오후, 산문 규칙이 헛정지를 냈다**: bnsone 에서 high 세션인데 «낮다»고 짐작해 `/dev 227` 을 세웠다. 원인은 규칙이 «어떻게 읽는지»(`$CLAUDE_EFFORT`)를 안 알려 줘 AI 가 짐작한 것. 더 나쁜 것은 같은 짐작이 `/done` 리뷰 수준에서 **낮은 쪽으로** 굳어 있었다(실호출 70건 중 40건 low·medium — `done/단계상세.md` §리뷰 수준).
- **결정(오너)**: AI 가 effort 를 고르게 두지 않는다. 판단이 무거운 스킬 9개에 값을 박는다. 「xhigh 세션을 끌어내린다」는 우려는 «그렇게 쓰는 사람이 없다»로 기각. `/design` 의 max 기각 사유(DD-05 「게이트 대화가 느려진다」)도 「전체를 재설계하는 스킬에 xhigh 는 낮다」로 뒤집혔다 — DD-05 개정 참조.
- 공식 권고(Opus 5): 「Start with high … step up to xhigh for demanding coding and agentic work, or to max when a task justifies unconstrained token spending」.

## 배정표
| 등급 | 스킬 | 근거 |
|---|---|---|
| `effort: max` (+`model: opus` design·scaffold) | overhaul · design · scaffold | 전수 재검토·되돌리기 가장 어려운 결정·골격. 저빈도라 토큰은 문제되지 않는다. 공식: 「max when a task justifies unconstrained token spending」 |
| `effort: xhigh` | dev · fix · done · adr · change · ui | 코딩·머지·판단 작업. 공식: 「step up to xhigh for demanding coding and agentic work」. `/done` 안의 리뷰 수준도 xhigh 고정(`/code-review ultra` 는 유료라 금지) |
| `effort: low` | log · assign-module | 조회 요약·표 갱신 — 판단 밀도 낮음. **기본값보다 내리는 핀**(비용 절감) |
| (핀 없음 = 세션 값) | module · docs · inspect · card · setup-gitlab · metrics · start · todo | 게이트가 백스톱이거나 절차·조회형. **todo는 low 금지** — 고위험 승인 대행 경로가 있다 |

## 병렬·독립성은 여기 아니라 본문 조건으로
**스킬 본문에서는** "에이전트 N명" 같은 수 지정을 하지 않는다 — 환경(한도·러너)에 따라 못 지킨다. 대신 **성립 조건**을 본문에 박는다(이미 있음): /done "리뷰는 fresh context 필수", 고위험 "작성자 아닌 눈"+증적 3종, /ui "시안 2~3안". **수를 고정해야 하는 곳은 저장 워크플로**(`.claude/workflows/*.js` — 스크립트가 렌즈·반박 표 수를 결정적으로 정한다: `merge-review`·`audit-sweep`, 2026-09-08 신설). 워크플로가 꺼진 환경(Pro 기본값·`disableWorkflows`)에서는 본문의 성립 조건으로 되돌아간다.

## 바꿀 때
등급 변경은 이 표와 frontmatter를 **같은 커밋**에서 — 표만 고치면 frontmatter가 정본 행세를 한다. 3배포처(킷·파일럿·bnsone) 동일 유지(스킬 sync 규칙).
★**핀을 새로 박기 전에 «기본값과 다른가»를 먼저 물어라** — 같으면 그 핀은 무효거나 남을 끌어내리기만 한다.
