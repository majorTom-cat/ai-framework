# needs 함정 — 잡 하나 때문에 파이프라인이 통째로 안 만들어진다

## 무슨 일 (bnsone 2026-08-03 실사고)

문서만 바꾼 main 푸시 **9회 전부** 파이프라인 잡 0개. `secret-scan`(차단)·`planner-guard`·`tamper-check`·`density-check`가 모두 미실행.

```
yaml_errors: 'service-deploy' job needs 'docker-build' job,
             but 'docker-build' is not in any previous stage
```

| 잡 | rules | 문서만 바뀐 푸시 |
| --- | --- | --- |
| `docker-build` | `if: main` + `changes:` | 제외 |
| `service-deploy` | `if: main` **만** | **포함** + `needs: ["docker-build"]` |

`needs`가 파이프라인에 없는 잡을 가리키면 GitLab은 그 잡만 빼는 게 아니라 **파이프라인 생성 자체를 거부**한다.

가장 아픈 점: `planner-guard`는 기획자의 docs 직접 push(ADR-0001)를 감시하려고 만든 잡인데, **정확히 그 상황에서만 100% 꺼졌다.**

## 왜 lint로 못 잡나 (실측)

- 로컬 `glab ci lint` → `✓ valid`
- `POST /ci/lint?dry_run=true` → `valid: true`

**비교할 diff가 없으면 `changes:`가 참으로 계산**되어 `docker-build`가 포함된 것처럼 보인다. 정적 검사로는 원리상 안 잡힌다 → `scripts/check-ci-needs.py`(CI `ci-needs-check`)가 필요한 이유.

## ★새 브랜치 첫 푸시는 항상 초록이다

같은 이유로, **새로 만든 브랜치의 첫 푸시에서는 `changes:`가 무조건 참**이다. 그래서:

> 배포 설정을 새 브랜치에서 만들어 검증 → 초록 → main 머지 → **그 다음 문서 푸시부터 터짐**

bnsone 검수 서버 세팅(2026-07-31)이 이 경로를 그대로 밟았다. **"브랜치에서 초록이었다"는 안전의 근거가 안 된다.**

## 처방

```yaml
needs:
  - job: docker-build
    optional: true
```

## 재현 (파일럿 #90, 푸시 3회)

| 조건 | 파이프라인 | 잡 |
| --- | --- | --- |
| 새 브랜치 첫 푸시 | success | 2 |
| 기존 브랜치에 **문서만** 커밋 | **failed** | **0** |
| 같은 조건 + `optional: true` | success | 1 |

## 검사기 자기검증 (6/6)

버그 있는 bnsone·재현 브랜치 수리 전 → 잡힘 / 킷·파일럿 main·수리 적용본 2종 → 통과.

**조용히 통과시키지 않는다** — PyYAML이 없으면 exit 0이 아니라 **exit 1**. "검사가 안 돈 걸 초록으로 보고하는 것"이 이 사고의 본질이었다.
