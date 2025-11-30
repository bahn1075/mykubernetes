# Kubernetes Full Stack Monitoring

이 디렉토리는 Kubernetes 클러스터에 완전한 모니터링 스택을 배포하기 위한 설정 파일들을 포함합니다.

## 구성 요소

- **Prometheus**: 메트릭 수집 및 저장
- **Grafana**: 시각화 및 대시보드
- **Loki**: 로그 집계 및 저장
- **Grafana Alloy**: 로그 수집 에이전트 (Promtail 대체)

## OCI FSS 통합 스토리지 구성

이 모니터링 스택은 **통합 OCI FSS(File Storage Service)**를 사용하여 데이터를 영구적으로 저장합니다.

### 통합 FSS 구조
- **단일 파일시스템**: `oke-fss-unified`
- **단일 마운트 포인트**: `/oke_fss`
- **앱별 서브디렉토리 사용**:
  - `/oke_fss/grafana` - Grafana 데이터
  - `/oke_fss/phoenix_postgres` - Phoenix PostgreSQL 데이터
  - `/oke_fss/jenkins` - Jenkins 데이터 (예정)

### 장점
- ✅ **리소스 효율성**: 단일 FSS로 여러 앱 지원
- ✅ **확장성**: OCI 마운트 타겟 제한 우회
- ✅ **데이터 영속성**: Pod 재시작 시에도 데이터 보존
- ✅ **관리 용이성**: 통합된 스토리지 관리

자세한 내용은 [FSS-UNIFIED-SETUP.md](FSS-UNIFIED-SETUP.md)를 참조하세요.

## 주요 특징

- ✅ **최신 이미지 사용**: Grafana는 `latest` 태그 사용, 나머지는 Helm chart 기본 최신 버전 사용
- ✅ **개별 컴포넌트 설치**: Stack 기술 대신 각 컴포넌트를 개별적으로 설치
- ✅ **Grafana 외부 접근**: LoadBalancer Service로 외부 접근 설정
- ✅ **Loki 스토리지 안정성**: `/tmp` 기반 스토리지로 권한 문제 해결
- ✅ **Grafana Alloy 사용**: Promtail 대신 최신 로그 수집 에이전트 사용
- ✅ **emptyDir 스토리지**: Prometheus와 AlertManager에 emptyDir 사용으로 권한 문제 회피
- ✅ **간소화된 설정**: 권한 문제 해결을 위한 최적화된 구성

## 파일 구조

```
monitoring/
├── 00-namespace.yaml              # 네임스페이스 정의
├── prometheus-values.yaml         # Prometheus 설정 (emptyDir 사용)
├── grafana-values.yaml            # Grafana 설정 (통합 FSS 사용)
├── grafana-service.yaml           # Grafana LoadBalancer Service 설정
├── grafana-fss-pv.yaml            # Grafana FSS PV (레거시)
├── grafana-fss-pvc.yaml           # Grafana FSS PVC (레거시)
├── unified-fss-pv.yaml            # 통합 FSS PV (Grafana용)
├── unified-fss-pvc.yaml           # 통합 FSS PVC (Grafana용)
├── loki-values.yaml               # Loki 설정 (SingleBinary 모드, /tmp 스토리지)
├── alloy-values.yaml              # Grafana Alloy 설정 (로그 수집)
├── FSS-UNIFIED-SETUP.md           # 통합 FSS 구성 가이드
├── apply-unified-fss.sh           # 통합 FSS 적용 스크립트
├── cleanup-old-fss.sh             # 기존 FSS 정리 스크립트
├── check-images.sh                # Pod 이미지 버전 확인 스크립트
├── install.sh                     # 설치 스크립트
├── uninstall.sh                   # 제거 스크립트
└── README.md                      # 이 파일
```

## 설치 방법

### 사전 요구사항

1. **Kubernetes 클러스터** (minikube, kind, 실제 클러스터 등)
2. **kubectl** 설치 및 클러스터 연결 설정
3. **Helm 3.x** 설치
4. **Ingress Controller** (nginx-ingress 권장)

```bash
# Ingress Controller 설치 (nginx)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

### 자동 설치

```bash
# 실행 권한 부여
chmod +x install.sh

# 설치 실행
./install.sh
```

### 수동 설치

1. **네임스페이스 생성**
```bash
kubectl apply -f 00-namespace.yaml
```

2. **Helm 저장소 추가**
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

3. **각 컴포넌트 설치**
```bash
# Prometheus (emptyDir 스토리지 사용)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --values prometheus-values.yaml

# Loki (/tmp 스토리지 사용)
helm install loki grafana/loki \
  --namespace monitoring --values loki-values.yaml

# Grafana Alloy (로그 수집)
helm install alloy grafana/alloy \
  --namespace monitoring --values alloy-values.yaml

# Grafana
helm install grafana grafana/grafana \
  --namespace monitoring --values grafana-values.yaml

# Grafana LoadBalancer Service
kubectl apply -f grafana-service.yaml
```

## 접속 정보

### Grafana 접속

- **사용자명**: admin
- **비밀번호**: admin123

#### Minikube 환경에서 접속

```bash
# 방법 1: Minikube service 명령어 사용 (브라우저 자동 열림)
minikube service grafana -n monitoring

# 방법 2: Port Forward
kubectl port-forward -n monitoring svc/grafana 3000:80
# 접속: http://localhost:3000

# 방법 3: LoadBalancer IP 확인 (minikube tunnel 필요)
minikube tunnel
# 다른 터미널에서:
kubectl get svc -n monitoring grafana
```

### Port Forward를 통한 접속

Ingress가 설정되지 않은 경우 다음 명령어로 접속할 수 있습니다:

```bash
# Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# AlertManager
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093
```

## 데이터 소스 설정

Grafana에 다음 데이터 소스들이 자동으로 설정됩니다:

1. **Prometheus**: `http://prometheus-operated.monitoring.svc.cluster.local:9090`
2. **Loki**: `http://loki.monitoring.svc.cluster.local:3100`

### Grafana에서 로그 확인 방법

1. Grafana **Explore** 메뉴로 이동
2. 데이터소스를 **Loki** 선택
3. 다음 쿼리 사용:
   - `{namespace="monitoring"}` - monitoring 네임스페이스의 모든 로그
   - `{pod="grafana-67b7ff4c86-4lvgk"}` - 특정 Pod 로그
   - `{job="loki.source.kubernetes.pods"}` - Alloy가 수집한 모든 로그

## 기본 대시보드

설치 시 다음 대시보드들이 자동으로 임포트됩니다:

### Kubernetes 관련
- **Kubernetes Cluster Monitoring** (ID: 7249)
- **Kubernetes Cluster Overview** (ID: 8588)
- **Kubernetes Pods** (ID: 6417)
- **Kubernetes StatefulSet** (ID: 8684)

### Node & System 관련
- **Node Exporter Full** (ID: 1860)
- **Node Exporter Server Metrics** (ID: 405)
- **System Overview** (ID: 3590)
- **Linux System Overview** (ID: 12486)

### 컨테이너 & Docker 관련
- **Docker Containers** (ID: 179)
- **Container Metrics** (ID: 11600)

### 모니터링 스택 관련
- **Prometheus Overview** (ID: 3662)
- **Prometheus Stats** (ID: 2)
- **Loki Dashboard** (ID: 13639)
- **Loki Logs** (ID: 12019)
- **AlertManager Overview** (ID: 9578)

### 네트워크 관련
- **Network Overview** (ID: 12177)

## 모니터링 대상

### Prometheus
- Kubernetes 클러스터 메트릭
- Node Exporter 메트릭
- kube-state-metrics
- Loki 메트릭

### Loki (via Grafana Alloy)
- 모든 Kubernetes Pod 로그
- 네임스페이스별 로그 수집
- 컨테이너별 로그 구분

## 스토리지 설정

### OCI FSS 통합 스토리지 (권장)
- **Grafana**: 통합 FSS `/oke_fss/grafana` 사용 (영구 저장)
  - PV: `grafana-unified-fss-pv`
  - PVC: `grafana-unified`
  - 데이터 영속성 보장

### emptyDir 사용 컴포넌트 (개발/테스트)
- **Prometheus**: 10Gi emptyDir (Pod 재시작 시 데이터 손실)
- **AlertManager**: 2Gi emptyDir (Pod 재시작 시 데이터 손실)
- **Loki**: `/tmp` 기반 임시 저장소 (Pod 재시작 시 로그 손실)

> **참고**: 
> - **Grafana**: OCI FSS 통합 스토리지로 데이터 영속성 보장
> - **운영 환경**: Prometheus, Loki도 FSS 사용 권장
> - 통합 FSS 구성 가이드: [FSS-UNIFIED-SETUP.md](FSS-UNIFIED-SETUP.md)

## 이미지 버전 정보

현재 사용 중인 주요 컴포넌트 이미지 버전:

- **Grafana**: `latest` (개발 환경용)
- **Prometheus**: `v3.7.3` (Prometheus Operator v0.86.2 관리)
- **AlertManager**: `v0.29.0` (Prometheus Operator v0.86.2 관리)
- **Loki**: `3.5.7` (Helm chart 기본 버전)
- **Grafana Alloy**: `v1.11.3` (안정 최신 버전)
- **Node Exporter**: `v1.10.2` (최신 버전)
- **Kube State Metrics**: `v2.17.0` (최신 버전)

> **참고**: Prometheus, AlertManager는 Prometheus Operator가 관리하므로 Operator 버전과의 호환성을 위해 
> 특정 버전이 유지됩니다. 모든 버전은 충분히 최신이며 안정적입니다.

### 이미지 버전 확인 스크립트

현재 실행 중인 Pod의 이미지 버전과 Docker Hub의 최신 버전을 확인하는 스크립트가 제공됩니다.

```bash
# 기본 사용 (monitoring 네임스페이스)
./check-images.sh

# 다른 네임스페이스 확인
./check-images.sh <네임스페이스명>
```

**스크립트 기능:**
- 현재 실행 중인 모든 Pod의 이미지 목록 표시
- 주요 컴포넌트 이미지 버전 표시 (중복 제거)
- Docker Hub에서 각 컴포넌트의 최신 태그 5개 조회
- 현재 버전과 최신 버전 비교 가능

## 제거 방법

```bash
# 실행 권한 부여
chmod +x uninstall.sh

# 제거 실행
./uninstall.sh
```

## 문제 해결

### 1. Pod가 시작되지 않는 경우

```bash
# Pod 상태 확인
kubectl get pods -n monitoring

# 특정 Pod 로그 확인
kubectl logs -n monitoring <pod-name>

# Pod 상세 정보 확인
kubectl describe pod -n monitoring <pod-name>
```

### 2. 스토리지 문제

```bash
# PVC 상태 확인
kubectl get pvc -n monitoring

# 스토리지 클래스 확인
kubectl get storageclass
```

### 3. Ingress 접속 문제

```bash
# Ingress 상태 확인
kubectl get ingress -n monitoring

# Ingress Controller 확인
kubectl get pods -n ingress-nginx

# Ingress Controller 로그 확인
kubectl logs -n ingress-nginx <ingress-controller-pod>
```

### 4. 서비스 연결 문제

```bash
# 서비스 상태 확인
kubectl get svc -n monitoring

# 엔드포인트 확인
kubectl get endpoints -n monitoring
```

## 추가 설정

### Slack 알림 설정

`prometheus-values.yaml`의 AlertManager 설정에서 Slack 웹훅을 추가할 수 있습니다.

### 추가 대시보드 임포트

Grafana UI에서 Dashboard > Import를 통해 추가 대시보드를 임포트할 수 있습니다.

### 커스텀 알람 규칙

`prometheus-values.yaml`에서 추가 알람 규칙을 정의할 수 있습니다.

## 지원

문제가 발생하거나 추가 설정이 필요한 경우, 각 컴포넌트의 공식 문서를 참조하세요:

- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [Loki](https://grafana.com/docs/loki/)
- [Grafana Alloy](https://grafana.com/docs/alloy/)

## 문제 해결 가이드

### 1. PVC 권한 문제

**증상**: Pod가 `CreateContainerConfigError` 또는 "permission denied" 오류로 시작 실패

**해결책**: emptyDir 사용
```yaml
# prometheus-values.yaml
prometheus:
  prometheusSpec:
    storageSpec:
      emptyDir:
        sizeLimit: 10Gi
```

### 2. Loki read-only 파일시스템 오류

**증상**: "mkdir /var/loki: read-only file system"

**해결책**: `/tmp` 경로 사용
```yaml
# loki-values.yaml
loki:
  commonConfig:
    path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
```

### 3. Promtail "too many open files" 오류

**증상**: Promtail Pod가 "too many open files" 오류로 CrashLoopBackOff

**해결책**: Grafana Alloy 사용
```bash
helm install alloy grafana/alloy --namespace monitoring --values alloy-values.yaml
```

### 4. Loki Canary 로그 과다 생성

**증상**: loki-canary Pod에서 "failed to create fsnotify watcher: too many open files" 반복 로그

**해결책**: Loki Canary 비활성화
```yaml
# loki-values.yaml
lokiCanary:
  enabled: false
```

**적용**:
```bash
helm upgrade loki grafana/loki --namespace monitoring --values loki-values.yaml
```

> **참고**: Loki Canary는 로그 수집 테스트용 도구로, 개발 환경에서는 불필요합니다.
