# ArgoCD Lightweight Installation Guide

OKE 클러스터에 ArgoCD를 설치하는 가이드입니다.

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                        ArgoCD                                │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Server    │  │ Repo-server │  │ Application-controller│ │
│  │   (UI/API)  │  │ (Git 클론)  │  │    (상태 동기화)      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│         │                │                    │              │
│         └────────────────┼────────────────────┘              │
│                          │                                   │
│                    ┌─────────────┐                          │
│                    │    Redis    │                          │
│                    │   (캐시)    │                          │
│                    └─────────────┘                          │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │   Kubernetes etcd       │
              │ (Application, AppProject│
              │   CRD로 상태 저장)       │
              └─────────────────────────┘
```

## 스토리지 정책

### PV/PVC가 필요 없는 이유

ArgoCD는 **상태를 Kubernetes CRD로 저장**하기 때문에 별도의 Persistent Volume이 필요하지 않습니다.

| 컴포넌트 | 저장 데이터 | 저장 위치 | 영속성 |
|----------|-------------|-----------|--------|
| Application-controller | Application 상태 | K8s etcd (CRD) | 영구 보존 |
| Server | AppProject, 설정 | K8s etcd (CRD, ConfigMap, Secret) | 영구 보존 |
| Repo-server | Git 레포지토리 캐시 | emptyDir (메모리) | 재시작 시 재클론 |
| Redis | 세션/캐시 데이터 | 메모리 | 재시작 시 재생성 |

### ArgoCD CRD 목록

```bash
# ArgoCD가 사용하는 CRD 확인
kubectl get crd | grep argoproj

# 출력 예시:
# applications.argoproj.io
# applicationsets.argoproj.io
# appprojects.argoproj.io
```

---

## 설치 과정

### Step 1: CRD 설치

```bash
kubectl apply -f /app/mykubernetes/helm/argocd/crds.yaml
```

### Step 2: ArgoCD 설치 및 업데이트

```bash
kubectl apply -f /app/mykubernetes/helm/argocd/install.yaml
```

### Step 3: 설치 확인

```bash
# Pod 상태 확인
kubectl get pods -n argocd

# 예상 출력:
# NAME                                  READY   STATUS    RESTARTS   AGE
# argocd-application-controller-0       1/1     Running   0          1m
# argocd-redis-xxxxxxxxxx-xxxxx         1/1     Running   0          1m
# argocd-repo-server-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
# argocd-server-xxxxxxxxxx-xxxxx        1/1     Running   0          1m
```

### Step 4: 초기 비밀번호 확인

```bash
# admin 비밀번호 확인
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### Step 5: 접속

- **URL**: https://argocd.64bit.kr (Ingress 설정 기준)
- **Username**: admin
- **Password**: Step 4에서 확인한 비밀번호

---

## 파일 구성

| 파일 | 설명 |
|------|------|
| `crds.yaml` | ArgoCD Custom Resource Definitions |
| `install.yaml` | ArgoCD 컴포넌트 (Namespace, Deployment, Service, RBAC 등) |

---

## Lightweight 설치 특징

이 설치는 다음 컴포넌트를 **제외**한 경량 버전입니다:

- ❌ Dex (SSO)
- ❌ ApplicationSet Controller
- ❌ Notifications Controller
- ❌ NetworkPolicies

포함된 핵심 컴포넌트:
- ✅ argocd-server (UI/API)
- ✅ argocd-repo-server (Git 연동)
- ✅ argocd-application-controller (동기화)
- ✅ argocd-redis (캐시)

---

## 삭제

```bash
kubectl delete -f /app/mykubernetes/helm/argocd/install.yaml
kubectl delete -f /app/mykubernetes/helm/argocd/crds.yaml
```

---

## 참고

- ArgoCD 공식 문서: https://argo-cd.readthedocs.io/
- 버전: v2.12.3
