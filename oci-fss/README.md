# OCI FSS (File Storage Service) - OKE 연결 가이드

OCI File Storage Service를 OKE 클러스터에 연결하는 빠른 가이드입니다.

## 파일 구성

| 파일 | 설명 |
|------|------|
| `fss-storageclass.yaml` | FSS용 StorageClass (동적 프로비저닝용) |
| `fs-manage-pv.yaml` | 기존 FSS 연결용 PersistentVolume |
| `fs-manage-pvc.yaml` | PersistentVolumeClaim |
| `fss-manage-pod.yaml` | 테스트용 Pod |
| `FSS-PVC-CONFIGURATION-GUIDE.md` | 상세 가이드 문서 |

---

## 빠른 시작

### 1. 기존 File System을 OKE에 연결하기

```bash
# PV, PVC, 테스트 Pod 적용
kubectl apply -f fs-manage-pv.yaml
kubectl apply -f fs-manage-pvc.yaml
kubectl apply -f fss-manage-pod.yaml

# 상태 확인
kubectl get pv,pvc,pod
```

### 2. PV의 volumeHandle 형식

```yaml
volumeHandle: "<FileSystem-OCID>:<Mount-Target-IP>:<Export-Path>"
# 예시:
volumeHandle: "ocid1.filesystem.oc1.ap_chuncheon_1.aaaa...:10.0.10.213:/oke-fss"
```

---

## 트러블슈팅: mount.nfs: Connection timed out

### 증상
```
Pod가 ContainerCreating 상태에서 멈춤
CSI 로그: "mount.nfs: Connection timed out"
```

### 원인 확인

```bash
# 1. Mount Target의 VCN 확인
MT_SUBNET=$(oci fs mount-target get \
  --mount-target-id <MOUNT_TARGET_OCID> \
  --query 'data."subnet-id"' --raw-output)

MT_VCN=$(oci network subnet get \
  --subnet-id $MT_SUBNET \
  --query 'data."vcn-id"' --raw-output)

echo "Mount Target VCN: $MT_VCN"

# 2. Worker Node의 VCN 확인
NODE_INSTANCE=$(oci compute instance list \
  --compartment-id <COMPARTMENT_OCID> \
  --query 'data[?contains("display-name", `oke-`)].id | [0]' --raw-output)

WN_SUBNET=$(oci compute instance list-vnics \
  --instance-id $NODE_INSTANCE \
  --query 'data[0]."subnet-id"' --raw-output)

WN_VCN=$(oci network subnet get \
  --subnet-id $WN_SUBNET \
  --query 'data."vcn-id"' --raw-output)

echo "Worker Node VCN: $WN_VCN"

# 3. VCN 비교
if [ "$MT_VCN" == "$WN_VCN" ]; then
  echo "Same VCN - Security List/NSG 확인 필요"
else
  echo "Different VCN - 새 Mount Target 필요!"
fi
```

### 해결 방법: VCN이 다른 경우

OCI FSS 구조:
```
File System (데이터 저장)
    ├── Mount Target A (기존 VCN) ← 기존 클러스터용
    └── Mount Target B (신규 VCN) ← 신규 클러스터용 (새로 생성)
```

**핵심: File System 데이터는 유지하면서 새 VCN에 Mount Target만 추가**

#### Step 1: 새 Mount Target 생성 (OCI Console 또는 CLI)

```bash
# Worker Node 서브넷 정보 확인
oci network subnet list \
  --compartment-id <COMPARTMENT_OCID> \
  --vcn-id <WORKER_NODE_VCN_OCID> \
  --query 'data[*].{name:"display-name",id:id,cidr:"cidr-block"}' \
  --output table

# 새 Mount Target 생성
oci fs mount-target create \
  --compartment-id <COMPARTMENT_OCID> \
  --availability-domain <AD_NAME> \
  --subnet-id <WORKER_NODE_SUBNET_OCID> \
  --display-name "oke-fss-new" \
  --wait-for-state ACTIVE
```

#### Step 2: 기존 File System을 새 Mount Target에 Export

```bash
# 새 Mount Target의 Export Set ID 확인
EXPORT_SET_ID=$(oci fs mount-target get \
  --mount-target-id <NEW_MOUNT_TARGET_OCID> \
  --query 'data."export-set-id"' --raw-output)

# Export 생성
oci fs export create \
  --export-set-id $EXPORT_SET_ID \
  --file-system-id <EXISTING_FILESYSTEM_OCID> \
  --path /oke-fss \
  --export-options '[{
    "source":"10.0.10.0/24",
    "requirePrivilegedSourcePort":false,
    "access":"READ_WRITE",
    "identitySquash":"NONE",
    "anonymousUid":65534,
    "anonymousGid":65534
  }]' \
  --wait-for-state ACTIVE
```

#### Step 3: 새 Mount Target IP 확인

```bash
# Private IP ID 확인
PRIVATE_IP_ID=$(oci fs mount-target get \
  --mount-target-id <NEW_MOUNT_TARGET_OCID> \
  --query 'data."private-ip-ids"[0]' --raw-output)

# IP 주소 확인
oci network private-ip get \
  --private-ip-id $PRIVATE_IP_ID \
  --query 'data."ip-address"' --raw-output
```

#### Step 4: PV 업데이트 및 재적용

```bash
# fs-manage-pv.yaml의 volumeHandle에서 IP 변경
# 예: 10.0.10.194 → 10.0.10.213

# 기존 리소스 삭제 후 재생성
kubectl delete pod fss-debug-pod
kubectl delete pvc fss-manage-pvc
kubectl delete pv fss-manage-pv

kubectl apply -f fs-manage-pv.yaml
kubectl apply -f fs-manage-pvc.yaml
kubectl apply -f fss-manage-pod.yaml

# 상태 확인
kubectl get pv,pvc,pod
```

---

## 현재 설정 정보

| 항목 | 값 |
|------|-----|
| File System OCID | `ocid1.filesystem.oc1.ap_chuncheon_1.aaaaaaaaaamxymxdpfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa` |
| Mount Target (신규) | `ocid1.mounttarget.oc1.ap_chuncheon_1.aaaaaa4np2wienjopfxhsllqojxwiotboawwg2dvnzrwqzlpnywtcllbmqwtcaaa` |
| Mount Target IP | `10.0.10.213` |
| Export Path | `/oke-fss` |
| Worker Subnet CIDR | `10.0.10.0/24` |

---

## 참고

- 상세한 구성 가이드는 [FSS-PVC-CONFIGURATION-GUIDE.md](./FSS-PVC-CONFIGURATION-GUIDE.md) 참조
- OCI FSS 문서: https://docs.oracle.com/en-us/iaas/Content/File/Concepts/filestorageoverview.htm
