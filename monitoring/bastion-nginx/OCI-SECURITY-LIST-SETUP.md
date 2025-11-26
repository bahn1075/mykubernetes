# OCI Security List 설정 가이드

## 현재 상태
배스천 서버의 firewalld 방화벽은 이미 설정되었습니다.
그러나 **OCI VCN의 보안 리스트**에서도 해당 포트를 열어야 외부에서 접근할 수 있습니다.

## OCI 콘솔에서 보안 리스트 설정하기

### 1. OCI 콘솔 로그인
https://cloud.oracle.com 접속

### 2. VCN 찾기
1. 햄버거 메뉴 → **Networking** → **Virtual Cloud Networks**
2. 사용 중인 VCN 선택 (배스천 서버가 속한 VCN)

### 3. 보안 리스트 편집
1. 왼쪽 메뉴에서 **Security Lists** 클릭
2. 배스천 서브넷에 연결된 보안 리스트 선택 (보통 "Default Security List for ..." 또는 Public Subnet용)
3. **Ingress Rules** 탭 클릭
4. **Add Ingress Rules** 버튼 클릭

### 4. 다음 규칙들을 추가

#### Rule 1: Grafana
- **Source Type**: CIDR
- **Source CIDR**: `0.0.0.0/0` (또는 특정 IP로 제한)
- **IP Protocol**: TCP
- **Source Port Range**: All
- **Destination Port Range**: `8080`
- **Description**: `Grafana Web UI`

#### Rule 2: Prometheus
- **Source Type**: CIDR
- **Source CIDR**: `0.0.0.0/0`
- **IP Protocol**: TCP
- **Source Port Range**: All
- **Destination Port Range**: `8090`
- **Description**: `Prometheus Web UI`

#### Rule 3: Loki
- **Source Type**: CIDR
- **Source CIDR**: `0.0.0.0/0`
- **IP Protocol**: TCP
- **Source Port Range**: All
- **Destination Port Range**: `8100`
- **Description**: `Loki API`

#### Rule 4: Alertmanager
- **Source Type**: CIDR
- **Source CIDR**: `0.0.0.0/0`
- **IP Protocol**: TCP
- **Source Port Range**: All
- **Destination Port Range**: `8093`
- **Description**: `Alertmanager Web UI`

#### Rule 5: Phoenix
- **Source Type**: CIDR
- **Source CIDR**: `0.0.0.0/0`
- **IP Protocol**: TCP
- **Source Port Range**: All
- **Destination Port Range**: `8006`
- **Description**: `Phoenix Web UI`
- **IP Protocol**: TCP
- **Source Port Range**: All
- **Destination Port Range**: `8093`
- **Description**: `Alertmanager Web UI`

### 5. 저장
**Add Ingress Rules** 버튼 클릭하여 규칙 저장

## 빠른 설정 (모든 포트를 한 번에)

위 4개의 규칙을 하나씩 추가하는 대신, 다음과 같이 설정할 수도 있습니다:

**옵션 A: 포트 범위로 추가 (간단)**
- **Source CIDR**: `0.0.0.0/0`
- **IP Protocol**: TCP
- **Destination Port Range**: `8080-8100,8093` (주의: OCI는 이런 형식을 지원하지 않을 수 있음)

**옵션 B: 개별 규칙으로 추가 (권장)**
- 위의 4개 규칙을 각각 추가

## 보안 강화 (프로덕션 환경)

테스트가 아닌 실제 환경에서는:

1. **소스 IP 제한**
   ```
   Source CIDR: <your-office-ip>/32
   또는
   Source CIDR: <vpn-gateway-ip>/32
   ```

2. **특정 서비스만 노출**
   - 예: Grafana(8080)만 외부 노출
   - 나머지는 내부 또는 VPN을 통해서만 접근

3. **Network Security Group (NSG) 사용**
   - 보안 리스트 대신 NSG를 사용하면 더 세밀한 제어 가능

## 설정 확인

### 로컬에서 확인
```bash
# 배스천 서버에서
curl http://localhost:8080
```

### 외부에서 확인
```bash
# 다른 컴퓨터에서
curl http://158.180.78.215:8080
```

또는 브라우저에서:
- http://158.180.78.215:8080 (Grafana)
- http://158.180.78.215:8090 (Prometheus)
- http://158.180.78.215:8100 (Loki)
- http://158.180.78.215:8093 (Alertmanager)

## 트러블슈팅

### 외부에서 접속이 안 되는 경우

1. **로컬 방화벽 확인**
   ```bash
   sudo firewall-cmd --list-ports
   # 8080/tcp 8090/tcp 8093/tcp 8100/tcp 가 있어야 함
   ```

2. **서비스 상태 확인**
   ```bash
   cd /app/mykubernetes/monitoring
   ./check-proxy-status.sh
   ```

3. **OCI 보안 리스트 재확인**
   - OCI 콘솔에서 Ingress Rules 확인
   - 올바른 서브넷의 보안 리스트인지 확인

4. **포트 리스닝 확인**
   ```bash
   sudo ss -tlnp | grep -E ':(8080|8090|8100|8093)'
   ```

5. **Nginx 로그 확인**
   ```bash
   sudo tail -f /var/log/nginx/access.log
   sudo tail -f /var/log/nginx/error.log
   ```

## 현재 설정된 포트 요약

| 서비스 | 포트 | 상태 |
|--------|------|------|
| Grafana | 8080 | ✅ firewalld 설정됨, ⚠️ OCI 보안 리스트 필요 |
| Prometheus | 8090 | ✅ firewalld 설정됨, ⚠️ OCI 보안 리스트 필요 |
| Loki | 8100 | ✅ firewalld 설정됨, ⚠️ OCI 보안 리스트 필요 |
| Alertmanager | 8093 | ✅ firewalld 설정됨, ⚠️ OCI 보안 리스트 필요 |

## 다음 단계

1. ✅ 배스천 서버 설정 완료
2. ✅ firewalld 설정 완료
3. ⚠️ **OCI 보안 리스트 설정 필요** ← 이 작업을 완료하세요!
4. 🔍 외부에서 접속 테스트
