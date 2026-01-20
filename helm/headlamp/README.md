# Headlamp Kubernetes Dashboard Helm Deployment

Headlamp은 Kubernetes 클러스터를 위한 사용하기 쉬운 웹 기반 대시보드입니다.

## 파일 구조

```
helm/headlamp/
├── application.yaml   # ArgoCD Application 매니페스트
├── headlamp-pv.yaml   # PersistentVolume (OKE FSS)
├── headlamp-pvc.yaml  # PersistentVolumeClaim
├── values.yaml        # Helm values 설정
└── README.md          # 이 파일
```

## 사전 준비

### 1. PV/PVC 생성 (플러그인 저장용)

```bash
# PV 생성
kubectl apply -f /app/mykubernetes/helm/headlamp/headlamp-pv.yaml

# PVC 생성
kubectl apply -f /app/mykubernetes/helm/headlamp/headlamp-pvc.yaml

# 확인
kubectl get pv headlamp-pv
kubectl get pvc headlamp-pvc -n monitoring
```

### 2. FSS 서브디렉토리 생성

OKE FSS에 headlamp 디렉토리를 미리 생성해야 합니다.
`fss-debug-pod`를 사용하여 디렉토리를 생성합니다:

```bash
# 디렉토리 생성
kubectl exec fss-debug-pod -n default -- mkdir -p /mnt/headlamp/plugins /mnt/headlamp/config

# 권한 설정 (headlamp user: uid=100, gid=101)
kubectl exec fss-debug-pod -n default -- chmod -R 755 /mnt/headlamp
kubectl exec fss-debug-pod -n default -- chown -R 100:101 /mnt/headlamp

# 확인
kubectl exec fss-debug-pod -n default -- ls -la /mnt/headlamp
```

## 배포 방법

### 방법 1: ArgoCD를 통한 배포 (권장)

```bash
# ArgoCD Application 등록
kubectl apply -f /app/mykubernetes/helm/headlamp/application.yaml

# 상태 확인
kubectl get application headlamp -n argocd

# 상세 상태 확인
argocd app get headlamp
```

> **참고**: `kubectl apply` 시 네임스페이스를 별도로 지정하지 않아도 됩니다.
> `application.yaml` 파일 내에 `namespace: argocd`가 이미 지정되어 있습니다.
>
> - **ArgoCD Application 리소스**: `argocd` 네임스페이스에 생성
> - **실제 Headlamp 워크로드**: `monitoring` 네임스페이스에 배포

### 방법 2: Helm CLI 직접 배포

```bash
# Helm repo 추가
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update

# 설치
helm upgrade --install headlamp headlamp/headlamp \
  --namespace monitoring \
  --create-namespace \
  -f /app/mykubernetes/helm/headlamp/values.yaml

# 삭제
helm uninstall headlamp -n monitoring
```

## 접속 정보

- **URL**: http://headlamp.64bit.kr
- **인증**: ServiceAccount 토큰 사용

### 토큰 생성 방법

```bash
# 1년 유효기간의 토큰 생성
kubectl create token headlamp -n monitoring --duration=8760h
```

생성된 토큰을 Headlamp 로그인 화면의 "ID 토큰" 입력란에 붙여넣으면 됩니다.

### 기존 토큰 확인 방법

`kubectl create token` 명령으로 생성한 토큰은 클러스터에 저장되지 않고 즉시 반환됩니다.
토큰을 영구 저장하려면 Secret을 생성해야 합니다:

```bash
# Secret 기반 영구 토큰 생성
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: headlamp-token
  namespace: monitoring
  annotations:
    kubernetes.io/service-account.name: headlamp
type: kubernetes.io/service-account-token
EOF

# 저장된 토큰 확인
kubectl get secret headlamp-token -n monitoring -o jsonpath='{.data.token}' | base64 -d && echo
```

> **참고**: 브라우저 로컬 스토리지에 토큰이 저장되므로, 동일 브라우저에서는 재로그인이 필요 없습니다.

## ArgoCD Application 설명

`application.yaml`은 Multiple Sources 방식을 사용합니다:

- **Helm Chart**: `headlamp` repo에서 직접 차트 참조
- **Values**: Git repo의 `helm/headlamp/values.yaml` 참조

이 방식의 장점:
- 차트 파일들을 Git에 저장할 필요 없음
- values.yaml만 관리하면 됨
- 차트 버전 업그레이드가 간편함 (targetRevision만 변경)

## 차트 버전 업그레이드

`application.yaml`에서 `targetRevision` 값을 변경:

```yaml
sources:
  - repoURL: https://kubernetes-sigs.github.io/headlamp/
    chart: headlamp
    targetRevision: 0.39.0  # 원하는 버전으로 변경
```

최신 버전 확인:
```bash
helm search repo headlamp/headlamp --versions | head -10
```

## 주요 기능

- Kubernetes 리소스 조회/편집/삭제
- 실시간 로그 조회
- Pod 셸 접속
- Helm 릴리스 관리 (enableHelm: true)
- 플러그인 확장 지원

## 트러블슈팅

### Sync 상태 확인
```bash
kubectl get application headlamp -n argocd -o jsonpath='{.status.sync.status}'
```

### Pod 상태 확인
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=headlamp
kubectl logs -n monitoring -l app.kubernetes.io/name=headlamp
```

### Ingress 확인
```bash
kubectl get ingress -n monitoring
```

## 배포 시 발생했던 문제와 해결 방법

### 문제 1: CrashLoopBackOff - 읽기 전용 파일시스템

**증상**: Pod가 `CrashLoopBackOff` 상태로 시작 실패

**원인**: `securityContext.readOnlyRootFilesystem: true` 설정으로 인해 Headlamp가 `/tmp`, `/home/headlamp/.config` 등에 쓰기 불가

**로그**:
```
mkdir /home/headlamp/.config: read-only file system
Failed to create static dir
```

**해결**: values.yaml에서 `readOnlyRootFilesystem: false`로 변경

```yaml
securityContext:
  readOnlyRootFilesystem: false  # headlamp needs to write to /tmp and /home
```

### 문제 2: ContainerCreating 상태에서 멈춤 - 볼륨 마운트 실패

**증상**: Pod가 `ContainerCreating` 상태에서 수 분간 멈춤

**원인**: 동일한 PVC를 두 개의 다른 볼륨 이름으로 마운트하면 OCI FSS CSI 드라이버에서 문제 발생

**잘못된 설정**:
```yaml
volumes:
  - name: headlamp-storage      # 볼륨 1
    persistentVolumeClaim:
      claimName: headlamp-pvc
  - name: headlamp-config       # 볼륨 2 (같은 PVC, 다른 이름)
    persistentVolumeClaim:
      claimName: headlamp-pvc
```

**해결**: 동일 PVC는 하나의 볼륨으로만 정의하고, volumeMounts에서 subPath로 분리

```yaml
volumeMounts:
  - name: headlamp-storage
    mountPath: /headlamp/plugins
    subPath: headlamp/plugins
  - name: headlamp-storage      # 같은 볼륨 이름 사용
    mountPath: /home/headlamp/.config
    subPath: headlamp/config

volumes:
  - name: headlamp-storage      # 볼륨 하나만 정의
    persistentVolumeClaim:
      claimName: headlamp-pvc
```

### 문제 3: FSS 서브디렉토리 미존재

**증상**: subPath 마운트 시 디렉토리가 없어서 마운트 실패

**해결**: fss-debug-pod를 사용하여 FSS에 미리 디렉토리 생성

```bash
kubectl exec fss-debug-pod -n default -- mkdir -p /mnt/headlamp/plugins /mnt/headlamp/config
kubectl exec fss-debug-pod -n default -- chown -R 100:101 /mnt/headlamp
```
