#!/bin/bash
# VCN-Native CNI Pod Restart Script
# OKE Native Pod Networking 2.3.0+ requires policy removal before pod deletion

set -e

BACKUP_DIR="$(dirname "$0")/backup"
mkdir -p "$BACKUP_DIR"

echo "=== VCN-Native CNI Pod Restart Script ==="
echo ""

# Step 1: Check current status
echo "[1/6] Checking current CNI pod status..."
kubectl get pods -n kube-system -l app=vcn-native-ip-cni
echo ""

# Step 2: Backup policies
echo "[2/6] Backing up ValidatingAdmissionPolicy..."
kubectl get validatingadmissionpolicy npn-pod-deletion-deny-policy -o yaml > "$BACKUP_DIR/vap-policy.yaml"
kubectl get validatingadmissionpolicybinding npn-pod-deletion-deny-policy-binding -o yaml > "$BACKUP_DIR/vap-binding.yaml"
echo "Backup saved to $BACKUP_DIR/"
echo ""

# Step 3: Delete policies
echo "[3/6] Deleting ValidatingAdmissionPolicy..."
kubectl delete validatingadmissionpolicy npn-pod-deletion-deny-policy
kubectl delete validatingadmissionpolicybinding npn-pod-deletion-deny-policy-binding
echo ""

# Step 4: Delete CNI pods
echo "[4/6] Deleting CNI pods (will auto-restart)..."
kubectl delete pods -n kube-system -l app=vcn-native-ip-cni
echo ""

# Step 5: Wait for pods to restart
echo "[5/6] Waiting for new pods to be ready..."
sleep 20
kubectl get pods -n kube-system -l app=vcn-native-ip-cni
echo ""

# Step 6: Restore policies
echo "[6/6] Restoring ValidatingAdmissionPolicy..."
kubectl apply -f "$BACKUP_DIR/vap-policy.yaml"
kubectl apply -f "$BACKUP_DIR/vap-binding.yaml"
echo ""

# Verify
echo "=== Verification ==="
echo "Checking for errors in new pods..."
ERRORS=$(kubectl logs -n kube-system -l app=vcn-native-ip-cni --all-containers --since=1m 2>&1 | grep -i error | wc -l)
if [ "$ERRORS" -eq 0 ]; then
    echo "SUCCESS: No errors found in CNI logs"
else
    echo "WARNING: Found $ERRORS error(s) in CNI logs"
    kubectl logs -n kube-system -l app=vcn-native-ip-cni --all-containers --since=1m 2>&1 | grep -i error | head -10
fi
echo ""
echo "=== Done ==="
