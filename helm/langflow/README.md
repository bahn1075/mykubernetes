# Langflow

## 개요

| 항목 | 값 |
|------|----|
| 접속 URL | https://langflow.tail651fca.ts.net |
| Namespace | `langflow` |
| ArgoCD Application | `langflow` |
| Helm Chart | `langflow-ai/langflow-ide` v0.1.2 |
| 이미지 | `docker.io/langflowai/langflow:latest` |

---

## 디렉토리 구조

```
helm/langflow/
├── application.yaml          # ArgoCD Application 정의 (root-app이 자동 인식)
├── values.yaml               # Helm chart override 값
├── manifests/
│   └── ingress.yaml          # Tailscale ingress (chart 내장 ingress 미지원으로 분리)
├── langflow-pv.yaml          # PV 정의 (수동 관리 - ArgoCD 외부)
├── langflow-pvc.yaml         # PVC 정의 (수동 관리 - ArgoCD 외부)
└── official-values.yaml      # 공식 chart 기본값 참조용 (배포 미사용)
```

---

## 아키텍처

```
[Tailscale Client]
       |
       v
[Ingress: langflow-tailscale]  (ingressClassName: tailscale)
       |
       v
[Service: langflow-service :8080]  → [Deployment: langflow-service-frontend]
       |
       v  (API proxy)
[Service: langflow-service-backend :7860]  → [StatefulSet: langflow-service]
       |
       ├──→ [PostgreSQL: postgresql.postgres.svc.cluster.local/langflow]
       └──→ [PVC: langflow-fss-pvc] → [PV: langflow-fss-pv (OCI FSS)]
```

---

## 인프라 구성

### ArgoCD (GitOps) - Multi-source

`application.yaml`은 3개의 소스를 참조한다:

| # | 소스 | 용도 |
|---|------|------|
| 1 | `langflow-ai.github.io/langflow-helm-charts` (chart: langflow-ide) | Helm chart 본체 |
| 2 | `github.com/bahn1075/mykubernetes.git` (`ref: values`) | values.yaml 참조용 |
| 3 | `github.com/bahn1075/mykubernetes.git` (`path: helm/langflow/manifests`) | Tailscale ingress raw manifest |

**root-app 자동 인식**: `root-app`이 `helm/*/application.yaml` 패턴을 감시하므로,
`application.yaml`을 git에 push하면 ArgoCD에 자동 등록된다.

### 스토리지 (OCI FSS)

| 항목 | 값 |
|------|----|
| PV | `langflow-fss-pv` (5Gi, RWX, Retain) |
| PVC | `langflow-fss-pvc` (namespace: langflow) |
| CSI Driver | `fss.csi.oraclecloud.com` |
| Mount Target | `10.0.10.213:/oke-fss` |

컨테이너 내 마운트 경로:

| PVC subPath | 컨테이너 경로 | 용도 |
|-------------|--------------|------|
| `langflow/flows` | `/app/flows` | 플로우 파일 |
| `langflow/data` | `/app/data` | 애플리케이션 데이터 |
| `langflow/db` | `/app/db` | Alembic 마이그레이션 로그 |

> PV/PVC는 ArgoCD가 관리하지 않는다. 클러스터 재구성 시 아래 수동 적용 절차를 따른다.

### 데이터베이스

| 항목 | 값 |
|------|----|
| Host | `postgresql.postgres.svc.cluster.local` |
| Port | `5432` |
| Database | `langflow` |
| User | `langflow` |
| Namespace | `postgres` |

### Ingress

`langflow-ide` chart의 내장 ingress 템플릿이 `ingressClassName`을 지원하지 않아,
`ingress.enabled: false`로 비활성화하고 `manifests/ingress.yaml`을 별도 소스로 배포한다.
Tailscale이 TLS 인증서를 자동 발급하므로 `secretName` 설정 불필요.

---

## Admin 계정 및 패스워드 관리

### superuserPassword 동작 방식

`values.yaml`의 `superuser` / `superuserPassword`는 **DB에 해당 사용자가 존재하지 않을 때만** 적용된다.
Langflow 최초 기동 시 `user` 테이블이 비어 있으면 이 값으로 admin 계정을 생성하고, 이후에는 무시된다.

```
최초 배포 (DB 비어 있음)  → values.yaml의 superuserPassword로 계정 생성  ← 적용됨
재배포 / values 변경      → DB에 이미 계정 존재                           ← 무시됨
```

> 이로 인해 values.yaml의 `superuserPassword`를 변경해도 기존 계정의 패스워드는 바뀌지 않는다.
> 이미 데이터가 있는 DB를 연결한 경우, 해당 DB에 저장된 패스워드(bcrypt 해시)가 그대로 사용된다.

### 패스워드 초기화 / 변경 절차

웹 UI 접속이 불가능한 상황이거나 패스워드를 분실한 경우, DB에서 직접 변경한다.

**1단계: 새 패스워드의 bcrypt 해시 생성**

```bash
kubectl exec -n langflow langflow-service-0 -- python3 -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['bcrypt'], deprecated='auto')
print(ctx.hash('새패스워드입력'))
"
```

**2단계: DB 업데이트**

```bash
kubectl exec -n postgres <postgres-pod> -- psql -U langflow -d langflow -c \
  "UPDATE \"user\" SET password = '<1단계에서 생성한 해시>' WHERE username = 'admin';"
```

**3단계: 확인**

```bash
kubectl exec -n postgres <postgres-pod> -- psql -U langflow -d langflow -c \
  "SELECT username FROM \"user\";"
```

### 기존 DB 연결 시 주의사항

이전 배포에서 사용하던 PostgreSQL DB를 그대로 연결하면 기존 계정과 플로우 데이터가 유지된다.
**패스워드는 이전 배포 당시 설정된 값이 그대로 적용되며**, values.yaml의 `superuserPassword`와 무관하다.

DB를 초기 상태로 리셋하려면 langflow 관련 테이블을 직접 삭제한다:

```bash
kubectl exec -n postgres <postgres-pod> -- psql -U postgres -d langflow -c "
DROP TABLE IF EXISTS vertex_build, transaction, trace, span, sso_user_profile, sso_config,
  message, job, folder, flow, file, apikey, variable, \"user\", alembic_version CASCADE;
"
# 이후 langflow Pod 재시작 → DB 스키마 재생성 및 values.yaml의 superuserPassword로 계정 재생성
kubectl rollout restart statefulset langflow-service -n langflow
```

---

## 운영 절차

### 신규 배포 (클러스터 재구성 시)

ArgoCD 외부 리소스(PV/PVC, Namespace)는 반드시 먼저 수동 적용해야 한다.

**1단계: PV 상태 확인 및 복구**

```bash
# PV가 Released 상태인 경우 claimRef 제거
kubectl get pv langflow-fss-pv
kubectl patch pv langflow-fss-pv -p '{"spec":{"claimRef": null}}'
```

**2단계: Namespace 및 PVC 생성**

```bash
kubectl create namespace langflow
kubectl apply -f helm/langflow/langflow-pvc.yaml
kubectl get pvc langflow-fss-pvc -n langflow  # Bound 확인
```

**3단계: Git push → ArgoCD 자동 배포**

```bash
# application.yaml, values.yaml 변경 후
git add helm/langflow/
git commit -m "..."
git push origin main
# root-app이 application.yaml을 감지해 langflow 앱 자동 등록·배포
```

**4단계: 배포 확인**

```bash
kubectl get application langflow -n argocd
kubectl get pods -n langflow
kubectl get ingress -n langflow
```

---

### 설정 변경

모든 변경은 `values.yaml` 또는 `manifests/` 수정 후 git push로 적용한다.
ArgoCD `selfHeal: true`가 설정되어 있어 git 상태를 기준으로 자동 복구한다.

**이미지 버전 고정 (latest → 특정 버전)**

```yaml
# values.yaml
langflow:
  backend:
    image:
      tag: "1.3.4"          # latest 대신 고정 버전 사용
  frontend:
    image:
      tag: "1.3.4"
```

**Helm chart 버전 업그레이드**

```yaml
# application.yaml
sources:
  - repoURL: https://langflow-ai.github.io/langflow-helm-charts
    chart: langflow-ide
    targetRevision: 0.1.3   # 버전 변경
```

> chart 업그레이드 전 `helm show values langflow/langflow-ide --version 0.1.3`으로
> values 스키마 변경 여부를 반드시 확인한다.

**리소스 조정**

```yaml
# values.yaml
langflow:
  backend:
    resources:
      requests:
        cpu: 200m
        memory: 2Gi
```

**DB 패스워드 변경** (values.yaml 직접 수정 방식)

```yaml
externalDatabase:
  password:
    value: "newpassword"
```

> 보안 강화가 필요한 경우: Secret을 수동 생성하고 `valueFrom.secretKeyRef`로 참조한다.
> ```bash
> kubectl create secret generic langflow-db-secret \
>   --from-literal=LANGFLOW_DB_PASSWORD=newpassword \
>   -n langflow
> ```

---

### 주의 사항 - StatefulSet 변경

StatefulSet의 일부 필드(`serviceName`, `volumeClaimTemplates` 등)는 **불변(immutable)** 이다.
ArgoCD가 이러한 변경을 감지하면 sync 실패가 발생한다.

```bash
# StatefulSet 불변 필드 변경이 필요한 경우: orphan 옵션으로 삭제 후 재생성
kubectl delete statefulset langflow-service -n langflow --cascade=orphan
# 이후 ArgoCD가 새 spec으로 재생성 (Pod는 유지됨)
```

`ignoreDifferences`가 `spec.volumeClaimTemplates`에 설정되어 있어
Kubernetes 기본값 추가로 인한 불필요한 diff는 무시된다.

---

### 헬스 체크 및 모니터링

**기동 시간**: langflow 백엔드는 DB 연결 및 Alembic 마이그레이션 실행으로
**최대 2~3분**이 소요된다. `probe.initialDelaySeconds: 120`으로 설정되어 있다.

```bash
# 파드 상태 확인
kubectl get pods -n langflow

# 백엔드 로그 확인
kubectl logs langflow-service-0 -n langflow

# 헬스 엔드포인트 직접 확인
kubectl exec langflow-service-0 -n langflow -- curl -s http://localhost:7860/health
```

**Prometheus 메트릭**: 백엔드 파드에 아래 어노테이션이 설정되어 있어 자동 수집된다.

```
prometheus.io/scrape: "true"
prometheus.io/port: "9090"
prometheus.io/path: "/metrics"
```

---

### 삭제

**애플리케이션만 삭제 (PV/PVC 유지)**

```bash
# application.yaml을 git에서 제거 후 push → root-app이 자동 삭제
git rm helm/langflow/application.yaml
git commit -m "remove langflow application"
git push origin main
```

> `prune: true` 설정으로 ArgoCD가 연관 리소스를 자동 삭제한다.
> PV는 `Retain` 정책이므로 데이터는 보존된다.

**완전 삭제 (데이터 포함)**

```bash
# 1. ArgoCD application 삭제 (위 절차)
# 2. PVC/Namespace 수동 삭제
kubectl delete pvc langflow-fss-pvc -n langflow
kubectl delete namespace langflow
# 3. PV 삭제 (FSS 데이터 주의)
kubectl delete pv langflow-fss-pv
# 4. PostgreSQL DB 정리
kubectl exec -n postgres <postgres-pod> -- psql -U postgres -d postgres \
  -c "DROP DATABASE IF EXISTS langflow; DROP USER IF EXISTS langflow;"
```

---

## 알려진 이슈 및 트러블슈팅

### ImageInspectError

**원인**: CRI-O 환경에서 `docker.io/` prefix 없는 이미지 사용 시 발생  
**해결**: `values.yaml`의 `image.repository`에 반드시 `docker.io/` prefix 포함

```yaml
image:
  repository: docker.io/langflowai/langflow   # 올바름
  # repository: langflowai/langflow           # CRI-O에서 오류
```

### chart 내장 ingress ingressClassName 미지원

**원인**: `langflow-ide` chart의 ingress 템플릿에 `ingressClassName` 필드가 없음  
**해결**: `ingress.enabled: false`로 비활성화하고 `manifests/ingress.yaml`을 별도 관리

### StatefulSet 업데이트 실패 (immutable field)

**원인**: StatefulSet의 `volumeClaimTemplates` 등 불변 필드 변경 시도  
**해결**: `kubectl delete statefulset langflow-service -n langflow --cascade=orphan` 후 ArgoCD sync

### Fernet key 경고 로그

```
Could not add starter projects MCP server for user admin: Fernet key must be 32 url-safe base64-encoded bytes.
```

**성격**: 비치명적 경고. Starter project의 MCP 서버 프리셋 누락만 발생하며 서비스 운영에 무관  
**해결**: 플로우 내 자격증명을 Pod 재시작 후에도 유지해야 할 경우 고정 Fernet 키 설정

```bash
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

```yaml
# values.yaml
env:
  - name: LANGFLOW_SECRET_KEY
    value: "<생성된 32바이트 base64 키>"
```

### Node ephemeral-storage 부족으로 Pod Evicted

**원인**: `docker.io/langflowai/langflow:latest` 이미지 크기 약 4GB. 노드 ephemeral storage 임계치 초과  
**증상**: `The node was low on resource: ephemeral-storage` 이벤트  
**해결**: 이미지 최초 pull 이후 캐시되므로 일시적 현상. 지속 발생 시 노드 디스크 공간 확보 필요

### PVC Pending 상태

**원인 1**: PV가 `Released` 상태 → `claimRef` 제거 필요  
```bash
kubectl patch pv langflow-fss-pv -p '{"spec":{"claimRef": null}}'
```
**원인 2**: PVC의 `storageClassName: ""`이 누락되면 동적 프로비저닝 시도로 Pending  
→ `langflow-pvc.yaml`의 `storageClassName: ""`과 `volumeName: langflow-fss-pv` 확인

---

## 관련 리소스

| 리소스 | 위치 |
|--------|------|
| Helm Chart 공식 문서 | https://langflow-ai.github.io/langflow-helm-charts |
| ArgoCD Application | `argocd` namespace → `langflow` |
| root-app | `helm/root-app.yaml` |
| PostgreSQL | `postgres` namespace → `postgresql-*` pod |
| Tailscale Operator | `tailscale` namespace |

---

## 작업 이력 - 2026-05-09 파일 업로드 장애 조치

### 증상

- Oracle 커스텀 컴포넌트의 `wallet_file`을 파일 선택창에서 선택해도 UI에 반응이 없었다.
- 공식 Langflow 이미지로 변경해도 기본 `Read File` 컴포넌트의 파일 업로드가 동작하지 않았다.
- 브라우저 사생활 창에서도 동일하게 파일 선택 후 아무 반응이 없었다.

### 확인한 내용

- 백엔드 업로드 API 자체는 정상 동작했다.
  - `/api/v2/files` 직접 업로드: `201 Created`
  - `/api/v1/files/upload/{flow_id}` 직접 업로드: `201 Created`
  - 쿠키 인증 업로드도 정상
- Tailscale ingress는 프론트엔드 nginx 대신 백엔드 서비스로 직접 라우팅하도록 변경했다.
  - `helm/langflow/manifests/ingress.yaml`
  - backend service: `langflow-service-backend`
  - port: `7860`
- JWT/Fernet 관련 오류를 줄이기 위해 `LANGFLOW_SECRET_KEY`에 유효한 Fernet key를 고정했다.
- probe 대기 시간이 과하게 길어 운영 피드백이 늦어지는 문제가 있어 백엔드 probe 값을 줄였다.

### 원인

Langflow `1.9.2` 프론트엔드 번들의 파일 선택 헬퍼가 파일 선택창 focus 복귀 후 `100ms` 안에 `change` 이벤트가 오지 않으면 빈 파일 목록으로 처리하는 구조였다.

일부 브라우저/환경에서는 실제 파일 선택 `change` 이벤트보다 focus 복귀 타이머가 먼저 실행되어, 파일을 선택해도 업로드 요청이 발생하지 않고 UI도 갱신되지 않았다.

백엔드 로그에 업로드 실패가 남지 않았던 이유는 브라우저가 업로드 API 요청까지 도달하지 못했기 때문이다.

### 적용한 변경

#### Ingress

Tailscale ingress를 백엔드로 직접 연결했다.

```yaml
backend:
  service:
    name: langflow-service-backend
    port:
      number: 7860
```

적용 커밋:

- `084671b fix: route langflow ingress to backend`

#### Probe

백엔드 probe를 적절히 단축했다.

```yaml
probe:
  failureThreshold: 6
  periodSeconds: 10
  timeoutSeconds: 5
  initialDelaySeconds: 20
```

적용 커밋:

- `590b1b3 fix: reduce langflow backend probe delay`

#### Secret key

Langflow secret key를 유효한 Fernet key로 고정했다.

```yaml
secretKey: "RuKHMArwWCAIeQbHuCJf3OAFP0rVoz2Gr7Lxx2gzkY8="
```

적용 커밋:

- `eed4188 fix: set valid langflow secret key`

#### Custom image 복구

Oracle 의존성이 포함된 커스텀 이미지를 다시 사용하도록 복구했다.

```yaml
image:
  repository: docker.io/bahn1075/langflow-custom
  tag: aarch64-20260509-1710
```

적용 커밋:

- `c36a6f1 fix: restore custom langflow backend image`

#### 파일 선택 프론트엔드 패치

커스텀 이미지 base를 `latest` 대신 `langflowai/langflow:1.9.2`로 고정했다.

또한 빌드 단계에서 프론트엔드 번들의 파일 선택 focus timeout을 `100ms`에서 `3000ms`로 늘리는 패치를 적용했다.

최종 배포 이미지:

```text
docker.io/bahn1075/langflow-custom:aarch64-20260509-1915
```

적용 커밋:

- `a47b59a fix: patch langflow file picker upload`

### 검증 결과

- ArgoCD 상태: `Synced / Healthy`
- Pod 상태: `Running`
- 배포 이미지:

```text
docker.io/bahn1075/langflow-custom:aarch64-20260509-1915
```

- 외부 헬스 체크:

```bash
curl -k https://langflow.tail651fca.ts.net/health
# {"status":"ok"}
```

- 배포된 프론트엔드 번들 확인:
  - 기존 `100ms` 패턴 없음
  - 변경된 `3000ms` 패턴 있음
- 새 Pod에서 `/api/v2/files` 업로드 재검증: `201 Created`
- 브라우저 UI에서 파일 업로드 정상 동작 확인

### 운영 메모

- `latest` 태그를 사용할 수는 있지만, 빌드 시점마다 Langflow 버전과 프론트엔드 번들이 바뀔 수 있어 운영 환경에서는 권장하지 않는다.
- 현재처럼 검증된 버전(`1.9.2`)을 고정하고 필요한 패치를 명시적으로 적용하는 방식이 안전하다.
- 향후 Langflow upstream에서 파일 선택 버그가 수정된 버전이 나오면, 새 고정 버전으로 올린 뒤 Dockerfile의 프론트엔드 번들 패치를 제거할 수 있다.
