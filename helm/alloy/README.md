# Grafana Alloy Helm Deployment

Grafana Alloy는 로그 수집을 위한 OpenTelemetry Collector 기반 에이전트입니다.

## 파일 구조

```
helm/alloy/
├── application.yaml  # ArgoCD Application 매니페스트
├── values.yaml       # Helm values 설정
└── README.md         # 이 파일
```

## 배포 방법

### 방법 1: ArgoCD를 통한 배포 (권장)

```bash
# ArgoCD Application 등록
kubectl apply -f /app/mykubernetes/helm/alloy/application.yaml

# 상태 확인
kubectl get application alloy -n argocd

# 상세 상태 확인
argocd app get alloy
```

> **참고**: `kubectl apply` 시 네임스페이스를 별도로 지정하지 않아도 됩니다.
> `application.yaml` 파일 내에 `namespace: argocd`가 이미 지정되어 있습니다.
>
> - **ArgoCD Application 리소스**: `argocd` 네임스페이스에 생성
> - **실제 Alloy 워크로드**: `monitoring` 네임스페이스에 배포

### 방법 2: Helm CLI 직접 배포

```bash
# 설치
helm upgrade --install alloy grafana/alloy \
  --namespace monitoring \
  --create-namespace \
  -f /app/mykubernetes/helm/alloy/values.yaml

# 삭제
helm uninstall alloy -n monitoring
```

## ArgoCD Application 설명

`application.yaml`은 Multiple Sources 방식을 사용합니다:

- **Helm Chart**: `grafana` repo에서 `alloy` 차트 직접 참조
- **Values**: Git repo의 `helm/alloy/values.yaml` 참조

이 방식의 장점:
- 차트 파일들을 Git에 저장할 필요 없음
- values.yaml만 관리하면 됨
- 차트 버전 업그레이드가 간편함 (targetRevision만 변경)

## 차트 버전 업그레이드

`application.yaml`에서 `targetRevision` 값을 변경:

```yaml
sources:
  - repoURL: https://grafana.github.io/helm-charts
    chart: alloy
    targetRevision: 1.5.2  # 원하는 버전으로 변경
```

최신 버전 확인:
```bash
helm search repo grafana/alloy --versions | head -10
```

## 현재 설정 요약

- **배포 모드**: DaemonSet (모든 노드에서 로그 수집)
- **로그 전송 대상**: Loki (`http://loki.monitoring.svc.cluster.local:3100`)
- **수집 대상**: Kubernetes Pod 로그
- **Label 매핑**: app, app.kubernetes.io/name → service_name

## 트러블슈팅

### Sync 상태 확인
```bash
kubectl get application alloy -n argocd -o jsonpath='{.status.sync.status}'
```

### 에러 로그 확인
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Pod 상태 확인
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy
```

### Alloy 로그 확인
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=100
```

### Alloy 설정 확인
```bash
kubectl get configmap -n monitoring -l app.kubernetes.io/name=alloy -o yaml
```
