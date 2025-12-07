import http from 'k6/http';
import { check, sleep } from 'k6';

// 부하 테스트 옵션 설정
export const options = {
  // 시나리오를 사용하여 복잡한 부하 패턴 정의
  scenarios: {
    periodic_load: {
      executor: 'ramping-arrival-rate', // 도착률 기반 실행
      startRate: 0,
      timeUnit: '1m',  // 1분당 발생 횟수
      preAllocatedVUs: 10, // 미리 할당할 VU 수
      maxVUs: 50,  // 최대 VU 수
      stages: [
        // 첫 번째 1분: 6번 실행 (10초당 1번)
        { duration: '1m', target: 6 },
        // 대기 10초
        { duration: '10s', target: 0 },
        // 두 번째 1분: 6번 실행 (10초당 1번)
        { duration: '1m', target: 6 },
        // 대기 10초
        { duration: '10s', target: 0 },
        // 세 번째 1분: 6번 실행 (10초당 1번)
        { duration: '1m', target: 6 },
      ],
    },
  },
  
  // 임계값 설정 (성능 목표)
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95%의 요청이 500ms 이내
    http_req_failed: ['rate<0.01'],   // 실패율 1% 미만
  },
  
  // Summary 출력 옵션
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)', 'count'],
  noColor: false,
};

// 기본 테스트 함수
export default function () {
  // airecipe-service의 NodePort를 통한 접근
  // 클러스터 내부에서 실행되는 경우: Service Name 사용
  const serviceName = 'airecipe-service.airecipe.svc.cluster.local';
  const servicePort = '8000';
  
  // 또는 NodePort를 통한 외부 접근 (노드 IP가 필요한 경우)
  // const nodeIP = 'YOUR_NODE_IP';
  // const nodePort = '30686';
  // const url = `http://${nodeIP}:${nodePort}/demo`;
  
  const url = `http://${serviceName}:${servicePort}/demo`;
  
  // HTTP GET 요청
  const response = http.get(url, {
    tags: { name: 'demo-endpoint' },
  });
  
  // 응답 검증
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  // 각 iteration 사이에 짧은 대기 (필요시 조정)
  sleep(1);
}

// 테스트 시작 전 실행 (선택적)
export function setup() {
  console.log('=== 부하 테스트 시작 ===');
  console.log('대상 서비스: airecipe-service.airecipe');
  console.log('엔드포인트: /demo');
  console.log('총 테스트 시간: 3분 20초 (실제 부하: 3분)');
  console.log('부하 패턴: 10초당 1회, 1분간 지속 × 3회');
  console.log('========================');
}

// 테스트 종료 후 실행 (선택적)
export function teardown(data) {
  console.log('=== 부하 테스트 완료 ===');
  console.log('결과 리포트는 아래를 참조하세요.');
}
