# OCI FSS 통합 구성 가이드

## 개요

단일 FSS 파일시스템(`/oke_fss`)에서 여러 애플리케이션의 데이터를 서브디렉토리로 관리하는 통합 구성입니다.

### 기존 구성의 문제점
- 각 애플리케이션마다 별도의 FSS 파일시스템 및 마운트 타겟 생성
- OCI 무료 티어의 마운트 타겟 제한(AD당 2개)으로 인한 확장성 제한
- 리소스 관리 복잡도 증가

### 새로운 통합 구성
- 단일 FSS 파일시스템: `oke-fss-unified`
- 단일 마운트 타겟 재사용: `grafana-mt` (10.0.10.194)
- 단일 엑스포트 경로: `/oke_fss`
- 각 앱별 서브디렉토리:
  - `/oke_fss/grafana`
  - `/oke_fss/phoenix_postgres`
  - `/oke_fss/jenkins`

## 생성된 OCI 리소스 정보

### File System
```
OCID: ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamuxirvpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa
Name: oke-fss-unified
AD: NnPr:AP-CHUNCHEON-1-AD-1
```

### Mount Target (재사용)
```
OCID: ocid1.mounttarget.oc1.ap_chuncheon_1.aaaaaa4np2weabbzpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa
Name: grafana-mt
Private IP: 10.0.10.194
Subnet: ocid1.subnet.oc1.ap-chuncheon-1.aaaaaaaaxb2frgb2wng2znerx46cmtpcjxrnj4qyckhkg24pl4dtxwmhr4da
```

### Export
```
OCID: ocid1.export.oc1.ap_chuncheon_1.aaaaaa4np2weim52pfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa
Path: /oke_fss
Export Set: ocid1.exportset.oc1.ap_chuncheon_1.aaaaaa4np2weabbypfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa
Export Options:
  - source: 10.0.10.0/24
  - access: READ_WRITE
  - identitySquash: NONE
```

## 디렉토리 구조 초기화

```bash
# FSS 마운트 및 디렉토리 생성용 임시 Pod
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: fss-setup
  namespace: default
spec:
  containers:
  - name: setup
    image: busybox
    command: ['sh', '-c', 'mkdir -p /mnt/oke_fss/grafana /mnt/oke_fss/phoenix_postgres /mnt/oke_fss/jenkins && chmod 777 /mnt/oke_fss/grafana /mnt/oke_fss/phoenix_postgres /mnt/oke_fss/jenkins && ls -la /mnt/oke_fss/ && sleep 3600']
    volumeMounts:
    - name: fss-volume
      mountPath: /mnt/oke_fss
  volumes:
  - name: fss-volume
    nfs:
      server: 10.0.10.194
      path: /oke_fss
EOF

# 디렉토리 확인
kubectl logs fss-setup

# 정리
kubectl delete pod fss-setup
```

## 애플리케이션별 적용 방법

### 1. Grafana

#### PV 생성
```bash
kubectl apply -f unified-fss-pv.yaml
```

`unified-fss-pv.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: grafana-unified-fss-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: fss.csi.oraclecloud.com
    volumeHandle: ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamuxirvpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa:/oke_fss/grafana
  mountOptions:
    - nosuid
```

#### PVC 업데이트
```bash
# 기존 PVC 삭제 (데이터 백업 후)
kubectl delete pvc grafana -n monitoring

# 새 PVC 생성
kubectl apply -f unified-fss-pvc.yaml
```

#### Grafana Values 업데이트
```yaml
# grafana-values.yaml
persistence:
  enabled: true
  type: pvc
  existingClaim: grafana-unified  # 변경됨
```

#### Grafana 재배포
```bash
helm upgrade grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml
```

### 2. Phoenix PostgreSQL

#### Kustomize 파일 업데이트

`/app/mykubernetes/kustomize/phoenix/base/postgres-pv.yaml` (새로 생성):
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: phoenix-postgres-unified-fss-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: fss.csi.oraclecloud.com
    volumeHandle: ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamuxirvpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa:/oke_fss/phoenix_postgres
  mountOptions:
    - nosuid
```

`postgres.yaml` 수정:
```yaml
# StatefulSet의 volumeClaimTemplates를 제거하고 PVC를 별도 정의
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: phoenix-postgres-data
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 10Gi
  volumeName: phoenix-postgres-unified-fss-pv
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  # ... (기존 내용)
  template:
    spec:
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: phoenix-postgres-data
  # volumeClaimTemplates 섹션 제거
```

### 3. Jenkins (미래 적용)

Jenkins 네임스페이스 생성 후:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-unified-fss-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: fss.csi.oraclecloud.com
    volumeHandle: ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamuxirvpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa:/oke_fss/jenkins
  mountOptions:
    - nosuid
```

## 기존 FSS 리소스 정리

### 삭제할 리소스 목록

1. **Phoenix PostgreSQL 기존 FSS**
   - File System: `csi-fss-94a23706-f9d2-4702-8808-6ddee1159b20`
   - Mount Target: `csi-fss-94a23706-f9d2-4702-8808-6ddee1159b20`
   - OCID: `ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamuequ4pfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa`

2. **Grafana 기존 FSS**
   - File System: `grafana-fss`
   - OCID: `ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamucyvcpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa`
   - Export Path: `/grafana`

### 정리 스크립트

```bash
# 주의: 새 구성으로 완전히 마이그레이션된 후에만 실행!

# 1. Export 삭제
oci fs export list --compartment-id ocid1.tenancy.oc1..aaaaaaaahsnrg2djzni7cvjs7dbd5xadz2l6pr3hsz7fd677tp7ikdcduxea \
  --lifecycle-state ACTIVE | \
  jq -r '.data[] | select(.path == "/grafana" or .path | startswith("/csi-fss")) | .id' | \
  while read export_id; do
    oci fs export delete --export-id "$export_id" --force
  done

# 2. 기존 File System 삭제
oci fs file-system delete \
  --file-system-id ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamuequ4pfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa \
  --force

oci fs file-system delete \
  --file-system-id ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamucyvcpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa \
  --force

# 3. 불필요한 Mount Target 삭제 (Phoenix용)
oci fs mount-target delete \
  --mount-target-id ocid1.mounttarget.oc1.ap_chuncheon_1.aaaaaa4np2weaqabpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa \
  --force
```

## 마이그레이션 체크리스트

### 사전 작업
- [ ] 기존 Grafana 데이터 백업
- [ ] 기존 Phoenix PostgreSQL 데이터 백업
- [ ] 통합 FSS 생성 완료 확인
- [ ] 서브디렉토리 생성 완료 확인

### Grafana 마이그레이션
- [ ] 기존 Grafana 데이터를 `/oke_fss/grafana`로 복사
- [ ] 새 PV/PVC 생성
- [ ] Grafana Helm values 업데이트
- [ ] Grafana 재배포
- [ ] 데이터 확인

### Phoenix PostgreSQL 마이그레이션
- [ ] 기존 PostgreSQL 데이터를 `/oke_fss/phoenix_postgres`로 복사
- [ ] StatefulSet을 Deployment+PVC로 변경
- [ ] 새 PV/PVC 생성
- [ ] Kustomize 재배포
- [ ] 데이터베이스 연결 확인

### 정리 작업
- [ ] 기존 FSS 리소스 삭제
- [ ] 기존 PV/PVC 삭제
- [ ] OCI Console에서 리소스 확인

## 장점

1. **리소스 효율성**: 단일 FSS와 마운트 타겟으로 여러 앱 지원
2. **확장성**: 마운트 타겟 제한 우회
3. **관리 용이성**: 통합된 스토리지 관리
4. **비용 절감**: 불필요한 리소스 제거
5. **유연성**: 새 앱 추가 시 서브디렉토리만 생성

## 주의사항

1. **권한 관리**: 각 서브디렉토리의 권한 설정 필수
2. **데이터 격리**: 앱 간 데이터 격리는 디렉토리 수준에서만 보장
3. **백업**: 마이그레이션 전 반드시 기존 데이터 백업
4. **순차 마이그레이션**: 한 번에 하나씩 앱을 마이그레이션

## 트러블슈팅

### Permission Denied 오류
```bash
# FSS 서브디렉토리 권한 확인
kubectl exec -it fss-setup -- ls -la /mnt/oke_fss/

# 권한 수정
kubectl exec -it fss-setup -- chmod 777 /mnt/oke_fss/<app_name>
```

### PV가 Available 상태로 유지
- PVC의 `volumeName`과 PV의 `metadata.name`이 일치하는지 확인
- PV의 `capacity`와 PVC의 `requests.storage`가 일치하는지 확인

### Pod가 ContainerCreating 상태
```bash
# Pod 이벤트 확인
kubectl describe pod <pod-name> -n <namespace>

# FSS Export 확인
oci fs export list --compartment-id <compartment-id> --lifecycle-state ACTIVE
```

## 참고 링크

- [OCI FSS 문서](https://docs.oracle.com/en-us/iaas/Content/File/Concepts/filestorageoverview.htm)
- [Kubernetes Static Provisioning](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#static)
