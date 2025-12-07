#!/bin/bash

# Kubernetes Monitoring 네임스페이스의 Pod 이미지 확인 스크립트
# 사용법: ./check-images.sh [네임스페이스]

NAMESPACE="${1:-monitoring}"

echo "=========================================="
echo "  Kubernetes Pod 이미지 버전 확인"
echo "  네임스페이스: $NAMESPACE"
echo "=========================================="
echo ""

# 모든 Pod의 이미지 정보 수집
echo "=== 현재 실행 중인 Pod 이미지 ===" 
kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[*]}  {.name}: {.image}{"\n"}{end}{range .spec.initContainers[*]}  {.name} (init): {.image}{"\n"}{end}{"\n"}{end}' | grep -v "^$"

echo ""
echo "=== 주요 컴포넌트 이미지 (중복 제거) ===" 
kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u | grep -E "(grafana|prometheus|alertmanager|loki|alloy|node-exporter|kube-state-metrics)"

echo ""
echo "=========================================="
echo "  Docker Hub 최신 버전 확인"
echo "=========================================="
echo ""

check_dockerhub_latest() {
    local repo=$1
    local current=$2
    echo ">>> $repo"
    echo "현재 버전: $current"
    echo "Docker Hub 최신 태그 (상위 5개):"
    curl -s "https://registry.hub.docker.com/v2/repositories/$repo/tags?page_size=5" 2>/dev/null | grep -o '"name":"[^"]*"' | head -5 | sed 's/"name":"//g; s/"//g; s/^/  - /'
    echo ""
}

# Grafana 이미지 확인
GRAFANA_VERSION=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[?(@.name=="grafana")].image}' | grep -o 'grafana:[^ ]*' | head -1)
if [ -n "$GRAFANA_VERSION" ]; then
    check_dockerhub_latest "grafana/grafana" "$GRAFANA_VERSION"
fi

# Loki 이미지 확인
LOKI_VERSION=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[?(@.name=="loki")].image}' | grep -o 'loki:[^ ]*' | head -1)
if [ -n "$LOKI_VERSION" ]; then
    check_dockerhub_latest "grafana/loki" "$LOKI_VERSION"
fi

# Alloy 이미지 확인
ALLOY_VERSION=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[?(@.name=="alloy")].image}' | grep -o 'alloy:[^ ]*' | head -1)
if [ -n "$ALLOY_VERSION" ]; then
    check_dockerhub_latest "grafana/alloy" "$ALLOY_VERSION"
fi

# Prometheus 이미지 확인
PROMETHEUS_VERSION=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[?(@.name=="prometheus")].image}' | grep -o 'prometheus:[^ ]*' | head -1)
if [ -n "$PROMETHEUS_VERSION" ]; then
    check_dockerhub_latest "prom/prometheus" "$PROMETHEUS_VERSION"
fi

# AlertManager 이미지 확인
ALERTMANAGER_VERSION=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[?(@.name=="alertmanager")].image}' | grep -o 'alertmanager:[^ ]*' | head -1)
if [ -n "$ALERTMANAGER_VERSION" ]; then
    check_dockerhub_latest "prom/alertmanager" "$ALERTMANAGER_VERSION"
fi

# Node Exporter 이미지 확인
NODE_EXPORTER_VERSION=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[?(@.name=="node-exporter")].image}' | grep -o 'node-exporter:[^ ]*' | head -1)
if [ -n "$NODE_EXPORTER_VERSION" ]; then
    check_dockerhub_latest "prom/node-exporter" "$NODE_EXPORTER_VERSION"
fi

echo "=========================================="
echo "  확인 완료"
echo "=========================================="
