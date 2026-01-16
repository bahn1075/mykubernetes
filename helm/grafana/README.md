# Grafana Helm Deployment

Grafana는 메트릭, 로그, 트레이스를 시각화하는 모니터링 대시보드입니다.

## 파일 구조

```
helm/grafana/
├── application.yaml  # ArgoCD Application 매니페스트
├── values.yaml       # Helm values 설정
└── README.md         # 이 파일
```

## 사전 요구사항

배포 전 다음 리소스가 필요합니다:

```bash
# 1. Admin 시크릿 생성
kubectl create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<YOUR_PASSWORD> \
  -n monitoring

# 2. PVC 생성 (기존 PV 사용 시)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-pvc
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: ""
  volumeName: <YOUR_PV_NAME>
EOF

# 3. 대시보드 ConfigMap (선택사항)
kubectl create configmap grafana-dashboards \
  --from-file=dashboards/ \
  -n monitoring
```

## 배포 방법

### 방법 1: ArgoCD를 통한 배포 (권장)

```bash
# ArgoCD Application 등록
kubectl apply -f /app/mykubernetes/helm/grafana/application.yaml

# 상태 확인
kubectl get application grafana -n argocd

# 상세 상태 확인
argocd app get grafana
```

> **참고**: `kubectl apply` 시 네임스페이스를 별도로 지정하지 않아도 됩니다.
> `application.yaml` 파일 내에 `namespace: argocd`가 이미 지정되어 있습니다.
>
> - **ArgoCD Application 리소스**: `argocd` 네임스페이스에 생성
> - **실제 Grafana 워크로드**: `monitoring` 네임스페이스에 배포

### 방법 2: Helm CLI 직접 배포

```bash
# 설치
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --create-namespace \
  -f /app/mykubernetes/helm/grafana/values.yaml

# 삭제
helm uninstall grafana -n monitoring
```

## ArgoCD Application 설명

`application.yaml`은 Multiple Sources 방식을 사용합니다:

- **Helm Chart**: `grafana` repo에서 `grafana` 차트 직접 참조
- **Values**: Git repo의 `helm/grafana/values.yaml` 참조

이 방식의 장점:
- 차트 파일들을 Git에 저장할 필요 없음
- values.yaml만 관리하면 됨
- 차트 버전 업그레이드가 간편함 (targetRevision만 변경)

## 차트 버전 업그레이드

`application.yaml`에서 `targetRevision` 값을 변경:

```yaml
sources:
  - repoURL: https://grafana.github.io/helm-charts
    chart: grafana
    targetRevision: 10.5.8  # 원하는 버전으로 변경
```

최신 버전 확인:
```bash
helm search repo grafana/grafana --versions | head -10
```

## 현재 설정 요약

- **Ingress**: grafana.64bit.kr (nginx ingress)
- **데이터소스**: Prometheus, Loki, Tempo
- **스토리지**: PVC (grafana-pvc) with subPath
- **인증**: 기존 시크릿 (grafana-admin) 사용
- **플러그인**: grafana-piechart-panel, grafana-worldmap-panel

## 접속 정보

```bash
# Ingress를 통한 접속
http://grafana.64bit.kr

# 포트포워딩 (Ingress 없이)
kubectl port-forward svc/grafana 3000:80 -n monitoring
# 접속: http://localhost:3000
```

## 트러블슈팅

### Sync 상태 확인
```bash
kubectl get application grafana -n argocd -o jsonpath='{.status.sync.status}'
```

### 에러 로그 확인
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Pod 상태 확인
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
```

### Grafana 로그 확인
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=100
```

### Admin 비밀번호 확인
```bash
kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```
