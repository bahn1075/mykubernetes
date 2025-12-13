#!/bin/bash

# Kubernetes Full Stack Monitoring Setup Script
# Components: Prometheus + Grafana + Loki + Alloy + Tempo

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

# Create required PersistentVolumes if they don't exist
print_status "Checking and creating required PersistentVolumes..."

# Create Grafana PV if it doesn't exist
if ! kubectl get pv grafana-unified-fss-pv &> /dev/null; then
    print_status "Creating Grafana PersistentVolume..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: grafana-unified-fss-pv
spec:
  accessModes:
    - ReadWriteMany
  capacity:
    storage: 10Gi
  csi:
    driver: fss.csi.oraclecloud.com
    volumeHandle: "ocid1.export.oc1.ap_chuncheon_1.aaaaaa4np2weim52pfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa:10.0.10.194:/oke_fss/grafana"
  mountOptions:
    - nosuid
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
EOF
    print_success "Grafana PV created"
else
    print_warning "Grafana PV already exists"
fi

# Create Loki PV if it doesn't exist
if ! kubectl get pv loki-fss-pv &> /dev/null; then
    print_status "Creating Loki PersistentVolume..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: loki-fss-pv
  labels:
    type: loki-storage
spec:
  accessModes:
    - ReadWriteMany
  capacity:
    storage: 5Gi
  csi:
    driver: fss.csi.oraclecloud.com
    volumeHandle: "ocid1.export.oc1.ap_chuncheon_1.aaaaaa4np2weim52pfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa:10.0.10.194:/oke_fss/loki"
  mountOptions:
    - nosuid
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
EOF
    print_success "Loki PV created"
else
    print_warning "Loki PV already exists"
fi

# Create Prometheus PV if it doesn't exist
if ! kubectl get pv prometheus-fss-pv &> /dev/null; then
    print_status "Creating Prometheus PersistentVolume..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-fss-pv
  labels:
    type: prometheus-storage
spec:
  accessModes:
    - ReadWriteMany
  capacity:
    storage: 5Gi
  csi:
    driver: fss.csi.oraclecloud.com
    volumeHandle: "ocid1.export.oc1.ap_chuncheon_1.aaaaaa4np2weim52pfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa:10.0.10.194:/oke_fss/prometheus"
  mountOptions:
    - nosuid
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
EOF
    print_success "Prometheus PV created"
else
    print_warning "Prometheus PV already exists"
fi

print_success "All required PersistentVolumes are ready"

# Create namespace
print_status "Creating monitoring namespace..."
kubectl create namespace monitoring || print_warning "Namespace 'monitoring' already exists"

# Check if namespace is active
sleep 5
if kubectl get namespace monitoring &> /dev/null; then
    print_success "Namespace 'monitoring' created and ready"
else
    print_error "Failed to create namespace"
    exit 1
fi

# Create Grafana admin secret if it doesn't exist
print_status "Creating Grafana admin secret..."
if kubectl get secret grafana-admin -n monitoring &> /dev/null; then
    print_warning "Secret 'grafana-admin' already exists"
else
    kubectl create secret generic grafana-admin \
        --from-literal=admin-user=admin \
        --from-literal=admin-password=admin123 \
        -n monitoring
    print_success "Grafana admin secret created"
fi

# Create Loki PVC manually to bind with loki-fss-pv
print_status "Creating Loki PVC..."
if ! kubectl get pvc storage-loki-0 -n monitoring &> /dev/null; then
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-loki-0
  namespace: monitoring
  labels:
    app.kubernetes.io/component: single-binary
    app.kubernetes.io/instance: loki
    app.kubernetes.io/name: loki
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  selector:
    matchLabels:
      type: loki-storage
  storageClassName: ""
  volumeMode: Filesystem
EOF
    print_success "Loki PVC created"
else
    print_warning "Loki PVC already exists"
fi

# Create Grafana PVC manually to bind with grafana-unified-fss-pv
print_status "Creating Grafana PVC..."
if ! kubectl get pvc grafana -n monitoring &> /dev/null; then
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana
  namespace: monitoring
  labels:
    app.kubernetes.io/instance: grafana
    app.kubernetes.io/name: grafana
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  volumeName: grafana-unified-fss-pv
  storageClassName: ""
  volumeMode: Filesystem
EOF
    print_success "Grafana PVC created"
else
    print_warning "Grafana PVC already exists"
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
    --wait --timeout=600s

print_success "Loki installed successfully"

# Install Alloy
print_status "Installing Alloy..."
helm upgrade --install alloy grafana/alloy \
    --namespace monitoring \
    --values alloy-values.yaml \
    --wait --timeout=600s

print_success "Alloy installed successfully"

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
echo "  • Grafana UI: http://grafana.64bit.kr"
echo "  • Admin Username: admin"
echo "  • Admin Password: admin123"
echo ""
echo "🔧 Port Forward Commands (if ingress is not working):"
echo "  • Grafana: kubectl port-forward -n monitoring svc/grafana 3000:80"
echo "  • Prometheus: kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
echo "  • AlertManager: kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093"
echo ""
echo "📝 Don't forget to add 'grafana.64bit.kr' to your /etc/hosts file if needed:"
echo "  echo '<your-ingress-ip> grafana.64bit.kr' | sudo tee -a /etc/hosts"
echo ""
print_warning "Note: Make sure you have an Ingress Controller (like nginx-ingress) installed for external access"
echo ""
print_status "🔄 Generate some trace data for testing:"
echo "  kubectl port-forward -n monitoring svc/trace-generator 8080:8080 &"
echo "  curl http://localhost:8080/"
