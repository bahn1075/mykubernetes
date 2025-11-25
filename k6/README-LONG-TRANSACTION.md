# K6 Long Transaction Load Test

## 개요
이 테스트는 airecipe-service의 `/demo` 엔드포인트에 대해 1분 이상 소요되는 장시간 트랜잭션을 생성하여 부하 테스트를 수행합니다.

## 테스트 구성

### 테스트 대상
- **서비스**: airecipe-service (Namespace: airecipe)
- **엔드포인트**: http://localhost:8000/demo
- **프로토콜**: HTTP GET

### 부하 조건
- **트랜잭션 간격**: 5초마다 1개의 새로운 트랜잭션 시작
- **테스트 기간**: 3분
- **예상 트랜잭션 시간**: 60초 이상
- **동시 VU 수**: 최대 40-50개 (장시간 트랜잭션이 겹치면서 증가)

### 실행 전제조건

1. **k6 설치 확인**
```bash
k6 version
```
설치되지 않은 경우:
```bash
brew install k6
```

2. **Port Forwarding 활성화**
```bash
kubectl port-forward svc/airecipe-service 8000:8000 -n airecipe
```

3. **서비스 접근 테스트**
```bash
curl http://localhost:8000/demo
```

## 실행 방법

### 방법 1: 스크립트 실행 (권장)
```bash
cd /app/mykubernetes/k6
./run-long-transaction-test.sh
```

### 방법 2: 직접 k6 명령 실행
```bash
cd /app/mykubernetes/k6
k6 run long-transaction-test.js
```

### 방법 3: 결과 파일 저장하며 실행
```bash
cd /app/mykubernetes/k6
k6 run --out json=test-results.json long-transaction-test.js
```

## 테스트 시나리오 상세

### Executor: constant-arrival-rate
- 일정한 간격(5초)으로 새로운 VU를 시작합니다
- 각 VU는 독립적으로 장시간 트랜잭션을 수행합니다
- 트랜잭션이 완료될 때까지 해당 VU는 점유된 상태로 유지됩니다

### 예상 동작
- 0초: 1번째 트랜잭션 시작
- 5초: 2번째 트랜잭션 시작 (1번째는 계속 진행 중)
- 10초: 3번째 트랜잭션 시작 (1, 2번째 계속 진행 중)
- ...
- 60초: 1번째 트랜잭션 완료, 13번째 트랜잭션 시작
- 180초: 테스트 종료

최대 약 36개의 트랜잭션이 동시에 진행될 수 있습니다 (180초 / 5초 = 36).

## 메트릭

### 기본 HTTP 메트릭
- `http_req_duration`: 요청 소요 시간
- `http_req_failed`: 실패한 요청 수
- `http_reqs`: 총 요청 수

### 커스텀 메트릭
- `long_transaction_duration`: 장시간 트랜잭션의 소요 시간 (Trend)
- `long_transaction_count`: 완료된 트랜잭션 수 (Counter)
- `long_transaction_errors`: 실패한 트랜잭션 수 (Counter)

### 임계값 (Thresholds)
- 95% 요청이 120초 이내 완료: `p(95)<120000`
- 에러율 10% 미만: `rate<0.1`

## 결과 분석

### 성공 기준
- ✅ 각 트랜잭션이 60초 이상 소요
- ✅ 3분 동안 약 36개의 트랜잭션 생성
- ✅ 에러율 10% 미만
- ✅ 동시 실행 트랜잭션 수 증가 확인

### 모니터링 포인트
1. **VU 수 증가**: 시간이 지남에 따라 활성 VU 수가 증가해야 함
2. **메모리/CPU**: 서비스 파드의 리소스 사용량 모니터링
3. **응답 시간**: 일관되게 60초 이상 유지되는지 확인
4. **에러율**: 장시간 트랜잭션으로 인한 타임아웃이나 에러 발생 여부

## 문제 해결

### Port Forward 연결 끊김
```bash
# Port forwarding 재시작
kubectl port-forward svc/airecipe-service 8000:8000 -n airecipe
```

### 타임아웃 에러
스크립트의 `timeout` 값을 조정:
```javascript
const response = http.get(`${BASE_URL}${DEMO_ENDPOINT}`, {
  timeout: '180s', // 120s에서 180s로 증가
});
```

### VU 부족 에러
`options`의 `maxVUs` 값을 증가:
```javascript
maxVUs: 100, // 50에서 100으로 증가
```

## 추가 옵션

### 테스트 기간 변경
```bash
k6 run -e DURATION=5m long-transaction-test.js
```

### 트랜잭션 간격 변경
스크립트의 `timeUnit` 수정:
```javascript
timeUnit: '3s', // 5초에서 3초로 변경
```

### 상세 로그 출력
```bash
k6 run --verbose long-transaction-test.js
```

## 참고 자료
- [k6 Documentation - Executors](https://k6.io/docs/using-k6/scenarios/executors/)
- [k6 Constant Arrival Rate](https://k6.io/docs/using-k6/scenarios/executors/constant-arrival-rate/)
- [k6 Metrics](https://k6.io/docs/using-k6/metrics/)
