# OCI Instance Principal 설정 가이드

Instance Principal을 사용하면 Private Key 없이 OKE 클러스터에서 OCI Vault에 안전하게 접근할 수 있습니다.

## 1. Dynamic Group 생성

OCI Console → Identity & Security → Dynamic Groups → Create Dynamic Group

**Name:** `oke-ai-recipe-dynamic-group`

**Matching Rules:**
```
ALL {instance.compartment.id = 'ocid1.compartment.oc1..your-compartment-id'}
```

또는 특정 클러스터의 노드만 포함하려면:
```
ALL {resource.type = 'cluster', resource.compartment.id = 'ocid1.compartment.oc1..your-compartment-id'}
```

## 2. Policy 생성

OCI Console → Identity & Security → Policies → Create Policy

**Name:** `oke-vault-access-policy`

**Compartment:** root 또는 해당 compartment

**Policy Statements:**
```
Allow dynamic-group oke-ai-recipe-dynamic-group to read secret-family in compartment <compartment-name>
Allow dynamic-group oke-ai-recipe-dynamic-group to use vaults in compartment <compartment-name>
```

## 3. Compartment OCID 확인

터미널에서 확인:
```bash
kubectl get nodes -o wide
# 노드가 실행 중인 compartment 확인
```

또는 OCI Console에서:
- Compute → Instances → 워커 노드 선택 → Compartment OCID 복사

## 4. 배포

설정 완료 후:
```bash
kubectl apply -k /app/mykubernetes/kustomize/ai-recipe/base
```

## 5. 확인

```bash
# ExternalSecret 상태 확인
kubectl get externalsecret -n ai-recipe

# 생성된 Secret 확인
kubectl get secret airecipe-openai-secret -n ai-recipe

# ExternalSecret 상세 로그
kubectl describe externalsecret airecipe-openai -n ai-recipe
```

## 장점

✅ Private Key 불필요 (Git에 민감 정보 저장 안함)
✅ OCI에서 권장하는 방식
✅ 자동으로 인증 관리
✅ 보안성 향상

## 문제 해결

만약 권한 오류가 발생하면:
1. Dynamic Group의 Matching Rule 확인
2. Policy가 올바른 Compartment에 적용되었는지 확인
3. External Secrets Pod 로그 확인:
   ```bash
   kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
   ```
