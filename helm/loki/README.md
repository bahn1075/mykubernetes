# Loki Helm Deployment

## 파일 구조

```
helm/loki/
├── application.yaml  # ArgoCD Application 매니페스트
├── values.yaml       # Helm values 설정
└── README.md         # 이 파일
```

## 배포 방법

### 방법 1: ArgoCD를 통한 배포 (권장)

```bash
# ArgoCD Application 등록
kubectl apply -f /app/mykubernetes/helm/loki/application.yaml

# 상태 확인
kubectl get application loki -n argocd

# 상세 상태 확인
argocd app get loki
```

> **참고**: `kubectl apply` 시 네임스페이스를 별도로 지정하지 않아도 됩니다.
> `application.yaml` 파일 내에 `namespace: argocd`가 이미 지정되어 있습니다.
>
> - **ArgoCD Application 리소스**: `argocd` 네임스페이스에 생성
> - **실제 Loki 워크로드**: `monitoring` 네임스페이스에 배포

### 방법 2: Helm CLI 직접 배포

```bash
# 설치
helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --create-namespace \
  -f /app/mykubernetes/helm/loki/values.yaml

# 삭제
helm uninstall loki -n monitoring
```

## ArgoCD Application 설명

`application.yaml`은 Multiple Sources 방식을 사용합니다:

- **Helm Chart**: `grafana` repo에서 `loki` 차트 직접 참조
- **Values**: Git repo의 `helm/loki/values.yaml` 참조

이 방식의 장점:
- 차트 파일들을 Git에 저장할 필요 없음
- values.yaml만 관리하면 됨
- 차트 버전 업그레이드가 간편함 (targetRevision만 변경)

## 차트 버전 업그레이드

`application.yaml`에서 `targetRevision` 값을 변경:

```yaml
sources:
  - repoURL: https://grafana.github.io/helm-charts
    chart: loki
    targetRevision: 6.49.0  # 원하는 버전으로 변경
```

최신 버전 확인:
```bash
helm search repo grafana/loki --versions | head -10
```

## 현재 설정 요약

- **배포 모드**: SingleBinary (단일 인스턴스)
- **스토리지**: Filesystem (PVC 사용 - `loki-fss-pvc`)
- **로그 보관**: 7일 (168시간)
- **인증**: 비활성화
- **모니터링/Canary**: 비활성화

## 트러블슈팅

### Sync 상태 확인
```bash
kubectl get application loki -n argocd -o jsonpath='{.status.sync.status}'
```

### 에러 로그 확인
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Pod 상태 확인
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
```

### Loki 로그 확인
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=100
```

### Loki 서비스 테스트
```bash
# Loki ready 상태 확인
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://localhost:3100/ready

# Loki 메트릭 확인
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://localhost:3100/metrics | head -20
```
