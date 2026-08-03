# 검수 서버 세팅 — 공통 개발자용 (프로젝트당 1회)

> **자동 로드 안 됨.** main 머지 시 자동 배포되는 리뷰 환경(검수 서버)을 사내 인프라에 **한 번** 세팅하는 방법. 일상 흐름(`/done` → 머지 → 자동 배포 → 검수 요청)은 스킬·가이드가 담당한다. 시안 허브(`sian-hub-setup.md`)와 별개 — 허브는 docs 정적 파일, 검수 서버는 **실행되는 앱**.
> 근거 조사: 2026-07-24 E드라이브 실배포 프로젝트 전수 조사(카드 #11 답 "이미 구현된 프로젝트 참조" 반영).

## 무엇인가 (한 문단)
검수자는 **URL 하나만** 본다. 개발자가 `/done`으로 main에 머지하면 CI가 이미지를 빌드해 자동 배포하고, 화면 하단 버전 표시(커밋 해시·배포 시각)로 "지금 보는 게 어느 커밋인지"를 확인한다. 프레임워크 요건(TeamDevMode_Playbook §5·6·9): 기동 순서 db→migrate→app 자동, 멱등 시드, 검수자 테스트 데이터 유지 + 온디맨드 전체 리셋, `/api/health`.

## 경로 = 사내 검증 패턴 (✅ 2026-07-24 리더 확정)
GitLab CI → Harbor → **k8s `bnspace` 네임스페이스**, main push 자동 롤링. **agora·intra·llm-wiki·bns-intranet 4개 프로젝트가 글자 그대로 같은 파이프라인으로 실배포 중** — 러너·레지스트리·인증서·스토리지가 전부 실재해 신규 조달 0. (Charter의 "자체 서버" 제약은 이 사내 클러스터가 곧 자체 서버라 충족.)

## 사내 실측 상수 (경로 A)
| 항목 | 값 | 출처 |
|---|---|---|
| 레지스트리 | `harbor.bns.co.kr/bnspace/<앱>` | 4개 프로젝트 공통 (구: `qcr.k8s.bns.co.kr`) |
| 네임스페이스 | `bnspace` | 〃 |
| CI 서비스계정 | `ssd-ci-deploy` (제한 RBAC: `set image`만 보장) | `E:\intra\k8s\ci-rbac.yaml` |
| pull secret | `registy-cred` (오타지만 클러스터 공용 — 그대로 재사용) | bns-intranet·llm-wiki |
| 스토리지 | RWO `ssd-ceph-block` / RWX `ssd-ceph-cephfs` | 〃 |
| Ingress/TLS | ingressClass `nginx` + cert-manager `ssd-cert`, `*.bns.co.kr` | 〃 |
| 노드 제약 | `ssd-node-05-km-02` 제외(Ceph CSI 없음) | bns-intranet·llm-wiki 매니페스트 |
| CPU 제약 | 구형 x86-64-v2 미지원 → **mysql:8.0 불가, MariaDB 10.11 사용** | `E:\bns-intranet\deploy\k8s\mysql.yaml` 주석 |
| 러너 | 클러스터 접근 내장 — KUBE_CONFIG 대개 불필요 | `E:\bns-intranet\.gitlab-ci.yml` 주석 |

## 세팅 절차 (경로 A, 1회 — 참조 실물을 복제해 값만 바꾼다)
**참조 정본 = `E:\intra`** (검수 서버 요건과 가장 유사: Next.js 단일 이미지·main 자동 배포·엔트리포인트 자동 마이그레이션). YAML 전문은 여기 싣지 않는다 — intra 실물이 정본.

### ⓪ 전제 확인
- GitLab이 뜬 클러스터에 `kubectl` 접근(`kubectl get ns`). ✅ `bnspace` 네임스페이스 접근 확인됨(2026-07-24 리더 확인).
- **검수 도메인 = 제품 도메인 그대로**(리더 방향 2026-07-24): 검수 서버는 리뷰 전용 임시 환경이 아니라 **검증·개발을 거쳐 그대로 실 운영으로 승격되는 서버**다 — 도메인도 처음부터 제품 주소(예: `bnsone.bns.co.kr`)로 잡는다(프로젝트당 1개, basePath 불필요, TLS는 cert-manager `ssd-cert`). ⚠️**제품 명칭 미확정**(사내명 BNSOne vs 차터 명칭 OfficeOne — 도메인에 이름이 박히므로 A레코드 요청 전에 확정 필요). 운영 승격은 새 서버 구축이 아니라 이 서버 그대로 — 오픈 전 데이터 리셋·검수용 데모 계정 분리는 Leader 가이드 §4(오픈 전 목록) 참조. 와일드카드 DNS 없으면 A레코드 선요청.
- (시안 허브 `sian.bns.co.kr`는 여러 프로젝트 공용 유지 — 검수 서버와 별개 구조로 확정.)

### ① 시크릿 2개
- Harbor pull secret: 기존 `registy-cred` 재사용(같은 ns면 생략 가능 여부 먼저 확인).
- 앱 시크릿(DB 비밀번호 등): **CI 변수에 두고 `kubectl create secret … --dry-run=client -o yaml | kubectl apply -f -`** (로그 노출 방지 — agora `service-deploy` 잡 패턴). 값 자체를 매니페스트에 커밋하지 않는다.

### ② DB
클러스터 내부 단일 파드 + PVC(RWO `ssd-ceph-block`) + `strategy: Recreate`. Postgres면 `E:\intra\k8s\postgres.yaml`, MySQL 계열이면 `E:\bns-intranet\deploy\k8s\mysql.yaml`(=MariaDB) 복제. 외부 비노출(`port-forward`로만 접근).

### ③ 앱 매니페스트
`E:\intra\k8s\app.yaml` 복제: readiness `/api/health`(배포 게이트 겸용), RollingUpdate `maxUnavailable: 0`, preStop 드레인, `ssd-node-05-km-02` 회피 nodeAffinity, Ingress(TLS `ssd-cert`).

### ④ 마이그레이션·시드 = 앱 엔트리포인트
CI에 별도 migrate Job을 만들지 않는다(CI SA RBAC이 Job 생성을 보장 안 함 — llm-wiki 실측). **이미지 엔트리포인트가 파드 기동마다 forward-only·멱등 마이그레이션 + 멱등 시드를 실행** — `E:\intra\docker-entrypoint.sh` 패턴. 프레임워크 킷의 `db/migrations` 자체 러너를 여기 연결한다. 온디맨드 전체 리셋 = DB 파드 PVC 재생성 스크립트 1개(플레이북 §6).

### ⑤ CI 잡 교체
킷/bnsone `.gitlab-ci.yml`의 `deploy-review` 스텁(echo)을 실제 잡으로: dind 빌드 → Harbor push → `kubectl -n bnspace set image deployment/<앱> …:$CI_COMMIT_SHORT_SHA` → `rollout status --timeout=300s`. `environment.url`을 실제 검수 도메인으로 교체. 원본 = `E:\intra\.gitlab-ci.yml`의 `release` 잡. RBAC이 부족한 환경 대비 graceful degradation(권한 있으면 매니페스트 동기화, 없으면 `set image`만 — llm-wiki 패턴).

**★`changes:`로 빌드 범위를 좁혔으면 `needs`를 반드시 `optional: true`로** — 빌드 잡이 빠지는 커밋(문서만 수정 등)에서 **파이프라인 생성 자체가 거부**되어 잡 0개가 된다(시크릿 스캔·planner-guard 포함 전 게이트 무효). bnsone 2026-08-03 실사고, 9회. `glab ci lint`·dry_run 다 통과하니 문법 검증으론 안 잡힌다 → 킷 `ci-needs-check` 잡이 기계 방어. 경위: G-10 · `3-starter-kit/_reference/ci-needs.md`

```yaml
needs:
  - job: docker-build
    optional: true
```

### ⑥ 확인 (완료 기준)
main에 **코드 파일을 실제로 건드리는** 커밋 1개 → 파이프라인 초록 → 검수 URL에서 앱 렌더 + 하단 버전 표시가 방금 커밋 해시로 갱신 + `/api/health` 200.
**빈 커밋·문서만 바꾼 커밋으로 확인하지 마라** — `changes:` 범위 밖이라 빌드·배포 잡이 애초에 안 돌고, 위 `optional` 처방을 안 했으면 그 커밋이 바로 파이프라인을 죽인다. **확인 후 문서만 바꾼 커밋도 한 번 올려 파이프라인이 정상 생성되는지 보라**(이 사고가 딱 그 케이스에서만 났다).

## 주의 (실측 교훈 계승)
- mysql:8.0 이미지는 구형 노드에서 안 뜬다 → MariaDB 10.11.
- 최초 리소스(시크릿·DB·Ingress)는 **운영자 수동 1회**(CI는 이미지 교체만) — bns-intranet 런북 방식.
- 첨부파일이 생기면: DB 저장(intra 방식, 볼륨 불필요) 또는 RWX cephfs(agora 방식) 중 설계 시 결정.
