# Secret 관리 가이드

ECR Secret은 보안상의 이유로 Git에 커밋하지 않습니다.

## ECR Secret 생성 방법

### 방법 1: kubectl 명령어 사용 (권장)

```bash
# Dev 환경
kubectl create secret docker-registry ecr-secret \
  --docker-server=567925872059.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
  -n dev-airecipe

# Prd 환경
kubectl create secret docker-registry ecr-secret \
  --docker-server=567925872059.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
  -n prd-airecipe
```

### 방법 2: ecr-secret.yaml 템플릿 사용

1. `ecr-secret.yaml` 파일을 복사하여 `ecr-secret.local.yaml` 생성
2. 실제 자격 증명으로 플레이스홀더 교체
3. 적용: `kubectl apply -f ecr-secret.local.yaml`
4. **중요**: `*.local.yaml` 파일은 `.gitignore`에 추가되어 있습니다

### 방법 3: External Secrets Operator 사용

AWS Secrets Manager나 Parameter Store와 연동하여 자동으로 Secret을 생성할 수 있습니다.

## 참고사항

- ECR 토큰은 12시간마다 갱신이 필요합니다
- 프로덕션 환경에서는 External Secrets Operator 사용을 권장합니다
- Secret은 각 네임스페이스마다 별도로 생성해야 합니다
