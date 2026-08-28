# `paths:` 규칙은 언제 로드되나 — 실측 (2026-08-28)

> 정본 규칙은 `CLAUDE.md` '규칙이 언제 읽히나'. 이 파일은 **그 결론의 근거**다(자동 로드 ❌).

## 왜 쟀나
bnsone 세션이 물었다: 「auto 모드라 Bash 로 파일을 읽는데, 그때도 `paths:` 규칙이 로드되는가?
안 걸린다면 auto 모드 세션에서는 `paths:` 기반 규칙 전체가 무력화된다.」 추측으로 둘 수 없는 질문이라 쟀다.

## 어떻게 쟀나 — 모델 자기보고가 아니라 하네스 로그
격리 임시 프로젝트 하나를 만들었다(이 repo 밖).

```
probe/
├── .claude/rules/probe.md   # frontmatter: paths: ["src/**"]  본문에 마커 지시
├── .claude/settings.json    # InstructionsLoaded 훅 → loaded.log 에 append
└── src/x.txt                # "hello-probe"
```

`InstructionsLoaded` 훅은 **어떤 지시문 파일이 언제 왜 로드됐는지**를 JSON 으로 넘긴다
(`file_path`·`memory_type`·`load_reason`). 모델이 "읽었다/못 읽었다"고 말하는 것보다 이게 사실에 가깝다.

같은 파일을 두 방식으로 읽혔다(`claude -p`, 도구를 하나씩만 허용):
- A: `--allowedTools Bash` + 「cat 으로 읽어라」
- B: `--allowedTools Read` + 「Read 로 읽어라」

## 결과

| | 로드된 지시문 | 마커 |
| --- | --- | --- |
| **A 셸 `cat`** | `~/.claude/CLAUDE.md` (`session_start`) **뿐** | 안 나옴 |
| **B Read 도구** | 위 + `.claude/rules/probe.md` (**`load_reason: path_glob_match`**) | 나옴 |

**결론: `paths:` 규칙은 Read 도구 경로에서만 걸린다. 셸로 읽으면 안 걸린다.**

## 무엇을 뜻하나
Bash 우선으로 읽는 세션(하네스가 그렇게 지시하는 모드 포함)에서는 `migrations.md`·`shared.md`·
`docs.md`·`module-*.md` 가 **조용히 무력화**된다. "규칙이 있으니 지켜지겠지"가 성립하지 않는다.

→ **반드시 지켜져야 하는 것은 `paths:` 규칙에만 두지 마라.** CLAUDE.md·`paths:` 없는 rules(항상 읽힘) ·
훅/CI(기계 강제) · 스킬(그 명령을 부를 때) — 이 세 층 중 하나에 두고, `paths:` 는 보강으로만 쓴다.

## 후속 실험 — 옮긴 규칙이 실제로 걸리는지도 쟀다 (같은 날)
조건부(`paths:` 있음)와 무조건(`paths:` 없음) 규칙을 **한 프로젝트에 나란히** 두고, 셸로만 읽는 세션 하나를 돌렸다.

| 규칙 | 로드 | 마커 |
| --- | --- | --- |
| `conditional.md` (`paths: src/**`) | 안 됨 | 안 나옴 |
| `always.md` (`paths:` 없음) | **`load_reason: session_start`** | 나옴 |

**«옮기면 걸린다»까지 확인한 것**이다 — 고쳤다고 말하기 전에 고쳐졌는지 재는 게 이 파일의 요점이다.

## 공식 문서와의 관계
문서는 「Path-scoped rules trigger when Claude **reads** files matching the pattern」이라고만 쓴다.
«read» 가 Read 도구를 뜻하는지 셸 읽기를 포함하는지는 문서로는 갈리지 않는다 — 그래서 쟀다.
