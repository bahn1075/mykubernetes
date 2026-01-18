#!/bin/bash

# Strimzi Kafka를 LoadBalancer 타입으로 재배포하는 스크립트

echo "=== Strimzi Kafka LoadBalancer 설정 및 배포 ==="
echo ""

# 1. 기존 Kafka 클러스터 삭제 (있는 경우)
echo "1. 기존 Kafka 클러스터 확인 및 삭제..."
if kubectl get kafka my-cluster -n kafka &> /dev/null; then
    echo "   기존 my-cluster 삭제 중..."
    kubectl delete kafka my-cluster -n kafka
    echo "   삭제 완료 대기 중 (30초)..."
    sleep 5
else
    echo "   기존 클러스터 없음"
fi

# 2. 새로운 LoadBalancer 타입의 Kafka 클러스터 배포
echo ""
echo "2. LoadBalancer 타입의 Kafka 클러스터 배포..."
kubectl apply -f /app/mykubernetes/kafka/kafka-cluster-loadbalancer.yaml

# 3. Kafka 클러스터가 준비될 때까지 대기
echo ""
echo "3. Kafka 클러스터 준비 대기 중..."
kubectl wait kafka/my-cluster --for=condition=Ready --timeout=5s -n kafka

# 4. LoadBalancer 서비스 확인
echo ""
echo "4. LoadBalancer 서비스 확인..."
echo ""
echo "=== Bootstrap 서비스 ==="
kubectl get svc -n kafka | grep my-cluster-kafka-external-bootstrap
echo ""
echo "=== Broker 서비스 ==="
kubectl get svc -n kafka | grep my-cluster-kafka-external-0

# 5. External IP 추출
echo ""
echo "=== LoadBalancer IP 정보 ==="
BOOTSTRAP_IP=$(kubectl get svc my-cluster-kafka-external-bootstrap -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
BROKER_IP=$(kubectl get svc my-cluster-kafka-0-external -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$BOOTSTRAP_IP" ]; then
    echo "⚠️  Bootstrap LoadBalancer IP가 아직 할당되지 않았습니다."
    echo "   MetalLB 설정을 확인하세요."
else
    echo "✓ Bootstrap IP: $BOOTSTRAP_IP:9094"
    echo "✓ Broker 0 IP: $BROKER_IP:9094"
    echo ""
    echo "=== kafka-test.js 파일 업데이트 ==="
    sed -i "s/<LOADBALANCER_IP>/$BOOTSTRAP_IP/g" /app/mykubernetes/kafka/xk6-output-kafka/examples/kafka-test.js
    echo "✓ kafka-test.js에 LoadBalancer IP 적용 완료"
fi

echo ""
echo "=== 배포 완료 ==="
echo ""
echo "다음 명령으로 테스트 토픽을 생성하세요:"
echo "kubectl exec -n kafka my-cluster-kafka-0 -c kafka -- bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists --topic test-topic --partitions 3 --replication-factor 1"
echo ""
echo "부하 테스트 실행:"
echo "cd /app/mykubernetes/kafka/xk6-output-kafka && bash run-loadbalancer-test.sh"
