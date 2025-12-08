
import { Writer, Reader, Connection } from 'k6/x/kafka';
import { check } from 'k6';

// 포트포워딩된 로컬 엔드포인트
const brokers = ['localhost:9092'];
const topic   = 'my-topic';

const writer  = new Writer({ brokers, topic });
const reader  = new Reader({ brokers, topic });
const conn    = new Connection({ address: brokers[0] });

export const options = {
  scenarios: {
    produce_messages: { executor: 'constant-vus', vus: 50, duration: '30s' },
  },
  thresholds: {
    'kafka_writer_error_count': ['value==0'],  // 전송 에러 없어야 함
    'kafka_writer_produce_rate': ['value>500'] // 초당 500건 이상(예시)
  },
};

// VU=1에서 토픽 생성(이미 있으면 예외 무시)
if (__VU === 1) {
  try { conn.createTopic({ topic: 'my-topic' }); } catch (e) { /* ignore if exists */ }
}

export default function () {
  const key = `key-${__VU}-${Date.now()}`;
  const val = JSON.stringify({ id: `${__VU}-${Date.now()}`, amount: Math.random() });

  writer.produce({ messages: [{ key, value: val, headers: { origin: 'xk6' } }] });

  // (옵션) 1건 소비 후 길이 체크
  const msgs = reader.consume({ limit: 1 });
  if (msgs.length > 0) {
    // msgs[0].value 는 바이트 배열일 수 있습니다. 간단히 존재 여부만 검사
    check(msgs[0].value, { '메시지 수신 OK': (buf) => buf && buf.length > 0 });
  }
}

export function teardown () {
  writer.close();
  reader.close();
  conn.close();
}
