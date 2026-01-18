# PostgreSQL Helm Chart with OCI FSS Support

이 Helm Chart는 Oracle Cloud Infrastructure (OCI) File Storage Service (FSS)를 사용하여 PostgreSQL을 배포합니다.

## 기능

- ✅ OCI FSS를 사용한 영구 스토리지 (PV/PVC)
- ✅ LoadBalancer 서비스를 통한 외부 접근
- ✅ Ingress를 통한 HTTP/HTTPS 접근 지원
- ✅ Health Check (Liveness/Readiness Probes)
- ✅ 리소스 제한 설정
- ✅ Prometheus 메트릭 지원 준비

## 사전 요구사항

1. Kubernetes 클러스터 (OKE 권장)
2. Helm 3.x 설치
3. OCI FSS Export 생성 및 Mount Target IP
4. NGINX Ingress Controller 설치 (Ingress 사용 시)

## 설치 방법

### 1. OCI FSS volumeHandle 확인

OCI Console에서 FSS Export 정보를 확인하고 `values.yaml`에서 다음 형식으로 설정:

```yaml
persistence:
  ociFss:
    enabled: true
    volumeHandle: "ocid1.export.oc1.<region>.<export_id>:<mount_target_ip>:/<export_path>"
```

### 2. values.yaml 수정

배포 전에 `values.yaml` 파일에서 다음 항목들을 수정하세요:

```yaml
# PostgreSQL 인증 정보
environmentVariables:
  POSTGRES_USER: your-username
  POSTGRES_PASSWORD: your-secure-password
  POSTGRES_DB: your-database

# OCI FSS 설정
persistence:
  ociFss:
    volumeHandle: "your-oci-fss-volume-handle"

# Ingress 호스트명
ingress:
  hosts:
    - host: postgres.your-domain.com
```

### 3. PV/PVC 생성 (선택사항)

persistence.pvcName을 사용하는 경우 먼저 PVC를 생성해야 합니다:

```bash
# PVC 생성 (예: monitoring/pv-pvc/postgres-pvc-confirmed.yaml 참조)
kubectl apply -f postgres-pvc.yaml
```

### 4. Helm Chart 설치

```bash
# postgres 네임스페이스에 설치 (권장)
helm install postgres . -n postgres --create-namespace

# 또는 커스텀 values 파일 사용
helm install postgres . -n postgres --create-namespace -f custom-values.yaml
```

### 5. 설치 확인

```bash
# Pod 상태 확인
kubectl get pods -n postgres

# Service 확인
kubectl get svc -n postgres

# Ingress 확인 (활성화된 경우)
kubectl get ingress -n postgres

# PV/PVC 확인
kubectl get pv,pvc -n postgres
```

## 외부 접속 방법

### 1. ClusterIP를 통한 접속 (클러스터 내부)

```bash
# Pod 내부에서 접속
kubectl run -it --rm psql-client --image=postgres:16.7 --restart=Never -n postgres -- \
  psql -h postgres-postgresql -U postgres -d postgresdb

# 또는 Port Forward로 로컬에서 접속
kubectl port-forward -n postgres svc/postgres-postgresql 5432:5432
psql -h localhost -U postgres -d postgresdb
```

### 2. LoadBalancer를 통한 직접 접속 (Service Type 변경 필요)

```bash
# External IP 확인
EXTERNAL_IP=$(kubectl get svc postgres-postgresql -n postgres -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# psql 클라이언트로 접속
psql -h $EXTERNAL_IP -U postgres -d postgresdb
```

### 3. Ingress를 통한 접속 (비권장)

Ingress가 활성화된 경우 설정한 도메인으로 접속 가능합니다:

```bash
psql -h postgres.your-domain.com -U postgres -d postgresdb
```

**참고**: Ingress를 통한 PostgreSQL 접속은 일반적이지 않으며, TCP 연결을 지원하는 Ingress Controller가 필요합니다. ClusterIP + Port Forward 또는 LoadBalancer 사용을 권장합니다.

## 구성 옵션

### Service Type 변경

```yaml
service:
  type: LoadBalancer  # ClusterIP, NodePort, LoadBalancer
  port: 5432
  # nodePort: 30432  # NodePort 사용 시
  # loadBalancerIP: "1.2.3.4"  # 고정 IP 사용 시
```

### 리소스 제한

```yaml
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### 스토리지 크기 변경

```yaml
persistence:
  size: 20Gi  # 필요한 크기로 변경
```

## 업그레이드

```bash
# values.yaml 수정 후
helm upgrade postgres . -n postgres

# 또는 특정 값만 변경
helm upgrade postgres . -n postgres --set replicaCount=1
```

## 삭제

```bash
# Helm Release 삭제
helm uninstall postgres -n postgres

# PVC 삭제
kubectl delete pvc postgres-postgresql-data-0 -n postgres

# PV는 Retain 정책으로 보존됩니다. 완전 삭제 시:
kubectl delete pv postgres-fss-pv
```

## 문제 해결

### Pod가 Pending 상태인 경우

```bash
# Pod 상세 정보 확인
kubectl describe pod <pod-name> -n postgres

# PVC 상태 확인
kubectl get pvc -n postgres
kubectl describe pvc postgres-postgresql-data-0 -n postgres

# PV 바인딩 확인
kubectl get pv postgres-fss-pv
```

**일반적인 원인:**
- PVC가 존재하지 않음 (persistence.pvcName 설정 시)
- PV가 다른 PVC에 바인딩되어 있음
- PV의 claimRef를 제거해야 할 수 있음:
  ```bash
  kubectl patch pv postgres-fss-pv -p '{"spec":{"claimRef": null}}'
  ```

### LoadBalancer External IP가 할당되지 않는 경우

OCI 환경에서는 자동으로 할당되지만, 시간이 걸릴 수 있습니다. 몇 분 기다린 후 다시 확인하세요.

기본 설정은 ClusterIP이므로 LoadBalancer가 필요한 경우 values.yaml에서 변경하세요:
```yaml
service:
  type: LoadBalancer
```

### 데이터베이스 접속이 안 되는 경우

```bash
# Pod 로그 확인
kubectl logs <pod-name> -n postgres

# PostgreSQL이 준비되었는지 확인
kubectl exec -it <pod-name> -n postgres -- pg_isready

# 연결 테스트
kubectl exec -it <pod-name> -n postgres -- psql -U postgres -d postgresdb -c "\l"
```

## 보안 고려사항

1. **비밀번호 관리**: 프로덕션 환경에서는 Kubernetes Secret을 사용하세요
2. **네트워크 정책**: 필요한 경우 NetworkPolicy를 추가하세요
3. **TLS/SSL**: Ingress에서 TLS 인증서를 구성하세요
4. **백업**: 정기적인 데이터베이스 백업 전략을 수립하세요

## 참고 자료

- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/)
- [OCI File Storage Service](https://docs.oracle.com/en-us/iaas/Content/File/Concepts/filestorageoverview.htm)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
