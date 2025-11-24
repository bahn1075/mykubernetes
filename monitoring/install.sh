#!/bin/bash

# Kubernetes Full Stack Monitoring Setup Script
# Components: Prometheus + Grafana + Loki + Promtail + Tempo

set -e

echo "🚀 Starting Kubernetes Full Stack Monitoring Setup..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    print_error "helm is not installed or not in PATH"
    exit 1
fi

# Add Helm repositories
print_status "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

print_success "Helm repositories added and updated"

# Create namespace
print_status "Creating monitoring namespace..."
kubectl apply -f 00-namespace.yaml

# Check if namespace is active
sleep 5
if kubectl get namespace monitoring &> /dev/null; then
    print_success "Namespace 'monitoring' created and ready"
else
    print_error "Failed to create namespace"
    exit 1
fi

# Install Prometheus (without Grafana)
print_status "Installing Prometheus..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values prometheus-values.yaml \
    --wait --timeout=600s

print_success "Prometheus installed successfully"

# Install Loki
print_status "Installing Loki..."
helm upgrade --install loki grafana/loki \
    --namespace monitoring \
    --values loki-values.yaml \
    --set loki.useTestSchema=true \
    --wait --timeout=600s

print_success "Loki installed successfully"

# Install Promtail
print_status "Installing Promtail..."
helm upgrade --install promtail grafana/promtail \
    --namespace monitoring \
    --values promtail-values.yaml \
    --wait --timeout=600s

print_success "Promtail installed successfully"

# Install Tempo
print_status "Installing Tempo..."
helm upgrade --install tempo grafana/tempo \
    --namespace monitoring \
    --values tempo-values.yaml \
    --wait --timeout=600s

print_success "Tempo installed successfully"

# Install trace generator for testing
print_status "Installing trace generator for testing..."
kubectl apply -f trace-generator.yaml

print_success "Trace generator installed"

# Install Grafana
print_status "Installing Grafana..."
helm upgrade --install grafana grafana/grafana \
    --namespace monitoring \
    --values grafana-values.yaml \
    --wait --timeout=600s

print_success "Grafana installed successfully"

# Apply Grafana Ingress
print_status "Applying Grafana Ingress..."
kubectl apply -f grafana-ingress.yaml

print_success "Grafana Ingress created"

# Wait for all deployments to be ready
print_status "Waiting for all deployments to be ready..."
kubectl wait --for=condition=Available deployment --all -n monitoring --timeout=600s

print_success "All deployments are ready!"

# Get service information
echo ""
print_status "=== Service Information ==="
kubectl get services -n monitoring

echo ""
print_status "=== Pod Status ==="
kubectl get pods -n monitoring

echo ""
print_status "=== Ingress Information ==="
kubectl get ingress -n monitoring

echo ""
print_success "🎉 Full Stack Monitoring Setup Complete!"
echo ""
echo "📊 Access Information:"
echo "  • Grafana UI: http://grafana.local"
echo "  • Admin Username: admin"
echo "  • Admin Password: admin123"
echo ""
echo "🔧 Port Forward Commands (if ingress is not working):"
echo "  • Grafana: kubectl port-forward -n monitoring svc/grafana 3000:80"
echo "  • Prometheus: kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
echo "  • AlertManager: kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093"
echo ""
echo "📝 Don't forget to add 'grafana.local' to your /etc/hosts file:"
echo "  echo '192.168.49.2 grafana.local' | sudo tee -a /etc/hosts"
echo ""
print_warning "Note: Make sure you have an Ingress Controller (like nginx-ingress) installed for external access"
echo ""
print_status "🔄 Generate some trace data for testing:"
echo "  kubectl port-forward -n monitoring svc/trace-generator 8080:8080 &"
echo "  curl http://localhost:8080/"
