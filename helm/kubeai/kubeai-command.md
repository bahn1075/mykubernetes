# KubeAI 적용을 위한 Command 모음

## GitHub 기본 가이드

```bash
helm repo add kubeai https://www.kubeai.org
helm repo update

helm upgrade --install kubeai kubeai/kubeai \
  --namespace kubeai \
  --create-namespace \
  -f kubeai/values.yaml
```

## KubeAI 설치 가이드

먼저 kubeai를 helm install 한다.
자세한 내용은 values.yaml을 참조 
rx9070을 custom으로 인식시켜 둔 상태 (209 ~ 218 라인)

### AMD GPU 이미지 설정
- vllm: 54라인의 amd-gpu: "rocm/vllm:latest" 이미지 지정
- ollama: 58라인의 amd-gpu: "ollama/ollama:rocm" 이미지 지정

### KubeAI Helm Install
```bash
helm dependency build kubeai
helm upgrade --install kubeai kubeai -n kubeai -f kubeai/values.yaml
```

### Model Install
이후 helm으로 model install 한다.
```bash
# kubeai 디렉토리에서 실행하는 경우
helm upgrade --install models ../models -n kubeai -f ../models/values.yaml

# 또는 kubeai/kubeai 디렉토리에서 실행하는 경우 (현재 위치)
helm upgrade --install models ../../models -n kubeai -f ../../models/values.yaml
```

> **참고**: values.yaml에서 `minReplicas: 1` 값을 지정하지 않으면 pod가 생성되지 않는다.

### Model 설정
```yaml
all:
  enabled: false
```
가 기본이며, 현재 GPU가 1개이므로 2개의 model을 동시에 활성화 할수는 없다.

### Model 활성화 조절
```bash
# model 활성화를 조절할 경우 helm upgrade를 수행 (경로 주의)
helm upgrade --install kubeai-models ../models --namespace kubeai --create-namespace

# 삭제
helm uninstall kubeai-models

# revision rollback (내용은 지정된 revision으로 돌아가지만 revision 숫자는 증가함)
helm rollback kubeai-models 7 -n kubeai
```

## Image Volumes 관리

### 리소스 삭제 예제
```bash
# Pod 삭제
kubectl delete -f qwen3-4b-pod.yaml
# pod "qwen3-4b-pod" deleted from kubeai namespace

# Service 삭제
kubectl delete -f qwen3-4b-service.yaml
# service "qwen3-4b-service" deleted from kubeai namespace

# PVC 삭제
kubectl delete -f qwen3-4b-pvc.yaml
# persistentvolumeclaim "qwen3-4b-pvc" deleted from kubeai namespace
```
