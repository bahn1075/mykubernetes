#!/bin/bash
# Install monitoring port-forward services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Installing port-forward systemd services..."

# Copy systemd service files
sudo cp "${SCRIPT_DIR}/port-forward-grafana.service" /etc/systemd/system/
sudo cp "${SCRIPT_DIR}/port-forward-prometheus.service" /etc/systemd/system/
sudo cp "${SCRIPT_DIR}/port-forward-loki.service" /etc/systemd/system/
sudo cp "${SCRIPT_DIR}/port-forward-alertmanager.service" /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start services
echo "📦 Enabling and starting Grafana port-forward..."
sudo systemctl enable port-forward-grafana
sudo systemctl start port-forward-grafana

echo "📦 Enabling and starting Prometheus port-forward..."
sudo systemctl enable port-forward-prometheus
sudo systemctl start port-forward-prometheus

echo "📦 Enabling and starting Loki port-forward..."
sudo systemctl enable port-forward-loki
sudo systemctl start port-forward-loki

echo "📦 Enabling and starting Alertmanager port-forward..."
sudo systemctl enable port-forward-alertmanager
sudo systemctl start port-forward-alertmanager

# Wait a bit for services to start
sleep 3

# Check status
echo ""
echo "📊 Service Status:"
sudo systemctl status port-forward-grafana --no-pager | head -5
sudo systemctl status port-forward-prometheus --no-pager | head -5
sudo systemctl status port-forward-loki --no-pager | head -5
sudo systemctl status port-forward-alertmanager --no-pager | head -5

echo ""
echo "🔧 Installing Nginx reverse proxy configuration..."

# Copy nginx config
sudo cp "${SCRIPT_DIR}/nginx-monitoring.conf" /etc/nginx/conf.d/

# Test nginx configuration
sudo nginx -t

# Enable and restart nginx
sudo systemctl enable nginx
sudo systemctl restart nginx

echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Services listening on:"
echo "   - Grafana:       http://<PUBLIC_IP>:8080"
echo "   - Prometheus:    http://<PUBLIC_IP>:8090"
echo "   - Loki:          http://<PUBLIC_IP>:8100"
echo "   - Alertmanager:  http://<PUBLIC_IP>:8093"
echo ""
echo "🔍 Check service status with:"
echo "   sudo systemctl status port-forward-grafana"
echo "   sudo systemctl status nginx"
echo ""
echo "📝 View logs with:"
echo "   sudo journalctl -u port-forward-grafana -f"
echo "   sudo journalctl -u nginx -f"
