# Node Refresh CronJob

OCI VCN Native IP CNI의 IP 풀 고갈 문제를 방지하기 위해 주기적으로 노드를 drain/uncordon하는 CronJob입니다.

## 파일 구조

```
common/node/
├── node-refresh-cronjob.yaml  # CronJob 및 관련 리소스
└── README.md                   # 이 파일
```

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
