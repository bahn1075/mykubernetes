#!/bin/bash

# Kubernetes Full Stack Monitoring Uninstall Script

set -e

echo "🗑️ Starting Kubernetes Full Stack Monitoring Cleanup..."

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

# Check if helm is available
if ! command -v helm &> /dev/null; then
    print_error "helm is not installed or not in PATH"
    exit 1
fi

# Uninstall all Helm releases
print_status "Uninstalling Helm releases..."

releases=("trace-generator" "grafana" "tempo" "promtail" "loki" "prometheus")

for release in "${releases[@]}"; do
    if helm list -n monitoring | grep -q "$release"; then
        print_status "Uninstalling $release..."
        helm uninstall "$release" -n monitoring
        print_success "$release uninstalled"
    else
        print_warning "$release not found, skipping..."
    fi
done

# Delete trace generator deployment
print_status "Deleting trace generator..."
kubectl delete -f trace-generator.yaml --ignore-not-found=true

# Delete Grafana Ingress
print_status "Deleting Grafana Ingress..."
kubectl delete -f grafana-ingress.yaml --ignore-not-found=true

# Delete persistent volume claims
print_status "Deleting Persistent Volume Claims..."
kubectl delete pvc --all -n monitoring --ignore-not-found=true

# Delete namespace
print_status "Deleting monitoring namespace..."
kubectl delete namespace monitoring --ignore-not-found=true

print_success "🎉 Full Stack Monitoring Cleanup Complete!"
echo ""
print_warning "Note: Persistent Volumes may still exist depending on your storage class reclaim policy"
print_warning "You may want to manually check and clean up any remaining PVs if needed"
