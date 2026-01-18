#!/bin/bash

# K6 Operator 설치 스크립트 (개발 환경)

set -e

echo "=========================================="
echo "  K6 Operator 설치 (개발 환경)"
echo "=========================================="
echo ""

# Helm 저장소 추가
echo "📦 Helm 저장소 추가..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || echo "grafana repo already exists"
helm repo update grafana

echo ""
echo "🚀 K6 Operator 설치 중..."
helm install k6-operator grafana/k6-operator \
  --namespace k6-operator \
  --create-namespace \
  --values dev-values.yaml 2>&1 | grep -v "namespaces.*already exists" || true

echo ""
echo "⏳ Pod가 준비될 때까지 대기 중..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=k6-operator \
  -n k6-operator \
  --timeout=120s

echo ""
echo "=========================================="
echo "  설치 완료!"
echo "=========================================="
echo ""

# 설치 상태 확인
echo "📊 설치 상태:"
echo ""
kubectl get pods -n k6-operator
echo ""
kubectl get svc -n k6-operator
echo ""

# ServiceMonitor 확인
if kubectl get servicemonitor -n k6-operator &>/dev/null; then
    echo "✅ ServiceMonitor 생성됨"
    kubectl get servicemonitor -n k6-operator
else
    echo "⚠️  ServiceMonitor가 생성되지 않았습니다"
fi

echo ""
echo "=========================================="
echo "  다음 단계"
echo "=========================================="
echo ""
echo "1. 샘플 테스트 실행:"
echo "   kubectl apply -f samples/k6-test-simple.yaml"
echo ""
echo "2. 테스트 상태 확인:"
echo "   kubectl get k6 -n k6-operator"
echo ""
echo "3. 테스트 로그 확인:"
echo "   kubectl logs -f -l k6_cr=k6-test-simple -n k6-operator"
echo ""
echo "4. Grafana에서 메트릭 확인"
echo ""
