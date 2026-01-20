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

OKE FSS에 headlamp 디렉토리를 미리 생성해야 합니다:

```bash
# FSS가 마운트된 노드 또는 Pod에서 실행
mkdir -p /oke-fss/headlamp/plugins
chmod 755 /oke-fss/headlamp
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

### 토큰 획득 방법

```bash
# headlamp 서비스 계정의 토큰 생성
kubectl create token headlamp -n monitoring

# 또는 장기 토큰 생성
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

# 토큰 확인
kubectl get secret headlamp-token -n monitoring -o jsonpath='{.data.token}' | base64 -d
```

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
