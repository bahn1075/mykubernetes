# Monitoring Services External Access via Nginx Reverse Proxy

이 설정은 OKE 클러스터의 ClusterIP 서비스를 배스천 서버의 Public IP를 통해 외부에서 접근할 수 있도록 합니다.

## 아키텍처

```
외부 클라이언트
    ↓
배스천 Public IP (158.180.78.215)
    ↓ (Nginx Reverse Proxy)
로컬호스트 포트 (127.0.0.1)
    ↓ (kubectl port-forward - systemd)
OKE 클러스터 ClusterIP 서비스
```

## 접근 URL

- **Grafana**: http://158.180.78.215:8080
- **Prometheus**: http://158.180.78.215:8090
- **Loki**: http://158.180.78.215:8100
- **Alertmanager**: http://158.180.78.215:8093

## 설치된 컴포넌트

### 1. Systemd 서비스 (kubectl port-forward)
다음 서비스들이 자동으로 실행되며, 서버 재시작 시에도 자동으로 시작됩니다:

- `port-forward-grafana.service` - Grafana (3000:80)
- `port-forward-prometheus.service` - Prometheus (9090:9090)
- `port-forward-loki.service` - Loki (3100:3100)
- `port-forward-alertmanager.service` - Alertmanager (9093:9093)

### 2. Nginx Reverse Proxy
외부에서 접근 가능한 포트로 프록시:
- 8080 → 127.0.0.1:3000 (Grafana)
- 8090 → 127.0.0.1:9090 (Prometheus)
- 8100 → 127.0.0.1:3100 (Loki)
- 8093 → 127.0.0.1:9093 (Alertmanager)

## 설치

```bash
cd /app/mykubernetes/monitoring
./install-proxy.sh
```

## 제거

```bash
cd /app/mykubernetes/monitoring
./uninstall-proxy.sh
```

## 서비스 관리

### 상태 확인
```bash
# 모든 port-forward 서비스 상태
sudo systemctl status port-forward-grafana
sudo systemctl status port-forward-prometheus
sudo systemctl status port-forward-loki
sudo systemctl status port-forward-alertmanager

# Nginx 상태
sudo systemctl status nginx
```

### 로그 확인
```bash
# port-forward 로그
sudo journalctl -u port-forward-grafana -f
sudo journalctl -u port-forward-prometheus -f

# Nginx 로그
sudo journalctl -u nginx -f
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

### 서비스 재시작
```bash
# port-forward 서비스 재시작
sudo systemctl restart port-forward-grafana
sudo systemctl restart port-forward-prometheus
sudo systemctl restart port-forward-loki
sudo systemctl restart port-forward-alertmanager

# Nginx 재시작
sudo systemctl restart nginx
```

## 방화벽 설정

firewalld에서 다음 포트가 열려 있습니다:
```bash
sudo firewall-cmd --list-all
# Output:
#   ports: 8080/tcp 8090/tcp 8100/tcp 8093/tcp
```

### OCI 보안 리스트 설정 필요
OCI 콘솔에서 VCN의 보안 리스트에 다음 Ingress 규칙을 추가해야 합니다:

| 소스 CIDR | 프로토콜 | 소스 포트 범위 | 대상 포트 범위 | 설명 |
|-----------|----------|---------------|----------------|------|
| 0.0.0.0/0 | TCP | All | 8080 | Grafana |
| 0.0.0.0/0 | TCP | All | 8090 | Prometheus |
| 0.0.0.0/0 | TCP | All | 8100 | Loki |
| 0.0.0.0/0 | TCP | All | 8093 | Alertmanager |

**주의**: 프로덕션 환경에서는 소스 CIDR을 특정 IP 또는 IP 범위로 제한하는 것을 권장합니다.

## 포트 매핑

| 서비스 | K8s Service | K8s Port | Local Port | Nginx Port | Public URL |
|--------|-------------|----------|------------|------------|------------|
| Grafana | grafana | 80 | 3000 | 8080 | http://158.180.78.215:8080 |
| Prometheus | prometheus-prometheus | 9090 | 9090 | 8090 | http://158.180.78.215:8090 |
| Loki | loki | 3100 | 3100 | 8100 | http://158.180.78.215:8100 |
| Alertmanager | prometheus-alertmanager | 9093 | 9093 | 8093 | http://158.180.78.215:8093 |

## 트러블슈팅

### port-forward 서비스가 실패하는 경우
```bash
# 로그 확인
sudo journalctl -u port-forward-grafana -n 50

# OCI CLI 경로 확인
which oci
# 출력: /home/opc/bin/oci

# systemd 서비스 파일에 PATH가 올바르게 설정되어 있는지 확인
cat /etc/systemd/system/port-forward-grafana.service
# Environment="PATH=/home/opc/bin:/usr/local/bin:/usr/bin:/bin" 확인
```

### Nginx가 시작되지 않는 경우
```bash
# 설정 테스트
sudo nginx -t

# 에러 로그 확인
sudo tail -f /var/log/nginx/error.log
```

### 포트가 이미 사용 중인 경우
```bash
# 포트 사용 확인
sudo ss -tlnp | grep -E '8080|8090|8100|8093'
```

### 외부에서 접근이 안 되는 경우
1. 로컬 방화벽 확인: `sudo firewall-cmd --list-all`
2. OCI 보안 리스트 확인 (OCI 콘솔)
3. Nginx 상태 확인: `sudo systemctl status nginx`
4. port-forward 서비스 상태 확인

## 파일 구조

```
monitoring/
├── install-proxy.sh                      # 설치 스크립트
├── uninstall-proxy.sh                    # 제거 스크립트
├── nginx-monitoring.conf                 # Nginx 리버스 프록시 설정
├── port-forward-grafana.service          # Grafana systemd 서비스
├── port-forward-prometheus.service       # Prometheus systemd 서비스
├── port-forward-loki.service             # Loki systemd 서비스
├── port-forward-alertmanager.service     # Alertmanager systemd 서비스
└── README-PROXY.md                       # 이 문서
```

## 보안 고려사항

⚠️ **경고**: 현재 설정은 테스트 목적으로 SSL/TLS 없이 HTTP만 사용합니다.

프로덕션 환경에서는:
1. Let's Encrypt를 사용한 HTTPS 설정 권장
2. 소스 IP 제한 (OCI 보안 리스트)
3. Grafana 인증 활성화 확인
4. 방화벽 규칙 최소화

## 성능 최적화

- Nginx는 경량이며 리소스 사용량이 적습니다
- kubectl port-forward는 안정적이며 자동 재연결 기능이 있습니다
- systemd를 통해 프로세스가 종료되면 자동으로 재시작됩니다

## 참고

- OKE Free Tier에서는 LoadBalancer 타입 서비스 사용 시 비용이 발생하므로 이 방법을 사용합니다
- NodePort도 가능하지만, 포트 범위 제한(30000-32767)이 있습니다
- 이 방법은 단일 배스천 서버를 통한 접근으로, 배스천 서버의 가용성에 의존합니다
