# AIRecipe Kubernetes Deployment

이 디렉토리는 airecipe 애플리케이션을 Kubernetes에 배포하기 위한 매니페스트 파일을 포함합니다.

## 디렉토리 구조

```
ai-recipe/
├── base/                      # 공통 기본 리소스
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── ecr-secret.yaml
│   └── kustomization.yaml
├── overlays/                  # 환경별 오버레이
│   ├── dev/                   # 개발 환경
│   │   └── kustomization.yaml
│   └── prd/                   # 운영 환경
│       └── kustomization.yaml
└── README.md
```

## 배포 방법 (Kustomize 사용)

### Dev 환경 배포
```bash
kubectl apply -k overlays/dev
```

### Prd 환경 배포
```bash
kubectl apply -k overlays/prd
```

### 배포 내용 미리보기 (dry-run)
```bash
# Dev 환경
kubectl kustomize overlays/dev

# Prd 환경
kubectl kustomize overlays/prd
```

### 배포 삭제
```bash
# Dev 환경
kubectl delete -k overlays/dev

# Prd 환경
kubectl delete -k overlays/prd
```

## 레거시 배포 방법 (수동)

루트 디렉토리의 yaml 파일들을 직접 사용하는 방법:

### 한 번에 모두 배포
```bash
kubectl apply -f namespace.yaml -f configmap.yaml -f deployment.yaml -f service.yaml -f ingress.yaml
```

## Minikube Tunnel 실행

서비스에 접근하기 위해 별도 터미널에서 minikube tunnel을 실행합니다:

```bash
minikube tunnel
```

## 서비스 확인

### Pod 상태 확인
```bash
kubectl get pods -n airecipe
```

### Service 상태 확인
```bash
kubectl get svc -n airecipe
```

### 외부 IP 확인 (EXTERNAL-IP가 할당될 때까지 대기)
```bash
kubectl get svc airecipe-service -n airecipe --watch
```

### 로그 확인
```bash
kubectl logs -n airecipe -l app=airecipe -f
```

## 애플리케이션 접근

minikube tunnel이 실행 중일 때:

```bash
# Service의 EXTERNAL-IP 확인
EXTERNAL_IP=$(kubectl get svc airecipe-service -n airecipe -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 애플리케이션 접근
curl http://${EXTERNAL_IP}:8000
```

또는 브라우저에서:
```
http://<EXTERNAL-IP>:8000
```

## 리소스 삭제

```bash
kubectl delete -f .
```

또는 네임스페이스 삭제 (모든 리소스가 함께 삭제됨):
```bash
kubectl delete namespace airecipe
```

## 트러블슈팅

### Pod가 ImagePullBackOff 상태인 경우
이미지가 minikube에 로드되었는지 확인:
```bash
minikube image ls | grep airecipe
```

이미지가 없다면 로드:
```bash
# Docker 이미지를 minikube에 로드
minikube image load airecipe:latest
```

### Service EXTERNAL-IP가 pending인 경우
minikube tunnel이 실행 중인지 확인:
```bash
minikube tunnel
```

### Pod가 시작되지 않는 경우
로그 확인:
```bash
kubectl describe pod -n airecipe -l app=airecipe
kubectl logs -n airecipe -l app=airecipe
```

## 설정 정보

- **Namespace**: airecipe
- **Image**: docker.io/library/airecipe:latest
- **Service Port**: 8000
- **Service Type**: LoadBalancer
- **ConfigMap**:
  - OPENAI_API_KEY: c3VwZXItc2VjcmV0LWtleQ==
  - OPENAI_PROXY_HOST: https://tdc-aws-dev.lgthinq.com
  - OPENAI_API_PATH: /hlp/v1/test/proxy/chat
