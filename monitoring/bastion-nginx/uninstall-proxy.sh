#!/bin/bash
# Uninstall monitoring port-forward services

set -e

echo "🛑 Stopping and disabling port-forward services..."

# Stop and disable services
sudo systemctl stop port-forward-grafana || true
sudo systemctl disable port-forward-grafana || true

sudo systemctl stop port-forward-prometheus || true
sudo systemctl disable port-forward-prometheus || true

sudo systemctl stop port-forward-loki || true
sudo systemctl disable port-forward-loki || true

sudo systemctl stop port-forward-alertmanager || true
sudo systemctl disable port-forward-alertmanager || true

sudo systemctl stop port-forward-phoenix || true
sudo systemctl disable port-forward-phoenix || true

# Remove systemd service files
sudo rm -f /etc/systemd/system/port-forward-grafana.service
sudo rm -f /etc/systemd/system/port-forward-prometheus.service
sudo rm -f /etc/systemd/system/port-forward-loki.service
sudo rm -f /etc/systemd/system/port-forward-alertmanager.service
sudo rm -f /etc/systemd/system/port-forward-phoenix.service

# Reload systemd
sudo systemctl daemon-reload

echo "🛑 Removing Nginx configuration..."

# Remove nginx config
sudo rm -f /etc/nginx/conf.d/nginx-monitoring.conf

# Test and restart nginx
sudo nginx -t
sudo systemctl restart nginx

echo ""
echo "✅ Uninstall complete!"
