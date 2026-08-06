# 검수 서버 세팅 — 공통 개발자용 (프로젝트당 1회)

> **정본 = 프레임워크 repo `4-reference/review-server-setup.md`판** (사내 실측 상수 포함). 이 파일은 그 정본에서 사내 정보(서버 주소·레지스트리·계정·경로)를 플레이스홀더로 정화한 배포판이다 — **최종 동기: 2026-08-06**. 로직·경고가 어긋나면 정본이 맞다.
> **자동 로드 안 됨.** main 머지 시 자동 배포되는 리뷰 환경(검수 서버)을 사내 인프라에 **한 번** 세팅하는 방법. 일상 흐름(`/done` → 머지 → 자동 배포 → 검수 요청)은 스킬·가이드가 담당한다. 시안 허브(`sian-hub-setup.md`)와 별개 — 허브는 docs 정적 파일, 검수 서버는 **실행되는 앱**.

## 무엇인가 (한 문단)
검수자는 **URL 하나만** 본다. 개발자가 `/done`으로 main에 머지하면 CI가 이미지를 빌드해 자동 배포하고, 화면 하단 버전 표시(커밋 해시·배포 시각)로 "지금 보는 게 어느 커밋인지"를 확인한다. 프레임워크 요건: 기동 순서 db→migrate→app 자동, 멱등 시드, 검수자 테스트 데이터 유지 + 온디맨드 전체 리셋, `/api/health`.

## 세팅 전 결정 2가지 (리더·공통 개발자)
1. **배포 대상**: 사내에 **이미 실배포 중인 프로젝트가 있으면 그 파이프라인을 그대로 복제**하는 것이 최선이다(검증된 러너·레지스트리·인증서 재사용, 신규 조달 0). 없으면 단일 VM+docker-compose가 차선.
2. **도메인**: 검수 서버가 나중에 **그대로 운영으로 승격되는 구조라면 처음부터 제품 도메인**으로 잡는다(직원들이 즐겨찾기할 주소다). A레코드 요청 전에 제품 명칭부터 확정.

## 채워야 할 값
| 항목 | 값 |
|---|---|
| 컨테이너 레지스트리 | `<레지스트리>/<그룹>/<앱>` |
| k8s 네임스페이스 (또는 VM 호스트) | `<네임스페이스>` |
| CI 서비스계정·권한 | `<CI계정>` (최소: 배포 이미지 교체 권한) |
| 이미지 pull secret | `<pull시크릿>` |
| 스토리지 클래스 (DB용 RWO) | `<스토리지클래스>` |
| Ingress·TLS | `<인그레스클래스>` · `<인증서발급자>` |
| 검수 도메인 | `<검수서버URL>` (CLAUDE.md ★실행 절과 CI `environment.url`에 반영) |

> ★**확정값은 이 표에 채워 남긴다** — 도메인·DB 포트·시크릿 이름·필요한 CI 변수까지. YAML 주석에만 두면 "정본에 없다"고 리뷰가 지적한다(bnsone 실측). 사내 서버엔 `kubectl` alias `k`가 있으면 그걸 쓴다(예시가 `kubectl`이라 매번 길어진다).

## 세팅 절차 (1회)
### ⓪ 전제 확인
- 배포 대상 클러스터/서버에 접근 가능(`kubectl get ns` 또는 ssh).
- **DNS는 먼저 `nslookup <도메인>`으로 확인** — 와일드카드 DNS가 이미 있으면 응답이 오고, 그러면 **A레코드 선요청은 건너뛴다**(bnsone은 A레코드 없이 nslookup만으로 끝났다). 응답이 없을 때만 A레코드 요청.

### ① 시크릿
- 레지스트리 pull secret + 앱 시크릿(DB 비밀번호 등). **값은 CI 변수에 두고 `kubectl create secret … --dry-run=client -o yaml | kubectl apply -f -`** 패턴으로(로그·매니페스트에 값 노출 금지).

### ② DB
- 클러스터 내부 단일 파드 + PVC(RWO) + `strategy: Recreate`, 외부 비노출(`port-forward`로만 접근). 사내 기존 프로젝트의 DB 매니페스트가 있으면 복제.

### ③ 앱 매니페스트
- readiness `/api/health`(배포 게이트 겸용), RollingUpdate `maxUnavailable: 0`, Ingress+TLS. 사내 기존 프로젝트 매니페스트 복제 권장.
- ★**매니페스트가 여러 파일이면 서버에서 `git clone` 하라** — 시안 허브 가이드의 base64 붙여넣기 우회보다 clone이 훨씬 단순하고 안 깨진다(실측).

### ④ 마이그레이션·시드 = 앱 엔트리포인트
- CI에 별도 migrate Job을 만들지 않는다(CI 계정 권한을 최소로 유지). **이미지 엔트리포인트가 파드 기동마다 forward-only·멱등 마이그레이션 + 멱등 시드를 실행**한다 — 킷 `db/migrations` 자체 러너를 여기 연결. 온디맨드 전체 리셋 = DB 파드·PVC 재생성 스크립트 1개.

### ⑤ CI 잡 교체
- 킷 `.gitlab-ci.yml`의 `deploy-review` 스텁(echo)을 실제 잡으로: 이미지 빌드 → push → `kubectl set image … $CI_COMMIT_SHORT_SHA` → `rollout status`. `environment.url` = 검수 도메인. CI 계정 권한이 부족한 환경 대비 graceful degradation(권한 있으면 매니페스트 동기화, 없으면 `set image`만).
- ★**기본 CI SA는 `set image`만 보장** → 매니페스트 `apply`가 필요하면 `Forbidden`으로 죽는다. 택1: **㉠관리자가 `ci-rbac.yaml` 적용** / **㉡운영자가 서버에서 직접 `apply`**(CI는 이미지 교체만). 어느 쪽인지 이 절에 명시.

- ★**`changes:`로 빌드 범위를 좁혔으면 그 빌드를 `needs`로 쓰는 잡에도 같은 `changes:`를 걸어라** — 한쪽만 빠지는 커밋(문서만 수정 등)에서 **파이프라인 생성 자체가 거부**되어 잡 0개가 된다(시크릿 스캔·planner-guard 포함 전 게이트가 통째로 무효). 실사고 8회(2026-07-31·08-03). `glab ci lint`·dry_run은 다 통과하니 **문법 검증으로는 안 잡힌다.** 경위·처방: `_reference/ci-needs.md`

```yaml
docker-build:
  rules: [{ if: '$CI_COMMIT_BRANCH == "main"', changes: &code_changes [src/**/*, Dockerfile] }]
service-deploy:
  needs: ["docker-build"]
  rules: [{ if: '$CI_COMMIT_BRANCH == "main"', changes: *code_changes }]   # 같이 들어오고 같이 빠진다
```

- `optional: true`는 **그 잡의 산출물(이미지·아티팩트)을 안 쓸 때만** 쓴다 — 쓰면서 optional로 두면 **눌러봤자 반드시 실패하는 버튼**이 남는다(올라간 적 없는 태그 → rollout 타임아웃까지 대기 후 빨간불). ※`rollout status --timeout`이 있으면 실패는 시끄럽고 `maxUnavailable: 0`이면 서비스도 안 끊긴다 — 다만 `rollout status` 없이 `set image`만 하는 배포 잡이라면 진짜로 조용히 깨진다.

### ⑥ 확인 (완료 기준)
- main에 **코드 파일을 실제로 건드리는** 커밋 1개 → 파이프라인 초록 → 검수 URL에서 앱 렌더 + 하단 버전 표시가 방금 커밋 해시로 갱신 + `/api/health` 200.
- ⛔**빈 커밋·문서만 바꾼 커밋으로 확인하지 마라** — `changes:` 범위 밖이라 빌드·배포 잡이 애초에 안 돌고, 위 `optional` 처방을 안 했으면 그 커밋이 바로 파이프라인을 죽인다(잡 0개 = 게이트 전부 무효).
- 그다음 **문서만 바꾼 커밋도 한 번 올려 파이프라인이 정상 생성되는지 보라** — 위 사고가 딱 그 케이스에서만 났다.

## 주의 (이건 정상이다 — "배포가 깨졌다"로 오해하기 쉬운 것들, bnsone 실측)
- **최초 1회 `deploy-review` 실패는 정상** — Deployment가 아직 없으면 `set image`가 죽는다(첫 배포 후 정상).
- **첫 이미지가 없으면 `ImagePullBackOff`도 정상** — CI 변수 등록 후 첫 빌드 전까지 그렇다.
- 최초 리소스(시크릿·DB·Ingress)는 **운영자 수동 1회** — CI는 이미지 교체만 한다.
- 구형 CPU 노드에선 일부 공식 이미지(예: mysql:8.0)가 안 뜰 수 있다 — 사내 검증된 이미지를 따르라.
- 첨부파일 저장은 설계 때 결정: DB 저장(볼륨 불필요) 또는 RWX 볼륨.
