#!/bin/bash

# Kafka 부하 테스트 스크립트 (kafka-console-producer 사용)

TOPIC="my-topic"
NUM_MESSAGES=${1:-1000}
NUM_THREADS=${2:-10}
BATCH_SIZE=$((NUM_MESSAGES / NUM_THREADS))

echo "=== Kafka 부하 테스트 시작 ==="
echo "Topic: $TOPIC"
echo "총 메시지 수: $NUM_MESSAGES"
echo "메시지 크기: ~10KB/메시지"
echo "예상 전송량: ~$((NUM_MESSAGES * 10 / 1024))MB"
echo "동시 Producer 수: $NUM_THREADS"
echo "각 Producer당 메시지: $BATCH_SIZE"
echo ""

# 시작 시간 기록
START_TIME=$(date +%s)

# 병렬로 메시지 생성 및 전송
for i in $(seq 1 $NUM_THREADS); do
  (
    echo "Producer $i 시작..."
    for j in $(seq 1 $BATCH_SIZE); do
      TIMESTAMP=$(date -Iseconds)
      MESSAGE_ID=$(( (i-1) * BATCH_SIZE + j ))
      # 10KB 크기의 더미 데이터 생성
      LARGE_DATA=$(head -c 10240 /dev/urandom | base64 | tr -d '\n')
      echo "{\"timestamp\":\"$TIMESTAMP\",\"producer\":$i,\"message_id\":$MESSAGE_ID,\"message\":\"Load test message $MESSAGE_ID from producer $i\",\"payload\":\"$LARGE_DATA\"}"
    done | kubectl exec -i -n kafka deployment/kafka-producer -- \
      bin/kafka-console-producer.sh \
      --bootstrap-server my-cluster-kafka-bootstrap:9092 \
      --topic $TOPIC 2>/dev/null
    echo "Producer $i 완료 ($BATCH_SIZE 메시지, ~10KB/메시지)"
  ) &
done

# 모든 백그라운드 작업 완료 대기
wait

# 종료 시간 기록
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=== 부하 테스트 완료 ==="
echo "소요 시간: ${DURATION}초"
echo "처리량: $((NUM_MESSAGES / DURATION)) 메시지/초"
echo "데이터 처리량: ~$((NUM_MESSAGES * 10 / DURATION / 1024)) MB/초"
echo ""

# 메시지 확인
echo "=== 전송된 메시지 샘플 (처음 5개) ==="
kubectl exec -n kafka my-cluster-dual-role-0 -c kafka -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic $TOPIC \
  --from-beginning \
  --max-messages 5 \
  --timeout-ms 5000 2>/dev/null

echo ""
echo "=== Topic 정보 ==="
kubectl exec -n kafka my-cluster-dual-role-0 -c kafka -- \
  bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic $TOPIC 2>/dev/null | awk -F: '{sum+=$3} END {print "총 메시지 수: " sum}'

echo ""
echo "=== Consumer Lag 테스트 ==="
CONSUMER_GROUP="console-consumer-18258"
echo "Consumer Group: $CONSUMER_GROUP"
echo "기존 consumer group 사용 (새로 생성하지 않음)"

# Consumer lag 확인
echo ""
echo "=== Producer 전송 전 Consumer Lag 상태 ==="
kubectl exec -n kafka my-cluster-dual-role-0 -c kafka -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --group $CONSUMER_GROUP 2>/dev/null

echo ""
echo "=== Producer 전송 후 최종 Consumer Lag 확인 ==="
kubectl exec -n kafka my-cluster-dual-role-0 -c kafka -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --group $CONSUMER_GROUP 2>/dev/null
