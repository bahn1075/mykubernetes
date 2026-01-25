# OKE Node Management & VCN-Native CNI Troubleshooting

OCI OKE 클러스터의 노드 관리 및 VCN-Native CNI 문제 해결 가이드입니다.

## 파일 구조

```
common/node/
├── README.md                   # 이 파일
├── node-refresh-cronjob.yaml   # CronJob 및 관련 리소스
├── cloud-init.md               # Cloud-init 설정 가이드
├── fix-crio-shortname.yaml     # CRI-O shortname 수정
└── backup/                     # ValidatingAdmissionPolicy 백업
    ├── vap-policy.yaml
    └── vap-binding.yaml
```

---

# VCN-Native CNI Troubleshooting

## 주요 에러 및 해결 방법

### Checkpoint File Not Found Error

```
Failed to load checkpoint: error reading checkpoint file:
open /var/lib/kubelet/device-plugins/kubelet_internal_checkpoint: no such file or directory
```

**원인**: CNI device plugin과 kubelet 간의 초기화 타이밍 문제

**해결 방법**: CNI Pod 재시작 (아래 절차 참조)

## CNI Pod 재시작 절차

OKE Native Pod Networking 2.3.0 이상에서는 보안 정책으로 CNI pod 삭제가 차단됩니다.
재시작하려면 다음 절차를 따르세요:

### 1. ValidatingAdmissionPolicy 백업
```bash
kubectl get validatingadmissionpolicy npn-pod-deletion-deny-policy -o yaml > backup/vap-policy.yaml
kubectl get validatingadmissionpolicybinding npn-pod-deletion-deny-policy-binding -o yaml > backup/vap-binding.yaml
```

### 2. 정책 삭제
```bash
kubectl delete validatingadmissionpolicy npn-pod-deletion-deny-policy
kubectl delete validatingadmissionpolicybinding npn-pod-deletion-deny-policy-binding
```

### 3. CNI Pod 삭제 (자동 재시작됨)
```bash
kubectl delete pods -n kube-system -l app=vcn-native-ip-cni
```

### 4. Pod 상태 확인
```bash
kubectl get pods -n kube-system -l app=vcn-native-ip-cni
```

### 5. 정책 복원
```bash
kubectl apply -f backup/vap-policy.yaml
kubectl apply -f backup/vap-binding.yaml
```

## 상태 확인 명령어

```bash
# CNI Pod 상태
kubectl get pods -n kube-system -l app=vcn-native-ip-cni

# CNI 로그 확인
kubectl logs -n kube-system -l app=vcn-native-ip-cni --all-containers --tail=50

# 에러만 확인
kubectl logs -n kube-system -l app=vcn-native-ip-cni --all-containers | grep -i error

# CNI 버전 확인
kubectl get daemonset -n kube-system vcn-native-ip-cni -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## 참고 문서

- [Oracle OKE Known Issues](https://docs.oracle.com/en-us/iaas/Content/ContEng/known-issues/conteng-known-issues.htm)
- [VCN-Native Pod Networking CNI Plugin](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpodnetworking_topic-OCI_CNI_plugin.htm)

---

# Node Refresh CronJob

OCI VCN Native IP CNI의 IP 풀 고갈 문제를 방지하기 위해 주기적으로 노드를 drain/uncordon하는 CronJob입니다.

## 배포 방법

```bash
kubectl apply -f /app/mykubernetes/common/node/node-refresh-cronjob.yaml
```

## 리소스 설명

| 리소스 | 이름 | 설명 |
|--------|------|------|
| ServiceAccount | node-refresh-sa | CronJob에서 사용할 서비스 계정 |
| ClusterRole | node-refresh-role | 노드 drain/uncordon 권한 |
| ClusterRoleBinding | node-refresh-rolebinding | 역할 바인딩 |
| ConfigMap | node-refresh-script | 노드 refresh 스크립트 |
| CronJob | node-refresh | 주간 스케줄 실행 |

## 스케줄

- **실행 시간**: 매주 일요일 오전 3:00 (KST)
- **Cron 표현식**: `0 18 * * 6` (UTC 기준 토요일 18:00 = KST 일요일 03:00)
- **타임존**: Asia/Seoul

## 동작 방식

각 노드에 대해 순차적으로:

1. 현재 Free IP 수 확인 (CNI 상태 체크)
2. 노드 Cordon (새 Pod 스케줄링 방지)
3. 노드 Drain (기존 Pod 안전하게 이동)
4. 30초 대기 (Pod 재스케줄링)
5. 노드 Uncordon (스케줄링 재개)
6. 노드 Ready 상태 대기
7. Free IP 수 재확인
8. 60초 대기 후 다음 노드 진행

## 수동 실행

스케줄을 기다리지 않고 즉시 실행:

```bash
# Job 수동 생성
kubectl create job --from=cronjob/node-refresh node-refresh-manual -n kube-system

# 실행 로그 확인
kubectl logs -n kube-system -l job-name=node-refresh-manual -f

# 수동 Job 삭제
kubectl delete job node-refresh-manual -n kube-system
```

## 상태 확인

```bash
# CronJob 상태
kubectl get cronjob node-refresh -n kube-system

# 최근 Job 목록
kubectl get jobs -n kube-system -l job-name=node-refresh

# Job 로그 확인
kubectl logs -n kube-system -l job-name=node-refresh --tail=100
```

## 주의사항

1. **서비스 중단**: drain 중 해당 노드의 Pod는 다른 노드로 이동됩니다
2. **시간 소요**: 노드당 약 2-3분, 전체 약 10분 소요
3. **DaemonSet**: DaemonSet Pod는 drain되지 않습니다
4. **PDB**: PodDisruptionBudget을 준수합니다

## 삭제

```bash
kubectl delete -f /app/mykubernetes/common/node/node-refresh-cronjob.yaml
```
