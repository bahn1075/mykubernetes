# Monitoring Stack ArgoCD 배포 가이드

이 디렉토리에는 `/app/mykubernetes/monitoring/old`의 Helm values 파일들을 ArgoCD용으로 변환한 Application 매니페스트가 포함되어 있습니다.

## 배포 방법

### 옵션 1: 개별 배포 (권장)

각 컴포넌트를 독립적으로 배포하여 세밀한 제어가 가능합니다.

```bash
# 모든 컴포넌트 배포
kubectl apply -f /app/mykubernetes/monitoring/argocd-apps/

# 또는 개별 배포
kubectl apply -f /app/mykubernetes/monitoring/argocd-apps/prometheus.yaml
kubectl apply -f /app/mykubernetes/monitoring/argocd-apps/loki.yaml
kubectl apply -f /app/mykubernetes/monitoring/argocd-apps/tempo.yaml
kubectl apply -f /app/mykubernetes/monitoring/argocd-apps/promtail.yaml
kubectl apply -f /app/mykubernetes/monitoring/argocd-apps/alloy.yaml
```

### 옵션 2: ApplicationSet 사용

하나의 매니페스트로 모든 컴포넌트를 관리합니다 (values는 별도 수정 필요).

```bash
kubectl apply -f /app/mykubernetes/monitoring/argocd-apps/monitoring-stack-set.yaml
```

> **참고**: ApplicationSet은 공통 구조를 사용하므로, values는 개별 Application 파일을 사용하는 것을 권장합니다.

## 파일 구조

```
argocd-apps/
├── prometheus.yaml              # Prometheus + AlertManager + Operator
├── loki.yaml                    # Loki (로그 저장소)
├── tempo.yaml                   # Tempo (트레이스 저장소)
├── promtail.yaml               # Promtail (로그 수집기)
├── alloy.yaml                  # Grafana Alloy (로그 수집기 - 대체)
├── monitoring-stack-set.yaml   # ApplicationSet (통합)
└── README.md                   # 이 파일
```

## 컴포넌트 설명

### 1. Prometheus (Chart: kube-prometheus-stack)
- **버전**: 69.2.0
- **포함**: Prometheus + AlertManager + Prometheus Operator + Node Exporter + kube-state-metrics
- **리포지토리**: https://prometheus-community.github.io/helm-charts
- **네임스페이스**: monitoring

### 2. Loki
- **버전**: 6.22.0
- **모드**: SingleBinary (단일 바이너리)
- **저장소**: Filesystem (임시)
- **보관 기간**: 5일 (120시간)
- **리포지토리**: https://grafana.github.io/helm-charts

### 3. Tempo
- **버전**: 1.10.1
- **프로토콜**: OTLP, Jaeger, Zipkin
- **저장소**: Local (임시)
- **보관 기간**: 5일 (120시간)
- **리포지토리**: https://grafana.github.io/helm-charts

### 4. Promtail
- **버전**: 6.16.6
- **배포**: DaemonSet (모든 노드)
- **수집**: Kubernetes Pod 로그
- **전송**: Loki
- **리포지토리**: https://grafana.github.io/helm-charts

### 5. Alloy (선택사항)
- **버전**: 0.13.0
- **설명**: Promtail의 대체제
- **배포**: DaemonSet
- **리포지토리**: https://grafana.github.io/helm-charts

> **참고**: Promtail과 Alloy 중 하나만 사용하면 됩니다.

## 배포 순서 (권장)

```bash
# 1. Loki 먼저 배포 (로그 저장소)
kubectl apply -f loki.yaml

# 2. Loki가 준비될 때까지 대기
kubectl wait --for=condition=available --timeout=300s deployment/loki -n monitoring

# 3. Promtail 배포 (로그 수집)
kubectl apply -f promtail.yaml

# 4. Tempo 배포 (트레이스 저장소)
kubectl apply -f tempo.yaml

# 5. Prometheus 배포 (메트릭 수집)
kubectl apply -f prometheus.yaml
```

## 확인

```bash
# ArgoCD Application 상태 확인
kubectl get applications -n argocd

# ArgoCD CLI로 확인
argocd app list

# 각 컴포넌트 상태 확인
argocd app get prometheus
argocd app get loki
argocd app get tempo
argocd app get promtail

# Kubernetes 리소스 확인
kubectl get all -n monitoring

# Pod 상태 확인
kubectl get pods -n monitoring
```

## ArgoCD UI에서 확인

1. ArgoCD UI 접속
2. Applications 목록에서 다음을 확인:
   - `prometheus`
   - `loki`
   - `tempo`
   - `promtail` 또는 `alloy`

## 문제 해결

### Loki Gateway 연결 오류
Promtail에서 `loki-gateway` 연결 오류가 발생하면:

```bash
# Loki 서비스 이름 확인
kubectl get svc -n monitoring | grep loki

# Promtail values에서 URL 수정 (필요시)
# loki-gateway 대신 loki 또는 loki-svc 사용
```

### ApplicationSet values 적용
ApplicationSet을 사용하려면 각 차트의 values를 valuesObject에 직접 추가해야 합니다:

```yaml
valuesObject:
  # prometheus values
  grafana:
    enabled: false
  # ... 기타 설정
```

## 원본 Values 파일 위치

모든 values는 다음 경로의 파일에서 가져왔습니다:
- `/app/mykubernetes/monitoring/old/prometheus-values.yaml`
- `/app/mykubernetes/monitoring/old/loki-values.yaml`
- `/app/mykubernetes/monitoring/old/tempo-values.yaml`
- `/app/mykubernetes/monitoring/old/promtail-values.yaml`
- `/app/mykubernetes/monitoring/old/alloy-values.yaml`

## 추가 설정

각 Application의 values는 해당 `.yaml` 파일의 `spec.source.helm.values` 섹션에서 수정할 수 있습니다.

예시:
```bash
# Prometheus values 수정
vi prometheus.yaml
# spec.source.helm.values 섹션 수정
kubectl apply -f prometheus.yaml
```
