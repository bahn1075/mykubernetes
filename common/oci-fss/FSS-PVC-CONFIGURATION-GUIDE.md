# OCI FSS (File Storage Service) PVC 구성 가이드

이 문서는 Oracle Cloud Infrastructure (OCI)의 File Storage Service (FSS)를 Kubernetes Persistent Volume Claim (PVC)으로 구성하는 전체 프로세스를 설명합니다.

## 목차
1. [개요](#개요)
2. [사전 요구사항](#사전-요구사항)
3. [FSS 구성 단계](#fss-구성-단계)
4. [Helm Values 파일 수정](#helm-values-파일-수정)
5. [검증 및 테스트](#검증-및-테스트)
6. [트러블슈팅](#트러블슈팅)
7. [실제 적용 예시](#실제-적용-예시)

---

## 개요

### FSS를 PVC로 사용하는 이유
- **데이터 영속성**: Pod 재시작/재배포 시에도 데이터 보존
- **공유 스토리지**: 여러 Pod에서 동시 접근 가능 (ReadWriteMany)
- **확장성**: OCI의 관리형 스토리지로 자동 확장
- **백업**: OCI FSS의 스냅샷 기능 활용 가능

### 적용 대상 서비스
- Grafana (대시보드, 플러그인 데이터)
- Prometheus (메트릭 데이터)
- Loki (로그 데이터)
- 기타 상태를 유지해야 하는 모든 서비스

---

## 사전 요구사항

### 1. OCI 리소스 정보 수집

다음 정보를 OCI Console에서 확인하고 기록하세요:

#### a) Availability Domain
```bash
# OCI CLI로 확인
oci iam availability-domain list --compartment-id <compartment-ocid>

# 예시 출력:
# NnPr:AP-CHUNCHEON-1-AD-1
```

#### b) Mount Target Subnet OCID
- **위치**: OCI Console > File Storage > Mount Targets
- **필요 정보**: Mount Target이 위치한 Subnet의 OCID
- **형식**: `ocid1.subnet.oc1.ap-chuncheon-1.aaaaaaa...`

#### c) Compartment OCID
- **위치**: OCI Console > Identity > Compartments
- **필요 정보**: FSS를 생성할 Compartment의 OCID
- **형식**: `ocid1.tenancy.oc1..aaaaaaa...` 또는 `ocid1.compartment.oc1..aaaaaaa...`

#### d) Subnet CIDR (Worker Node Subnet)
- **위치**: OCI Console > Networking > Virtual Cloud Networks > Subnets
- **필요 정보**: Kubernetes Worker Node들이 위치한 Subnet의 CIDR
- **예시**: `10.0.10.0/24`

### 2. Kubernetes 환경 확인

```bash
# CSI Driver 확인
kubectl get csidriver fss.csi.oraclecloud.com

# 출력 예시:
# NAME                      ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES        AGE
# fss.csi.oraclecloud.com   false            false            false             <unset>         false               Persistent   100d
```

> **중요**: OCI Container Engine for Kubernetes (OKE)를 사용하는 경우, FSS CSI Driver가 기본적으로 설치되어 있습니다.

---

## FSS 구성 단계

### Step 1: StorageClass 생성

`fss-storageclass.yaml` 파일을 생성합니다:

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: oci-fss
provisioner: fss.csi.oraclecloud.com
parameters:
  # OCI Availability Domain
  availabilityDomain: <YOUR_AVAILABILITY_DOMAIN>
  
  # Mount Target Subnet OCID
  mountTargetSubnetOcid: <YOUR_MOUNT_TARGET_SUBNET_OCID>
  
  # Compartment OCID
  compartmentOcid: <YOUR_COMPARTMENT_OCID>
  
  # Export Options (NFS 접근 제어)
  # source: Worker Node Subnet CIDR
  exportOptions: "[{\"source\":\"<YOUR_WORKER_SUBNET_CIDR>\",\"requirePrivilegedSourcePort\":false,\"access\":\"READ_WRITE\",\"identitySquash\":\"NONE\"}]"

reclaimPolicy: Delete
volumeBindingMode: Immediate
```

#### 파라미터 설명

| 파라미터 | 설명 | 예시 |
|---------|------|------|
| `availabilityDomain` | FSS가 생성될 AD | `NnPr:AP-CHUNCHEON-1-AD-1` |
| `mountTargetSubnetOcid` | Mount Target Subnet | `ocid1.subnet.oc1...` |
| `compartmentOcid` | Compartment OCID | `ocid1.tenancy.oc1...` |
| `exportOptions.source` | 접근 허용 Subnet CIDR | `10.0.10.0/24` |
| `exportOptions.access` | 접근 권한 | `READ_WRITE` |
| `exportOptions.identitySquash` | UID/GID 매핑 | `NONE` (권장) |

#### StorageClass 적용

```bash
kubectl apply -f fss-storageclass.yaml
```

#### 검증

```bash
# StorageClass 확인
kubectl get storageclass oci-fss

# 출력 예시:
# NAME      PROVISIONER               RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
# oci-fss   fss.csi.oraclecloud.com   Delete          Immediate           false                  10s
```

#### default storageclass 변경

# 현재 default 제거
kubectl patch storageclass oci-bv -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# oci-fss를 default로 설정
kubectl patch storageclass oci-fss -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
storageclass.storage.k8s.io/oci-bv patched
storageclass.storage.k8s.io/oci-fss patched



### Step 2: PV/PVC 구성 방식 선택

FSS PVC를 생성하는 방법은 2가지가 있습니다:

#### 방법 1: 동적 프로비저닝 (권장)
- StorageClass를 참조하는 PVC만 생성
- PV는 자동으로 생성됨
- 가장 간단하고 권장되는 방법

#### 방법 2: 정적 프로비저닝
- PV와 PVC를 모두 수동으로 생성
- 기존 FSS를 재사용할 때 사용

### Step 3-A: 동적 프로비저닝 (권장)

PVC 파일만 생성하면 됩니다 (PV는 자동 생성):

```yaml
# 예시: grafana-fss-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-storage
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: oci-fss
  resources:
    requests:
      storage: 10Gi
```

```bash
# PVC 적용 (PV는 자동 생성됨)
kubectl apply -f grafana-fss-pvc.yaml
```

### Step 3-B: 정적 프로비저닝 (선택사항)

기존 FSS를 사용하는 경우:

```yaml
# grafana-fss-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: grafana-fss-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: oci-fss
  mountOptions:
    - nosuid
  csi:
    driver: fss.csi.oraclecloud.com
    volumeHandle: <EXISTING_FSS_OCID>:<EXPORT_PATH>
    volumeAttributes:
      availabilityDomain: <YOUR_AVAILABILITY_DOMAIN>
---
# grafana-fss-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-storage
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: oci-fss
  resources:
    requests:
      storage: 10Gi
  volumeName: grafana-fss-pv
```

---

## Helm Values 파일 수정

서비스의 Helm Values 파일에서 persistence 설정을 수정합니다.

### Grafana 예시

```yaml
# grafana-values.yaml
persistence:
  enabled: true
  type: pvc
  storageClassName: oci-fss  # FSS StorageClass 사용
  accessModes:
    - ReadWriteMany          # 여러 Pod에서 접근 가능
  size: 10Gi                 # 요청 크기 (FSS는 자동 확장)
```

### Prometheus 예시

```yaml
# prometheus-values.yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: oci-fss
          accessModes: 
            - ReadWriteMany
          resources:
            requests:
              storage: 50Gi
```

### Loki 예시

```yaml
# loki-values.yaml
loki:
  storage:
    type: filesystem
    filesystem:
      chunks_directory: /var/loki/chunks
      rules_directory: /var/loki/rules

persistence:
  enabled: true
  storageClassName: oci-fss
  accessModes:
    - ReadWriteMany
  size: 30Gi
```

### 기타 서비스 공통 패턴

대부분의 Helm Chart는 다음 형식을 따릅니다:

```yaml
persistence:
  enabled: true
  storageClassName: oci-fss
  accessModes:
    - ReadWriteMany
  size: <원하는_크기>Gi
```

---

## 검증 및 테스트

### 1. PVC 상태 확인

```bash
# PVC 목록 확인
kubectl get pvc -n <namespace>

# 출력 예시:
# NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# grafana-storage   Bound    pvc-abc123...                              10Gi       RWX            oci-fss        5m
```

**STATUS가 `Bound`여야 정상입니다.**

### 2. PV 상태 확인

```bash
# PV 목록 확인
kubectl get pv

# 출력 예시:
# NAME            CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                         STORAGECLASS   AGE
# pvc-abc123...   10Gi       RWX            Delete           Bound    monitoring/grafana-storage    oci-fss        5m
```

### 3. Pod에서 마운트 확인

```bash
# Pod 내부에서 확인
kubectl exec -n <namespace> <pod-name> -- df -h

# 출력에서 FSS 마운트 확인:
# Filesystem                Size  Used Avail Use% Mounted on
# <FSS_IP>:/grafana-xxx    8.0E     0  8.0E   0% /var/lib/grafana
```

### 4. OCI Console에서 확인

1. **OCI Console** > **File Storage** > **File Systems**
2. 새로 생성된 File System 확인
3. Export Path 및 Mount Target 확인

### 5. 데이터 영속성 테스트

```bash
# 1. Pod에서 테스트 파일 생성
kubectl exec -n <namespace> <pod-name> -- touch /var/lib/grafana/test-file.txt

# 2. Pod 삭제
kubectl delete pod -n <namespace> <pod-name>

# 3. Pod가 자동으로 재생성된 후 파일 확인
kubectl exec -n <namespace> <pod-name> -- ls -la /var/lib/grafana/test-file.txt

# 파일이 존재하면 영속성 확인 완료
```

---

## 트러블슈팅

### 문제 1: PVC가 Pending 상태

```bash
# PVC 상세 정보 확인
kubectl describe pvc -n <namespace> <pvc-name>

# Events 섹션에서 오류 확인
```

**일반적인 원인:**

1. **StorageClass 이름 오타**
   ```bash
   # StorageClass 이름 확인
   kubectl get storageclass
   ```

2. **CSI Driver 미설치**
   ```bash
   # CSI Driver 확인
   kubectl get csidriver fss.csi.oraclecloud.com
   ```

3. **OCI 권한 문제**
   - Instance Principal 또는 User Principal 권한 확인
   - Compartment에 대한 FSS 생성 권한 확인

### 문제 2: Pod가 ContainerCreating 상태

```bash
# Pod 이벤트 확인
kubectl describe pod -n <namespace> <pod-name>

# 일반적으로 "Unable to attach or mount volumes" 오류 표시
```

**일반적인 원인:**

1. **Mount Target Subnet이 Worker Node와 다른 경우**
   - Mount Target과 Worker Node가 같은 VCN에 있어야 함
   - Security List/NSG에서 NFS 포트(2048-2050, 111) 허용 필요

2. **Export Options의 source CIDR 불일치**
   ```yaml
   # Worker Node Subnet CIDR와 일치하는지 확인
   exportOptions: "[{\"source\":\"10.0.10.0/24\", ...}]"
   ```

### 문제 3: 권한 오류 (Permission Denied)

```bash
# Pod 로그 확인
kubectl logs -n <namespace> <pod-name>

# "Permission denied" 오류가 나타나는 경우
```

**해결 방법:**

1. **identitySquash 설정 확인**
   ```yaml
   exportOptions: "[{..., \"identitySquash\":\"NONE\"}]"
   ```

2. **Pod의 securityContext 설정**
   ```yaml
   securityContext:
     fsGroup: 472  # Grafana의 경우
     runAsUser: 472
   ```

3. **initContainer로 권한 설정**
   ```yaml
   initContainers:
   - name: fix-permissions
     image: busybox
     command: ['sh', '-c', 'chmod -R 777 /var/lib/grafana']
     volumeMounts:
     - name: storage
       mountPath: /var/lib/grafana
   ```

### 문제 4: FSS 생성 실패

```bash
# CSI Controller 로그 확인
kubectl logs -n kube-system -l app=csi-oci-fss-controller
```

**일반적인 원인:**

1. **Compartment OCID 오류**
   - 정확한 Compartment OCID 입력 확인

2. **Availability Domain 불일치**
   - Mount Target과 같은 AD 사용 확인

3. **Quota 초과**
   - OCI Console에서 FSS Quota 확인

---

## 실제 적용 예시

### 사례 1: Grafana FSS 구성

#### 1. StorageClass 생성
```yaml
# fss-storageclass.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: oci-fss
provisioner: fss.csi.oraclecloud.com
parameters:
  availabilityDomain: NnPr:AP-CHUNCHEON-1-AD-1
  mountTargetSubnetOcid: ocid1.subnet.oc1.ap-chuncheon-1.aaaaaaaaxb2frgb2wng2znerx46cmtpcjxrnj4qyckhkg24pl4dtxwmhr4da
  compartmentOcid: ocid1.tenancy.oc1..aaaaaaaahsnrg2djzni7cvjs7dbd5xadz2l6pr3hsz7fd677tp7ikdcduxea
  exportOptions: "[{\"source\":\"10.0.10.0/24\",\"requirePrivilegedSourcePort\":false,\"access\":\"READ_WRITE\",\"identitySquash\":\"NONE\"}]"
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

```bash
kubectl apply -f fss-storageclass.yaml
```

#### 2. Grafana Values 수정
```yaml
# grafana-values.yaml
image:
  repository: grafana/grafana
  tag: latest

adminUser: admin
adminPassword: admin123

# FSS PVC 사용
persistence:
  enabled: true
  type: pvc
  storageClassName: oci-fss
  accessModes:
    - ReadWriteMany
  size: 10Gi

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-prometheus.monitoring.svc.cluster.local:9090
        access: proxy
        isDefault: true

service:
  type: ClusterIP
  port: 80
```

#### 3. Grafana 설치
```bash
# Helm으로 설치 (PVC 자동 생성)
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml

# 또는 업그레이드
helm upgrade grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml
```

#### 4. 검증
```bash
# PVC 확인
kubectl get pvc -n monitoring
# NAME                        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# grafana                     Bound    pvc-abc123...                              10Gi       RWX            oci-fss        2m

# Pod 확인
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
# NAME                       READY   STATUS    RESTARTS   AGE
# grafana-7d9f8c5b6d-xyz     1/1     Running   0          2m

# 마운트 확인
kubectl exec -n monitoring grafana-7d9f8c5b6d-xyz -- df -h | grep grafana
# 10.0.20.123:/grafana-pvc-abc123   8.0E     0  8.0E   0% /var/lib/grafana
```

### 사례 2: 여러 서비스에 FSS 적용

#### 1. 공통 StorageClass 재사용
```bash
# 이미 생성된 oci-fss StorageClass를 모든 서비스에서 재사용
kubectl get storageclass oci-fss
```

#### 2. 각 서비스별 Values 수정

**Prometheus:**
```yaml
# prometheus-values.yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: oci-fss
          accessModes: 
            - ReadWriteMany
          resources:
            requests:
              storage: 50Gi
```

**Loki:**
```yaml
# loki-values.yaml
loki:
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem

singleBinary:
  persistence:
    enabled: true
    storageClass: oci-fss
    size: 30Gi
```

**AlertManager:**
```yaml
# alertmanager-values.yaml (kube-prometheus-stack 내)
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: oci-fss
          accessModes:
            - ReadWriteMany
          resources:
            requests:
              storage: 10Gi
```

#### 3. 순차적으로 적용
```bash
# Prometheus 업그레이드
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml

# Loki 업그레이드
helm upgrade loki grafana/loki \
  --namespace monitoring \
  --values loki-values.yaml

# PVC 상태 확인
kubectl get pvc -n monitoring
```

---

## 체크리스트

새로운 서비스에 FSS PVC를 적용할 때 다음 체크리스트를 사용하세요:

### 사전 준비
- [ ] OCI Availability Domain 확인
- [ ] Mount Target Subnet OCID 확인
- [ ] Compartment OCID 확인
- [ ] Worker Node Subnet CIDR 확인
- [ ] CSI Driver 설치 확인: `kubectl get csidriver fss.csi.oraclecloud.com`

### StorageClass 구성
- [ ] `fss-storageclass.yaml` 생성
- [ ] 모든 OCID 및 파라미터 정확히 입력
- [ ] `kubectl apply -f fss-storageclass.yaml` 실행
- [ ] `kubectl get storageclass oci-fss` 로 확인

### Helm Values 수정
- [ ] 서비스의 values 파일에서 `persistence` 섹션 찾기
- [ ] `enabled: true` 설정
- [ ] `storageClassName: oci-fss` 설정
- [ ] `accessModes: [ReadWriteMany]` 설정
- [ ] 적절한 `size` 지정

### 배포 및 검증
- [ ] Helm install 또는 upgrade 실행
- [ ] PVC Bound 상태 확인: `kubectl get pvc -n <namespace>`
- [ ] Pod Running 상태 확인: `kubectl get pods -n <namespace>`
- [ ] Pod 내부 마운트 확인: `kubectl exec ... -- df -h`
- [ ] OCI Console에서 FSS 생성 확인

### 영속성 테스트
- [ ] Pod에서 테스트 파일 생성
- [ ] Pod 삭제 후 재생성
- [ ] 테스트 파일 존재 확인

---

## 참고 자료

### OCI 문서
- [OCI File Storage Service 문서](https://docs.oracle.com/en-us/iaas/Content/File/Concepts/filestorageoverview.htm)
- [OCI CSI Driver for FSS](https://github.com/oracle/oci-cloud-controller-manager/blob/master/docs/volume-provisioner.md)

### Kubernetes 문서
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)

### Helm Charts
- [Grafana Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana)
- [Prometheus Operator Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Loki Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/loki)

---

## 버전 정보

- **문서 버전**: 1.0
- **작성일**: 2025-11-27
- **대상 환경**: OCI Container Engine for Kubernetes (OKE)
- **테스트 완료**: Grafana, Prometheus, Loki

---

## 변경 이력

| 날짜 | 버전 | 변경 내용 | 작성자 |
|------|------|-----------|--------|
| 2025-11-27 | 1.0 | 초기 문서 작성 | GitHub Copilot |

---

## 라이선스

이 문서는 MIT 라이선스 하에 배포됩니다.
