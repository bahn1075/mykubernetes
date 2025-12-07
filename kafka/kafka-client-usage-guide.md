# Kafka Client Pods 사용 가이드

## 4. 편리한 사용법

### 환경변수 활용한 명령어 (YAML로 생성한 경우)

**Producer:**
```bash
kubectl exec -n kafka -it deployment/kafka-producer -- bash

# Shell 내부
bin/kafka-console-producer.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic $KAFKA_TOPIC
```

**Consumer:**
```bash
kubectl exec -n kafka -it deployment/kafka-consumer -- bash

# Shell 내부
bin/kafka-console-consumer.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic $KAFKA_TOPIC \
  --from-beginning
```

## 5. 추가 유용한 명령어들

### Topic 생성
```bash
kubectl exec -n kafka -it deployment/kafka-producer -- bash

bin/kafka-topics.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --create \
  --topic my-topic \
  --partitions 3 \
  --replication-factor 1
```

### Topic 목록 조회
```bash
bin/kafka-topics.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --list
```

### Topic 상세 정보
```bash
bin/kafka-topics.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --describe \
  --topic my-topic
```

### Consumer Group 조회
```bash
bin/kafka-consumer-groups.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --list
```

### Consumer Group 상세 정보
```bash
bin/kafka-consumer-groups.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --describe \
  --group my-consumer-group
```

### Consumer Group Offset 리셋
```bash
# 가장 처음부터 다시 시작
bin/kafka-consumer-groups.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --reset-offsets \
  --to-earliest \
  --topic my-topic \
  --execute

# 가장 최신으로 이동
bin/kafka-consumer-groups.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --reset-offsets \
  --to-latest \
  --topic my-topic \
  --execute

# 특정 offset으로 이동
bin/kafka-consumer-groups.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --group my-consumer-group \
  --reset-offsets \
  --to-offset 100 \
  --topic my-topic \
  --execute
```

## 6. 성능 테스트 명령어

### Producer 성능 테스트

**기본 테스트:**
```bash
bin/kafka-producer-perf-test.sh \
  --topic my-topic \
  --num-records 1000000 \
  --record-size 100 \
  --throughput 10000 \
  --producer-props bootstrap.servers=$KAFKA_BOOTSTRAP_SERVERS
```

**압축 사용:**
```bash
bin/kafka-producer-perf-test.sh \
  --topic my-topic \
  --num-records 1000000 \
  --record-size 1000 \
  --throughput -1 \
  --producer-props \
    bootstrap.servers=$KAFKA_BOOTSTRAP_SERVERS \
    compression.type=snappy \
    batch.size=16384 \
    linger.ms=10
```

**배치 크기 조정:**
```bash
bin/kafka-producer-perf-test.sh \
  --topic my-topic \
  --num-records 500000 \
  --record-size 256 \
  --throughput -1 \
  --producer-props \
    bootstrap.servers=$KAFKA_BOOTSTRAP_SERVERS \
    batch.size=32768 \
    linger.ms=100 \
    buffer.memory=67108864
```

### Consumer 성능 테스트

**기본 테스트:**
```bash
bin/kafka-consumer-perf-test.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --messages 1000000 \
  --threads 1
```

**여러 스레드로 테스트:**
```bash
bin/kafka-consumer-perf-test.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --messages 1000000 \
  --threads 4 \
  --group perf-consumer-group
```

**특정 파티션에서 읽기:**
```bash
bin/kafka-consumer-perf-test.sh \
  --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
  --topic my-topic \
  --messages 1000000 \
  --consumer-props \
    group.id=perf-test \
    auto.offset.reset=earliest
```

## 7. 편의 Alias 설정

### Pod Shell 내부에서 설정

```bash
# ~/.bashrc 파일에 추가 (Pod 내부)
cat >> ~/.bashrc << 'EOF'

# Kafka Aliases
alias kprod='bin/kafka-console-producer.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --topic $KAFKA_TOPIC'
alias kcons='bin/kafka-console-consumer.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --topic $KAFKA_TOPIC --from-beginning'
alias klist='bin/kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list'
alias kdesc='bin/kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --describe --topic'
alias kgroups='bin/kafka-consumer-groups.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list'
alias kgdesc='bin/kafka-consumer-groups.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --describe --group'

EOF

# 적용
source ~/.bashrc
```

### 사용 예시

```bash
# Producer 시작
kprod

# Consumer 시작
kcons

# Topic 목록
klist

# Topic 상세 정보
kdesc my-topic

# Consumer Group 목록
kgroups

# Consumer Group 상세 정보
kgdesc my-consumer-group
```

### 로컬 kubectl에서 alias 설정

```bash
# ~/.bashrc 또는 ~/.zshrc에 추가
cat >> ~/.bashrc << 'EOF'

# Kafka kubectl aliases
alias kprod-exec='kubectl exec -n kafka -it deployment/kafka-producer -- bash'
alias kcons-exec='kubectl exec -n kafka -it deployment/kafka-consumer -- bash'
alias kprod-send='kubectl exec -n kafka -i deployment/kafka-producer --'
alias kcons-read='kubectl exec -n kafka deployment/kafka-consumer --'

EOF

source ~/.bashrc
```

사용:
```bash
# Producer Pod 접속
kprod-exec

# Consumer Pod 접속
kcons-exec

# 메시지 전송 (Shell 진입 없이)
echo "test message" | kprod-send bin/kafka-console-producer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic
```

## 8. 외부에서 직접 명령 실행 (Shell 진입 없이)

### Producer에 메시지 전송

**단일 메시지:**
```bash
echo "Hello Kafka" | kubectl exec -n kafka -i deployment/kafka-producer -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic
```

**여러 메시지:**
```bash
cat << EOF | kubectl exec -n kafka -i deployment/kafka-producer -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic
Message 1
Message 2
Message 3
EOF
```

**파일에서 메시지 전송:**
```bash
cat messages.txt | kubectl exec -n kafka -i deployment/kafka-producer -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic
```

**Key-Value 메시지:**
```bash
echo "key1:value1" | kubectl exec -n kafka -i deployment/kafka-producer -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic \
  --property "parse.key=true" \
  --property "key.separator=:"
```

### Consumer에서 메시지 읽기

**처음 10개 메시지만 읽기:**
```bash
kubectl exec -n kafka deployment/kafka-consumer -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic \
  --from-beginning \
  --max-messages 10
```

**특정 파티션에서 읽기:**
```bash
kubectl exec -n kafka deployment/kafka-consumer -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic \
  --partition 0 \
  --offset earliest \
  --max-messages 10
```

**Key와 Value 함께 출력:**
```bash
kubectl exec -n kafka deployment/kafka-consumer -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic \
  --from-beginning \
  --property print.key=true \
  --property key.separator=": " \
  --max-messages 10
```

**타임스탬프 포함 출력:**
```bash
kubectl exec -n kafka deployment/kafka-consumer -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic \
  --from-beginning \
  --property print.timestamp=true \
  --property print.key=true \
  --property print.value=true \
  --max-messages 10
```

### Topic 관리 명령어

**Topic 생성:**
```bash
kubectl exec -n kafka deployment/kafka-producer -- \
  bin/kafka-topics.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --create \
  --topic test-topic \
  --partitions 3 \
  --replication-factor 1
```

**Topic 삭제:**
```bash
kubectl exec -n kafka deployment/kafka-producer -- \
  bin/kafka-topics.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --delete \
  --topic test-topic
```

**Topic 설정 변경:**
```bash
kubectl exec -n kafka deployment/kafka-producer -- \
  bin/kafka-configs.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --entity-type topics \
  --entity-name my-topic \
  --alter \
  --add-config retention.ms=86400000
```

**Topic 설정 조회:**
```bash
kubectl exec -n kafka deployment/kafka-producer -- \
  bin/kafka-configs.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --entity-type topics \
  --entity-name my-topic \
  --describe
```

## 9. 고급 사용 패턴

### JSON 메시지 전송

```bash
cat << EOF | kubectl exec -n kafka -i deployment/kafka-producer -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic json-topic
{"user_id": 1, "name": "Alice", "timestamp": "2024-01-01T10:00:00"}
{"user_id": 2, "name": "Bob", "timestamp": "2024-01-01T10:05:00"}
{"user_id": 3, "name": "Charlie", "timestamp": "2024-01-01T10:10:00"}
EOF
```

### 특정 Consumer Group으로 읽기

```bash
kubectl exec -n kafka -it deployment/kafka-consumer -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic \
  --group my-app-group \
  --from-beginning
```

### 여러 Topic 동시 구독

```bash
kubectl exec -n kafka -it deployment/kafka-consumer -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --whitelist "topic-.*" \
  --from-beginning
```

### Partition 정보와 함께 읽기

```bash
kubectl exec -n kafka deployment/kafka-consumer -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --topic my-topic \
  --from-beginning \
  --property print.partition=true \
  --property print.offset=true \
  --property print.timestamp=true \
  --max-messages 10
```

## 10. 디버깅 및 모니터링

### Broker 정보 확인

```bash
kubectl exec -n kafka deployment/kafka-producer -- \
  bin/kafka-broker-api-versions.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092
```

### 로그 세그먼트 정보

```bash
kubectl exec -n kafka deployment/kafka-producer -- \
  bin/kafka-log-dirs.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --describe \
  --topic-list my-topic
```

### Consumer Lag 확인

```bash
kubectl exec -n kafka deployment/kafka-consumer -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --describe \
  --group my-consumer-group \
  --members \
  --verbose
```

### 파티션별 상태 확인

```bash
kubectl exec -n kafka deployment/kafka-producer -- \
  bin/kafka-topics.sh \
  --bootstrap-server my-cluster-kafka-bootstrap:9092 \
  --describe \
  --topic my-topic \
  --under-replicated-partitions
```

## 11. Pod 삭제 및 정리

### Deployment 삭제

```bash
kubectl delete -n kafka deployment kafka-producer
kubectl delete -n kafka deployment kafka-consumer
```

### YAML로 생성한 경우

```bash
kubectl delete -f kafka-client-pods.yaml
```

### 특정 네임스페이스의 모든 리소스 확인

```bash
kubectl get all -n kafka
```

## 12. 트러블슈팅

### Pod 상태 확인

```bash
kubectl get pods -n kafka
kubectl describe pod -n kafka <pod-name>
kubectl logs -n kafka <pod-name>
```

### 연결 테스트

```bash
# Pod 내부에서
kubectl exec -n kafka -it deployment/kafka-producer -- bash

# telnet으로 Kafka 연결 확인
telnet my-cluster-kafka-bootstrap 9092

# nc로 연결 확인
nc -zv my-cluster-kafka-bootstrap 9092
```

### DNS 확인

```bash
kubectl exec -n kafka deployment/kafka-producer -- \
  nslookup my-cluster-kafka-bootstrap
```

### 네트워크 정책 확인

```bash
kubectl get networkpolicies -n kafka
kubectl describe networkpolicy -n kafka <policy-name>
```

## 참고사항

- 모든 명령어는 Strimzi 0.49.1 버전 기준입니다
- Bootstrap server 주소는 클러스터 이름에 따라 변경될 수 있습니다
- 프로덕션 환경에서는 적절한 리소스 제한과 보안 설정이 필요합니다
- Consumer Group 이름은 애플리케이션별로 고유하게 설정하세요
