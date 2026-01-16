# Prometheus (kube-prometheus-stack) Helm Deployment

## 파일 구조

```
helm/prometheus/
├── application.yaml  # ArgoCD Application 매니페스트
├── values.yaml       # Helm values 설정
└── README.md         # 이 파일
```

## 배포 방법

### 방법 1: ArgoCD를 통한 배포 (권장)

```bash
# ArgoCD Application 등록
kubectl apply -f /app/mykubernetes/helm/prometheus/application.yaml

# 상태 확인
kubectl get application prometheus -n argocd

# 상세 상태 확인
argocd app get prometheus
```

> **참고**: `kubectl apply` 시 네임스페이스를 별도로 지정하지 않아도 됩니다.
> `application.yaml` 파일 내에 `namespace: argocd`가 이미 지정되어 있습니다.
>
> - **ArgoCD Application 리소스**: `argocd` 네임스페이스에 생성
> - **실제 Prometheus 워크로드**: `monitoring` 네임스페이스에 배포

### 방법 2: Helm CLI 직접 배포

```bash
# 설치
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f /app/mykubernetes/helm/prometheus/values.yaml

# 삭제
helm uninstall prometheus -n monitoring
```

## ArgoCD Application 설명

`application.yaml`은 Multiple Sources 방식을 사용합니다:

- **Helm Chart**: `prometheus-community` repo에서 `kube-prometheus-stack` 차트 직접 참조
- **Values**: Git repo의 `helm/prometheus/values.yaml` 참조

이 방식의 장점:
- 차트 파일들을 Git에 저장할 필요 없음
- values.yaml만 관리하면 됨
- 차트 버전 업그레이드가 간편함 (targetRevision만 변경)

## 차트 버전 업그레이드

`application.yaml`에서 `targetRevision` 값을 변경:

```yaml
sources:
  - repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 80.14.3  # 원하는 버전으로 변경
```

최신 버전 확인:
```bash
helm search repo prometheus-community/kube-prometheus-stack --versions | head -10
```

## 트러블슈팅

### Sync 상태 확인
```bash
kubectl get application prometheus -n argocd -o jsonpath='{.status.sync.status}'
```

### 에러 로그 확인
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Pod 상태 확인
```bash
kubectl get pods -n monitoring -l release=prometheus
```
