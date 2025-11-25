import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// Custom metrics
const longTransactionDuration = new Trend('long_transaction_duration');
const longTransactionCount = new Counter('long_transaction_count');
const longTransactionErrors = new Counter('long_transaction_errors');

// Test configuration
export const options = {
  // Use constant arrival rate executor
  scenarios: {
    long_running_transactions: {
      executor: 'constant-arrival-rate',
      rate: 100,          // 10 iterations per...
      timeUnit: '1s',    // ...1 second (10 per second)
      duration: '3m',    // Run for 3 minutes
      preAllocatedVUs: 1000, // Pre-allocate enough VUs to handle overlapping long transactions
      maxVUs: 1000,      // Maximum VUs if needed
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<120000'], // 95% of requests should complete within 120 seconds
    'http_req_failed': ['rate<0.1'],       // Error rate should be less than 10%
  },
};

// Test target URL
const BASE_URL = 'http://localhost:8000';
const DEMO_ENDPOINT = '/demo';

export default function () {
  const iterationStart = Date.now();
  
  // Perform GET request to /demo endpoint
  const response = http.get(`${BASE_URL}${DEMO_ENDPOINT}`, {
    timeout: '120s', // Set timeout to 120 seconds (2 minutes) to allow for long-running requests
  });
  
  // Check response status
  const responseSuccess = check(response, {
    'status is 200': (r) => r.status === 200,
  });
  
  if (!responseSuccess) {
    longTransactionErrors.add(1);
    console.log(`Request failed. Status: ${response.status}`);
    return; // Exit early if request failed
  }
  
  // Simulate long-running transaction by sleeping for 60 seconds
  // This keeps the VU occupied and simulates a long-running process
  console.log(`Request successful, simulating long transaction (60s sleep)...`);
  sleep(60);
  
  const iterationDuration = Date.now() - iterationStart;
  
  // Verify transaction duration
  const success = check({ duration: iterationDuration }, {
    'transaction duration >= 60s': (data) => data.duration >= 60000,
  });
  
  // Record metrics
  longTransactionDuration.add(iterationDuration);
  longTransactionCount.add(1);
  
  if (!success) {
    longTransactionErrors.add(1);
    console.log(`Transaction too short. Duration: ${iterationDuration}ms`);
  } else {
    console.log(`Long transaction completed successfully. Duration: ${iterationDuration}ms`);
  }
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
  };
}

function textSummary(data, options) {
  const indent = options.indent || '';
  const enableColors = options.enableColors || false;
  
  let summary = '\n';
  summary += `${indent}================== Test Summary ==================\n`;
  summary += `${indent}Test Duration: ${data.state.testRunDurationMs / 1000}s\n`;
  summary += `${indent}Total VUs: ${data.metrics.vus?.values.max || 'N/A'}\n`;
  summary += `${indent}\n`;
  summary += `${indent}HTTP Metrics:\n`;
  summary += `${indent}  Total Requests: ${data.metrics.http_reqs?.values.count || 0}\n`;
  summary += `${indent}  Failed Requests: ${data.metrics.http_req_failed?.values.passes || 0}\n`;
  summary += `${indent}  Request Duration (avg): ${(data.metrics.http_req_duration?.values.avg / 1000).toFixed(2)}s\n`;
  summary += `${indent}  Request Duration (p95): ${(data.metrics.http_req_duration?.values['p(95)'] / 1000).toFixed(2)}s\n`;
  summary += `${indent}\n`;
  summary += `${indent}Long Transaction Metrics:\n`;
  summary += `${indent}  Total Transactions: ${data.metrics.long_transaction_count?.values.count || 0}\n`;
  summary += `${indent}  Transaction Errors: ${data.metrics.long_transaction_errors?.values.count || 0}\n`;
  summary += `${indent}  Avg Duration: ${(data.metrics.long_transaction_duration?.values.avg / 1000).toFixed(2)}s\n`;
  summary += `${indent}  Min Duration: ${(data.metrics.long_transaction_duration?.values.min / 1000).toFixed(2)}s\n`;
  summary += `${indent}  Max Duration: ${(data.metrics.long_transaction_duration?.values.max / 1000).toFixed(2)}s\n`;
  summary += `${indent}==================================================\n`;
  
  return summary;
}
