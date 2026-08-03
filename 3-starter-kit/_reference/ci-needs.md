# needs 함정 — 잡 하나 때문에 파이프라인이 통째로 안 만들어진다

> **배포 잡(빌드→배포처럼 `needs`로 이어지는 잡)을 만들거나 고칠 때 읽어라.**

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

가장 아픈 점: `planner-guard`는 기획자의 docs 직접 push(ADR-0001)를 감시하려고 만든 잡인데, **정확히 그 상황에서만 100% 꺼졌다.** 안전망이 필요한 순간에만 꺼지는 유형이다.

## 왜 lint로 못 잡나 (실측)

- 로컬 `glab ci lint` → `✓ valid`
- `POST /ci/lint?dry_run=true` → `valid: true`

**비교할 diff가 없으면 `changes:`가 참으로 계산**되어 needs가 충족된 것처럼 보인다. 문법 검증으로는 원리상 안 잡힌다.

## ★새 브랜치 첫 푸시는 항상 초록이다

같은 이유로, **새로 만든 브랜치의 첫 푸시에서는 `changes:`가 무조건 참**이다. 그래서:

> 배포 설정을 새 브랜치에서 만들어 검증 → 초록 → main 머지 → **그 다음 문서 푸시부터 터짐**

bnsone 검수 서버 세팅(2026-07-31)이 이 경로를 그대로 밟았다. **"브랜치에서 초록이었다"는 안전의 근거가 안 된다.**

## 처방 — 순서대로 검토하라

**① 기본: 두 잡의 `rules`를 맞춘다** (같은 `changes:`를 YAML 앵커로 공유)

```yaml
docker-build:
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes: &code_changes [src/**/*, package.json, Dockerfile]

service-deploy:
  needs: ["docker-build"]
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes: *code_changes          # ← 같이 들어오고 같이 빠진다
```

**② `optional: true`는 산출물을 안 쓸 때만**

```yaml
needs:
  - job: docker-build
    optional: true
```

**★`optional`을 아무 데나 붙이지 마라.** 배포 잡이 빌드 잡의 이미지·아티팩트를 쓰는데 `optional`로 두면, 빌드가 안 돈 커밋에서도 배포 잡이 실행 가능해진다 → 올라간 적 없는 태그를 가리켜 **CI에서 시끄럽게 실패하는 대신 k8s에서 조용히 `ImagePullBackOff`**. 시끄러운 실패를 조용한 실패로 바꾸는 건 개악이다.

## 확인 방법

배포 설정을 바꾼 뒤 **문서만 바꾼 커밋을 main에 한 번 올려** 파이프라인이 정상 생성되는지 본다. 이 사고가 딱 그 케이스에서만 났다. 빈 커밋·브랜치 초록으로 확인하지 마라(위 참조).

## 재현 근거 (파일럿 #90, 푸시 3회)

| 조건 | 파이프라인 | 잡 |
| --- | --- | --- |
| 새 브랜치 첫 푸시 | success | 2 |
| 기존 브랜치에 **문서만** 커밋 | **failed** | **0** |
| 같은 조건 + `optional: true` | success | 1 |

## 왜 자동 검사기를 두지 않는가 (2026-08-03 시도 후 철회)

이 함정을 CI 잡으로 기계 검사하려고 `check-ci-needs.py`를 만들었다가 **fresh-context 리뷰에서 블로커 4건이 나와 철회**했다. 재현 확인된 것:

- `extends`로 물려받은 `needs`를 **못 본다** — 잡아야 할 바로 그 모양을 놓쳤다
- 양쪽 `changes:` 경로 목록이 다르거나 "MR엔 changes, main엔 무조건"인 형태를 **못 본다** — 이 킷 CI가 도처에 쓰는 모양이다
- 부모/자식 파이프라인 `needs: [{pipeline:…, job:…}]`을 **버그로 오판**해 영구 빨간불
- `include:`로 파일을 나눈 프로젝트도 전부 거짓 경보

GitLab 설정 문법이 넓어서 "빠질 수 있나"를 정적으로 판정하려면 예외가 계속 나온다. **잘못 짠 검사기는 없는 것보다 나쁘다**(거짓 경보로 CI를 막거나, 통과 도장을 찍어 안심시킨다).

※ 교훈 하나 더: 처음엔 자체 검증 6/6 통과로 보고했으나, **그 6가지는 만든 사람이 상상한 6가지**였다. 새 눈이 보자 즉시 3건이 나왔다 — 자기 물건의 자기 검증은 커버리지의 근거가 못 된다. (CLAUDE.md 셀프 승인 증적 3종이 실제로 나쁜 변경을 막은 사례)
