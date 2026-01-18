# K6 Operator 개발 환경 설치 가이드

## 개요

K6 Operator는 Kubernetes에서 k6 부하 테스트를 실행할 수 있게 해주는 Operator입니다.

## 설치

### 1. K6 Operator 설치

```bash
# Helm 저장소 추가
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# k6-operator 네임스페이스에 설치
helm install k6-operator grafana/k6-operator \
  --namespace k6-operator \
  --create-namespace \
  --values dev-values.yaml
```

### 2. 설치 확인

```bash
# Pod 상태 확인
kubectl get pods -n k6-operator

# Service 확인
kubectl get svc -n k6-operator

# CRD 확인
kubectl get crd | grep k6
```

## 주요 설정

### 개발 환경 최적화

- **리소스 제한**: CPU 200m, Memory 200Mi (소규모 환경)
- **단일 Replica**: 고가용성 불필요
- **개발 모드 로깅**: 사람이 읽기 쉬운 형식
- **LoadBalancer Service**: MetalLB를 통한 외부 접근

### Prometheus 모니터링

- **ServiceMonitor 활성화**: Prometheus가 자동으로 메트릭 수집
- **메트릭 수집 간격**: 30초
- **타겟 네임스페이스**: monitoring

## 사용 방법

### 1. 간단한 테스트 실행

```bash
# 샘플 테스트 실행
kubectl apply -f samples/k6-test-simple.yaml

# 테스트 상태 확인
kubectl get k6 -n k6-operator

# 테스트 Pod 확인
kubectl get pods -n k6-operator

# 테스트 로그 확인
kubectl logs -f <k6-test-pod-name> -n k6-operator
```

### 2. 테스트 결과 확인

```bash
# 테스트 완료 후 결과 확인
kubectl describe k6 <test-name> -n k6-operator
```

### 3. 테스트 삭제

```bash
kubectl delete k6 <test-name> -n k6-operator
```

## Grafana에서 모니터링

K6 메트릭은 Prometheus에 자동으로 수집되며, Grafana에서 확인 가능합니다.

### 접속 방법

1. Grafana 접속 (http://grafana.local 또는 LoadBalancer IP)
2. Explore 메뉴 선택
3. Prometheus 데이터소스 선택
4. 다음 쿼리로 k6 메트릭 확인:
   - `k6_*` - 모든 k6 메트릭
   - `k6_http_reqs_total` - HTTP 요청 수
   - `k6_http_req_duration_seconds` - HTTP 요청 지연 시간

### 추천 대시보드

Grafana에서 k6 대시보드 임포트:
- Dashboard ID: 18030 (K6 Performance Testing)
- Dashboard ID: 10553 (K6 Load Testing Results)

## 제거

```bash
helm uninstall k6-operator -n k6-operator

# 네임스페이스 삭제 (선택)
kubectl delete namespace k6-operator
```

## 샘플 테스트

### 1. 기본 HTTP GET 테스트
```bash
kubectl apply -f samples/k6-test-basic-http.yaml
kubectl logs -f -n k6-operator -l k6_cr=k6-test-basic-http
```

### 2. Prometheus 메트릭 모니터링 테스트
```bash
kubectl apply -f samples/k6-test-prometheus.yaml
kubectl logs -f -n k6-operator -l k6_cr=k6-test-prometheus
```

### 3. 배치 작업 부하 테스트 (POST 요청)
실제 배치 작업을 시뮬레이션하는 테스트입니다:
- 점진적으로 증가하는 동시 배치 작업 (2→5→8→12→15)
- 각 배치 작업은 POST 요청으로 데이터 전송
- 배치별 성공/실패 추적 및 소요시간 측정

**사용 전 준비:**
1. `samples/k6-test-batch-post.yaml` 파일 열기
2. ConfigMap의 `test.js` 내부 `url` 변수를 실제 서비스 URL로 변경:
   ```javascript
   const url = 'http://your-service.your-namespace.svc.cluster.local/api/batch';
   ```
3. `payload` 데이터를 실제 배치 작업에 맞게 수정

**실행:**
```bash
kubectl apply -f samples/k6-test-batch-post.yaml
kubectl logs -f -n k6-operator -l k6_cr=k6-test-batch-post
```

**결과 예시:**
```json
{
  "test_duration": "13m",
  "batch_statistics": {
    "total": 87,
    "success": 85,
    "failed": 2,
    "success_rate": "97.70%"
  },
  "performance": {
    "avg_batch_duration": "45230ms",
    "p90_batch_duration": "58900ms",
    "p95_batch_duration": "62100ms"
  }
}
```

**테스트 삭제:**
```bash
kubectl delete -f samples/k6-test-batch-post.yaml
```

## 트러블슈팅

### Pod가 시작되지 않는 경우

```bash
# Pod 상태 확인
kubectl get pods -n k6-operator

# Pod 상세 정보
kubectl describe pod <pod-name> -n k6-operator

# 로그 확인
kubectl logs <pod-name> -n k6-operator
```

### ServiceMonitor가 작동하지 않는 경우

```bash
# ServiceMonitor 확인
kubectl get servicemonitor -n k6-operator

# Prometheus targets 확인
# Prometheus UI에서 Status > Targets 확인
```

## 참고 링크

- [K6 Operator 공식 문서](https://github.com/grafana/k6-operator)
- [K6 문서](https://k6.io/docs/)
- [K6 스크립트 예제](https://k6.io/docs/examples/)
