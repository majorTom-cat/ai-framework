# 시안 허브 세팅 — 공통 개발자용 (인스턴스에 1회)

> **자동 로드 안 됨.** 화면 시안을 비개발자가 브라우저로 보게 하는 **정적 서버**를 회사 GitLab 인스턴스에 **한 번** 띄우는 방법. 이 문서는 공통 개발자가 세팅할 때만 연다. 일상 사용법(생성·채택)은 `/ui` 스킬에 있다.
> ★**정본 = 킷.** 허브는 인스턴스에 1개인데 이 문서는 프로젝트마다 복사된다 — 고칠 일이 생기면 **킷을 고치고 배포처로 동기**하라(한 프로젝트 사본만 고치면 다음 프로젝트가 옛 절차를 밟는다). 맨 아래 "실측값 기록"만 각 사본 고유다.

## 무엇인가 (한 문단)
`git-sync`(저장소를 주기적으로 당겨오는 사이드카) + `nginx`(정적 서빙) 파드 하나. 프로젝트 저장소의 `docs/05_UIUX/`를 **≈30초마다 자동 동기**해 `http(s)://<허브호스트>/{프로젝트}/` 로 보여준다. GitLab 웹은 HTML을 **렌더링하지 않고 소스로** 보여주기 때문에(비개발자가 다운로드를 반복해야 함) 이걸 둔다. **앱 검수 서버와는 별개**이고, **프로젝트마다가 아니라 인스턴스에 1개**(프로젝트는 경로로 구분).

## 언제 안 써도 되나 (먼저 확인)
- **GitLab Pages가 정상이면 허브 불필요.** Pages 활성 + CI 아티팩트 정상인 인스턴스면, 각 프로젝트 CI의 `pages` 잡(킷 `.gitlab-ci.yml`에 주석 템플릿)만 켜면 상시 URL이 자동 발행된다. 그게 1순위.
- 이 인스턴스(사내 k8s Helm 설치본)는 **CI 아티팩트 업로드 400 버그**(러너-헬퍼 16.3.0 ↔ 서버 16.4.1 불일치, GitLab #432253)로 Pages 미가용 → 그 우회로 허브를 쓴다. (경위·재개 조건: 파일럿 이슈 #17.) 러너/아티팩트 버그가 풀리면 Pages로 돌아가고 허브는 내려도 된다.

## 세팅 (1회, 약 5분)

### ⓪ 전제 — 시작 전 확인 2가지
- **kubectl 접근**: GitLab이 뜬 그 쿠버네티스 클러스터에 `kubectl`이 되는 셸에서 진행한다(`kubectl get ns`로 접근 확인).
- **DNS**: `<허브호스트>`가 인그레스 IP로 해석돼야 마지막 확인(④)이 된다 — 와일드카드 DNS면 자동, 없으면 A레코드 1개를 먼저 요청해 둔다.
- (표기: 이 문서의 `<허브호스트>` = CLAUDE.md 등 타 문서 `<시안허브URL>`의 호스트 부분.)

### ① 배포 토큰 — 프로젝트마다 1개 (읽기 전용)
프로젝트 → **Settings → Repository → Deploy tokens** → name `sian-sync`, scope **`read_repository`만** → Create → username·token 복사(한 번만 보임).

### ② 쿠버네티스 시크릿
```bash
kubectl -n <네임스페이스> create secret generic sian-git-creds \
  --from-literal=username='<username>' --from-literal=password='<token>'
```
(예: GitLab이 깔린 네임스페이스 — 여기 두면 기존 nginx-ingress·인증서를 재사용.)

### ③ 매니페스트 적용
아래 YAML을 서버에서 `sian-mockups.yaml`로 저장 후 `kubectl apply -f sian-mockups.yaml`.
- ⚠ **긴 YAML을 터미널에 붙여넣으면 공백·따옴표가 깨진다**(실측: `line NN could not find expected ':'`). 깨지면 로컬에서 `base64 -w0 sian-mockups.yaml` 한 덩어리로 만들어 `echo '<base64>' | base64 -d > sian-mockups.yaml && kubectl apply -f sian-mockups.yaml` (공백·따옴표 없어 안 깨짐).

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata: { name: sian-nginx-conf, namespace: <네임스페이스> }
data:
  default.conf: |
    server {
      listen 80;
      server_name <허브호스트>;
      charset utf-8;
      # 허브 루트 = 프로젝트 목록. 프로젝트 추가 시: 아래 location 한 줄 + 이 목록에 <li> 추가 + git-sync 사이드카 1개.
      location = / {
        default_type text/html;
        return 200 '<!doctype html><meta charset="utf-8"><title>시안 허브</title><body style="font:16px system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 16px"><h1>화면 시안 — 프로젝트별</h1><ul><li><a href="/<프로젝트>/"><프로젝트></a></li></ul></body>';
      }
      location /<프로젝트>/ {
        alias /git/head/docs/05_UIUX/;   # git-sync가 당겨온 저장소의 시안 폴더
        autoindex on;                    # index.html 없어도 폴더 목록으로(이중 안전)
        index index.html;                # 있으면 갤러리
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: sian-mockups, namespace: <네임스페이스>, labels: { app: sian-mockups } }
spec:
  replicas: 1
  selector: { matchLabels: { app: sian-mockups } }
  template:
    metadata: { labels: { app: sian-mockups } }
    spec:
      securityContext: { fsGroup: 65533 }   # git-sync(uid 65533) 그룹 소유 → nginx가 읽게
      containers:
      - name: git-sync
        image: registry.k8s.io/git-sync/git-sync:v4.2.4
        args:
        - --repo=<프로젝트 저장소 https URL .git>
        - --ref=main
        - --root=/git
        - --link=head
        - --depth=1
        - --period=30s                      # 30초마다 새 커밋 확인 → 시안 push 후 곧 반영
        - --max-failures=-1
        - -v=2
        env:
        - { name: GITSYNC_USERNAME, valueFrom: { secretKeyRef: { name: sian-git-creds, key: username } } }
        - { name: GITSYNC_PASSWORD, valueFrom: { secretKeyRef: { name: sian-git-creds, key: password } } }
        volumeMounts: [{ name: git, mountPath: /git }]
      - name: nginx
        image: nginx:1.27-alpine
        ports: [{ containerPort: 80 }]
        volumeMounts:
        - { name: git, mountPath: /git, readOnly: true }
        - { name: nginx-conf, mountPath: /etc/nginx/conf.d }
      volumes:
      - { name: git, emptyDir: {} }
      - { name: nginx-conf, configMap: { name: sian-nginx-conf } }
---
apiVersion: v1
kind: Service
metadata: { name: sian-mockups, namespace: <네임스페이스> }
spec:
  selector: { app: sian-mockups }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sian-mockups
  namespace: <네임스페이스>
  annotations:
    # 전용 인증서 없으면 HTTP(비로그인·비밀값 없는 정적 시안이라 무방). 아래 tls 주석 유지.
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  # tls:                                # 운영: <허브호스트> 덮는 인증서 있으면 복원 + ssl-redirect "true"
  # - { hosts: [<허브호스트>], secretName: <인증서 시크릿> }
  rules:
  - host: <허브호스트>
    http:
      paths:
      - { path: /, pathType: Prefix, backend: { service: { name: sian-mockups, port: { number: 80 } } } }
```

### ④ 확인
```bash
kubectl -n <네임스페이스> get pods -l app=sian-mockups        # 2/2 Running
kubectl -n <네임스페이스> logs deploy/sian-mockups -c git-sync --tail=15   # "updated successfully"
```
→ 브라우저 `http(s)://<허브호스트>/<프로젝트>/`

## 자주 막히는 4곳 (실측)
| 증상 | 원인 | 처치 |
| --- | --- | --- |
| `error converting YAML … could not find expected ':'` | 긴 YAML 붙여넣다 공백·따옴표 깨짐 | 위 base64 방식으로 파일 생성 |
| 브라우저 인증서 경고(`ERR_CERT_COMMON_NAME_INVALID`) | 인증서가 `<허브호스트>`를 안 덮음(사내 인증서는 gitlab 전용, 와일드카드 없음) | 파일럿=HTTP(위 매니페스트 그대로) / 운영=`*.<도메인>` 와일드카드 인증서 발급 후 tls 복원 |
| 페이지 자체가 안 뜸 | `<허브호스트>` DNS가 인그레스 IP로 안 잡힘 | 와일드카드 DNS 있으면 자동, 없으면 A레코드 1개 추가 |
| 랜딩·nginx 설정을 바꿨는데 반영 안 됨 | ConfigMap 갱신은 자동 재로드가 안 됨 | `kubectl apply` 후 **`kubectl rollout restart deploy/sian-mockups`**(nginx 재로드) |

## 프로젝트 추가 (2번째부터)
서버 한 대가 전 프로젝트를 담당한다. bnsone 등 새 프로젝트를 붙일 때:
1. 그 프로젝트에서 배포 토큰 발급(①) → 같은 시크릿에 키를 추가하거나 프로젝트별 시크릿 생성.
2. Deployment에 **git-sync 사이드카 1개 더**(그 저장소 `--repo`, `--root=/git-{프로젝트}`, 시크릿은 1번 것 참조) + **`volumes:`에 emptyDir 1개 추가**(기존 볼륨 정의 복제) → 그 볼륨을 **git-sync·nginx 양쪽 컨테이너에 마운트**.
3. ConfigMap에 **`location /{프로젝트}/ { alias /git-{프로젝트}/head/docs/05_UIUX/; … }` 한 블록** + 허브 루트 목록에 `<li>` 추가.
4. `kubectl apply` → `http(s)://<허브호스트>/{프로젝트}/` 생성.

> 실측값 기록(세팅 후 공통 개발자가 여기를 실제 값으로 채운다): 네임스페이스 `<네임스페이스>`, 허브호스트 `<허브호스트>`, 첫 프로젝트 경로 `/<프로젝트>/`, HTTP/HTTPS 여부. 인스턴스의 Pages가 정상화되면 GitLab Pages로 이관 검토.
