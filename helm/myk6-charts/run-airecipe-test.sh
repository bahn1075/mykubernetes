#!/bin/bash

# airecipe-service 부하 테스트 실행 스크립트

set -e

NAMESPACE="airecipe"
TESTRUN_NAME="airecipe-periodic-load-test"
MANIFEST_FILE="k6-testrun-airecipe.yaml"

echo "======================================"
echo "airecipe-service 부하 테스트 실행"
echo "======================================"
echo ""

# 네임스페이스 존재 확인
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "❌ 네임스페이스 '$NAMESPACE'가 존재하지 않습니다."
    echo "네임스페이스를 먼저 생성하세요:"
    echo "  kubectl create namespace $NAMESPACE"
    exit 1
fi

# 서비스 존재 확인
echo "🔍 airecipe-service 확인 중..."
if ! kubectl get service airecipe-service -n "$NAMESPACE" &> /dev/null; then
    echo "⚠️  경고: airecipe-service가 '$NAMESPACE' 네임스페이스에 존재하지 않습니다."
    echo "계속 진행하시겠습니까? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "테스트를 중단합니다."
        exit 1
    fi
else
    echo "✅ airecipe-service 확인됨"
    kubectl get service airecipe-service -n "$NAMESPACE"
    echo ""
fi

# k6-operator 설치 확인
echo "🔍 k6-operator 확인 중..."
if ! kubectl get crd testruns.k6.io &> /dev/null; then
    echo "❌ k6-operator가 설치되어 있지 않습니다."
    echo "k6-operator를 먼저 설치하세요:"
    echo "  cd k6-operator && ./install.sh"
    exit 1
fi
echo "✅ k6-operator 확인됨"
echo ""

# 기존 TestRun 정리
echo "🧹 기존 TestRun 정리 중..."
if kubectl get testrun "$TESTRUN_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "기존 TestRun을 삭제합니다..."
    kubectl delete testrun "$TESTRUN_NAME" -n "$NAMESPACE" --wait=false
    sleep 5
fi

# ConfigMap 정리
if kubectl get configmap k6-airecipe-script -n "$NAMESPACE" &> /dev/null; then
    echo "기존 ConfigMap을 삭제합니다..."
    kubectl delete configmap k6-airecipe-script -n "$NAMESPACE"
fi
echo ""

# TestRun 생성
echo "🚀 TestRun 생성 중..."
kubectl apply -f "$MANIFEST_FILE" -n "$NAMESPACE"
echo ""

# 상태 확인
echo "📊 TestRun 상태:"
kubectl get testrun "$TESTRUN_NAME" -n "$NAMESPACE"
echo ""

# Pod 대기
echo "⏳ k6 Pod가 시작될 때까지 대기 중..."
sleep 5

# Pod 이름 찾기
POD_NAME=""
for i in {1..30}; do
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l k6_cr="$TESTRUN_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD_NAME" ]; then
        echo "✅ Pod 찾음: $POD_NAME"
        break
    fi
    echo "대기 중... ($i/30)"
    sleep 2
done

if [ -z "$POD_NAME" ]; then
    echo "❌ k6 Pod를 찾을 수 없습니다."
    echo "수동으로 확인하세요:"
    echo "  kubectl get pods -n $NAMESPACE -l k6_cr=$TESTRUN_NAME"
    exit 1
fi
echo ""

# Pod 상태 대기
echo "⏳ Pod가 실행될 때까지 대기 중..."
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s || true
echo ""

# 로그 스트리밍
echo "======================================"
echo "📋 테스트 로그 (실시간)"
echo "======================================"
echo ""
echo "테스트는 약 3분 20초 동안 실행됩니다..."
echo "Ctrl+C를 눌러도 테스트는 백그라운드에서 계속 실행됩니다."
echo ""

kubectl logs -f "$POD_NAME" -n "$NAMESPACE" || true

echo ""
echo "======================================"
echo "✅ 테스트 완료"
echo "======================================"
echo ""

# 최종 상태 확인
echo "📊 최종 TestRun 상태:"
kubectl get testrun "$TESTRUN_NAME" -n "$NAMESPACE"
echo ""

echo "추가 명령어:"
echo "  # 로그 다시 보기:"
echo "    kubectl logs $POD_NAME -n $NAMESPACE"
echo ""
echo "  # TestRun 상태 확인:"
echo "    kubectl describe testrun $TESTRUN_NAME -n $NAMESPACE"
echo ""
echo "  # TestRun 삭제:"
echo "    kubectl delete testrun $TESTRUN_NAME -n $NAMESPACE"
echo ""
