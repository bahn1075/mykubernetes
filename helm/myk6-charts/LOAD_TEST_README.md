# airecipe-service 부하 테스트 가이드

## 개요

이 디렉토리에는 `airecipe-service`에 대한 k6 부하 테스트 스크립트가 포함되어 있습니다.

## 테스트 스크립트

### 1. `airecipe-periodic-load-test.js` (권장)

**테스트 패턴:**
- 10초에 1번씩 요청 전송 (1분에 6번)
- 1분간 부하 주입 후 10초 대기
- 위 패턴을 3회 반복
- **총 테스트 시간: 3분 20초**
- **총 요청 수: 18회**

**타임라인:**
```
0:00 - 1:00  → 부하 주입 (6 requests)
1:00 - 1:10  → 대기
1:10 - 2:10  → 부하 주입 (6 requests)
2:10 - 2:20  → 대기
2:20 - 3:20  → 부하 주입 (6 requests)
```

### 2. `airecipe-load-test.js` (대안)

유사한 패턴이지만 `ramping-arrival-rate` executor를 사용합니다.

## 대상 서비스 정보

```yaml
Name:                     airecipe-service
Namespace:                airecipe
Type:                     NodePort
ClusterIP:                10.96.154.249
Port:                     8000/TCP
NodePort:                 30686/TCP
Endpoint:                 /demo
```

## 사용 방법

### 방법 1: 로컬에서 실행 (NodePort 사용)

1. **스크립트 수정** - 노드 IP 설정:
   ```javascript
   // airecipe-periodic-load-test.js 파일에서 다음 부분을 수정:
   const nodeIP = 'YOUR_NODE_IP';  // 실제 노드 IP로 변경 (예: '192.168.1.100')
   const nodePort = '30686';
   url = `http://${nodeIP}:${nodePort}${endpoint}`;
   ```

2. **k6 실행**:
   ```bash
   k6 run airecipe-periodic-load-test.js
   ```

### 방법 2: Kubernetes 클러스터 내부에서 실행 (ClusterIP 사용)

k6를 클러스터 내부 Pod로 실행하면 Service DNS를 통해 접근할 수 있습니다.

1. **k6 Job 생성**:
   ```bash
   kubectl create configmap k6-script \
     --from-file=airecipe-periodic-load-test.js \
     -n airecipe
   
   kubectl apply -f k6-job.yaml -n airecipe
   ```

2. **로그 확인**:
   ```bash
   kubectl logs -f job/k6-load-test -n airecipe
   ```

### 방법 3: k6 Operator 사용 (권장)

k6-operator가 이미 설치되어 있다면, TestRun CRD를 사용할 수 있습니다.

1. **TestRun 리소스 생성** (`k6-testrun-airecipe.yaml`):
   ```yaml
   apiVersion: k6.io/v1alpha1
   kind: TestRun
   metadata:
     name: airecipe-load-test
     namespace: airecipe
   spec:
     parallelism: 1
     script:
       configMap:
         name: k6-script
         file: airecipe-periodic-load-test.js
     separate: false
     runner:
       image: grafana/k6:latest
       resources:
         requests:
           cpu: 100m
           memory: 128Mi
         limits:
           cpu: 500m
           memory: 512Mi
   ```

2. **ConfigMap 생성 및 TestRun 실행**:
   ```bash
   # ConfigMap 생성
   kubectl create configmap k6-script \
     --from-file=airecipe-periodic-load-test.js \
     -n airecipe
   
   # TestRun 실행
   kubectl apply -f k6-testrun-airecipe.yaml
   
   # 상태 확인
   kubectl get testrun -n airecipe
   
   # 로그 확인
   kubectl logs -f -l k6_cr=airecipe-load-test -n airecipe
   ```

## 노드 IP 확인 방법

```bash
# 노드 IP 조회
kubectl get nodes -o wide

# 또는 특정 노드의 IP만 추출
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
```

## 결과 해석

테스트 완료 후 다음과 같은 Summary Report가 출력됩니다:

```
checks.........................: 100.00% ✓ 54       ✗ 0   
data_received..................: 123 kB  615 B/s
data_sent......................: 12 kB   60 B/s
demo_requests..................: 18      0.089925/s
http_req_blocked...............: avg=1.23ms  min=456µs  med=1.1ms   max=3.45ms  p(90)=2.1ms   p(95)=2.5ms   p(99)=3.2ms   
http_req_connecting............: avg=1.1ms   min=401µs  med=987µs   max=3.1ms   p(90)=1.9ms   p(95)=2.3ms   p(99)=2.9ms   
http_req_duration..............: avg=125.3ms min=89ms   med=121ms   max=234ms   p(90)=156ms   p(95)=178ms   p(99)=221ms   
  { expected_response:true }...: avg=125.3ms min=89ms   med=121ms   max=234ms   p(90)=156ms   p(95)=178ms   p(99)=221ms   
http_req_failed................: 0.00%   ✓ 0        ✗ 18  
http_req_receiving.............: avg=234µs   min=123µs  med=212µs   max=456µs   p(90)=345µs   p(95)=389µs   p(99)=432µs   
http_req_sending...............: avg=78µs    min=45µs   med=71µs    max=134µs   p(90)=98µs    p(95)=112µs   p(99)=127µs   
http_req_tls_handshaking.......: avg=0s      min=0s     med=0s      max=0s      p(90)=0s      p(95)=0s      p(99)=0s      
http_req_waiting...............: avg=124.9ms min=88.7ms med=120.8ms max=233.5ms p(90)=155.6ms p(95)=177.4ms p(99)=220.3ms 
http_reqs......................: 18      0.089925/s
iteration_duration.............: avg=126.5ms min=90.1ms med=122.3ms max=235.7ms p(90)=157.8ms p(95)=179.5ms p(99)=222.9ms 
iterations.....................: 18      0.089925/s
vus............................: 0       min=0      max=5 
vus_max........................: 10      min=10     max=10
```

### 주요 메트릭 설명:

- **http_req_duration**: 요청 처리 시간 (목표: p95 < 1000ms)
- **http_req_failed**: 실패한 요청 비율 (목표: < 5%)
- **checks**: 검증 통과율 (목표: 100%)
- **demo_requests**: 실제 전송된 요청 수 (예상: 18회)

## 중요 사항

### ⚠️ k6의 스케줄링 제약

k6는 **정확히 "10초에 1번"과 같은 간격 기반 스케줄링을 네이티브로 지원하지 않습니다.**

현재 스크립트는 다음 방식으로 요구사항을 근사합니다:
- `constant-arrival-rate` executor를 사용하여 **1분에 6번 (평균 10초에 1번)** 요청 전송
- 3개의 시나리오를 10초 간격으로 시작하여 총 3분간 부하 주입

이 방식은 **평균적으로 10초당 1번**의 효과를 냅니다만, 정확히 매 10초마다 실행되는 것은 아닙니다.

### 대안: 정확한 10초 간격이 필요한 경우

정확히 10초마다 요청을 보내야 한다면 다음 방법을 고려하세요:

1. **크론잡 사용**: Kubernetes CronJob으로 10초마다 실행
2. **외부 스케줄러**: 별도의 스크립트로 10초마다 k6를 실행
3. **커스텀 executor**: k6 확장 기능 사용

## 트러블슈팅

### 연결 실패 시

1. **서비스 상태 확인**:
   ```bash
   kubectl get svc airecipe-service -n airecipe
   kubectl get endpoints airecipe-service -n airecipe
   ```

2. **Pod 상태 확인**:
   ```bash
   kubectl get pods -n airecipe -l app=airecipe
   ```

3. **네트워크 테스트**:
   ```bash
   # 클러스터 내부에서
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n airecipe -- \
     curl http://airecipe-service:8000/demo
   
   # 클러스터 외부에서 (NodePort)
   curl http://<NODE_IP>:30686/demo
   ```

### 성능 이슈 시

- VU 수 조정: `preAllocatedVUs`, `maxVUs` 값 증가
- 타임아웃 조정: `timeout: '30s'` → `timeout: '60s'`
- 임계값 조정: `thresholds` 값 완화

## 참고 자료

- [k6 Documentation](https://grafana.com/docs/k6/latest/)
- [k6 Options Reference](https://grafana.com/docs/k6/latest/using-k6/k6-options/reference/)
- [k6 Executors](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/)
- [k6 Operator](https://github.com/grafana/k6-operator)
