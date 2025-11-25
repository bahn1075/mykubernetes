#!/bin/bash
# Check monitoring proxy status

echo "=== Port Forward Services Status ==="
echo ""
sudo systemctl status port-forward-grafana --no-pager | head -3
sudo systemctl status port-forward-prometheus --no-pager | head -3
sudo systemctl status port-forward-loki --no-pager | head -3
sudo systemctl status port-forward-alertmanager --no-pager | head -3

echo ""
echo "=== Nginx Status ==="
sudo systemctl status nginx --no-pager | head -3

echo ""
echo "=== Listening Ports ==="
ss -tlnp | grep -E ':(8080|8090|8100|8093|3000|9090|3100|9093)' | awk '{print $4, $5}'

echo ""
echo "=== Public IP ==="
PUBLIC_IP=$(curl -s ifconfig.me)
echo "Public IP: $PUBLIC_IP"

echo ""
echo "=== Access URLs ==="
echo "  Grafana:      http://$PUBLIC_IP:8080"
echo "  Prometheus:   http://$PUBLIC_IP:8090"
echo "  Loki:         http://$PUBLIC_IP:8100"
echo "  Alertmanager: http://$PUBLIC_IP:8093"

echo ""
echo "=== Firewall Status ==="
sudo firewall-cmd --list-ports

echo ""
echo "⚠️  Remember to configure OCI Security List for these ports!"
