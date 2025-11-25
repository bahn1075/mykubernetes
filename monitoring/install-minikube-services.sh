#!/bin/bash
# Minikube 자동 설정 서비스 설치 스크립트

set -e

echo "=========================================="
echo "Minikube 자동 설정 서비스 설치"
echo "=========================================="
echo ""

# 1. inotify 설정 스크립트 생성
cat > /tmp/minikube-inotify-setup.sh <<'EOF'
#!/bin/bash
# Minikube 노드 inotify 자동 설정 스크립트

LOG_FILE="/var/log/minikube-inotify-setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# minikube가 실행 중인지 확인
while ! minikube status &> /dev/null; do
    log "Minikube가 아직 시작되지 않았습니다. 5초 후 재시도..."
    sleep 5
done

log "Minikube 감지됨. inotify 설정 시작..."

# 모든 노드에 inotify 설정
for node in $(minikube node list 2>/dev/null | awk '{print $1}'); do
    log "  - $node 설정 중..."
    minikube ssh -n "$node" -- 'sudo sysctl -w fs.inotify.max_user_instances=1024' &> /dev/null
    minikube ssh -n "$node" -- 'sudo sysctl -w fs.inotify.max_user_watches=524288' &> /dev/null
done

log "✓ inotify 설정 완료"
EOF

chmod +x /tmp/minikube-inotify-setup.sh
sudo mv /tmp/minikube-inotify-setup.sh /usr/local/bin/minikube-inotify-setup.sh

echo "✓ inotify 설정 스크립트 생성: /usr/local/bin/minikube-inotify-setup.sh"

# 2. minikube tunnel 서비스 생성
cat > /tmp/minikube-tunnel.service <<EOF
[Unit]
Description=Minikube Tunnel for MetalLB
After=network.target

[Service]
Type=simple
User=$USER
Environment="HOME=/home/$USER"
ExecStartPre=/bin/bash -c 'while ! minikube status &>/dev/null; do sleep 2; done'
ExecStart=/usr/bin/minikube tunnel
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/minikube-tunnel.service /etc/systemd/system/minikube-tunnel.service

echo "✓ Minikube tunnel 서비스 생성: /etc/systemd/system/minikube-tunnel.service"

# 3. minikube inotify 설정 서비스 생성
cat > /tmp/minikube-inotify.service <<EOF
[Unit]
Description=Minikube inotify Configuration
After=network.target

[Service]
Type=oneshot
User=$USER
Environment="HOME=/home/$USER"
ExecStart=/usr/local/bin/minikube-inotify-setup.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/minikube-inotify.service /etc/systemd/system/minikube-inotify.service

echo "✓ Minikube inotify 서비스 생성: /etc/systemd/system/minikube-inotify.service"

# 4. systemd 리로드 및 서비스 활성화
sudo systemctl daemon-reload

echo ""
echo "=========================================="
echo "설치 완료!"
echo "=========================================="
echo ""
echo "서비스 시작 방법:"
echo "  sudo systemctl start minikube-tunnel"
echo "  sudo systemctl start minikube-inotify"
echo ""
echo "서비스 자동 시작 활성화:"
echo "  sudo systemctl enable minikube-tunnel"
echo "  sudo systemctl enable minikube-inotify"
echo ""
echo "서비스 상태 확인:"
echo "  sudo systemctl status minikube-tunnel"
echo "  sudo systemctl status minikube-inotify"
echo ""
echo "로그 확인:"
echo "  sudo journalctl -u minikube-tunnel -f"
echo "  sudo journalctl -u minikube-inotify -f"
echo "  tail -f /var/log/minikube-inotify-setup.log"
echo ""
echo "⚠️  참고:"
echo "  - minikube 시작 후 자동으로 서비스가 실행됩니다."
echo "  - tunnel 서비스는 sudo 권한이 필요하므로 sudoers 설정이 필요할 수 있습니다."
echo ""
