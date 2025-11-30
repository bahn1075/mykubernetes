# Jenkins Kustomize Configuration

Minimal Jenkins deployment using Kustomize for Kubernetes.

## Structure

```
jenkins/
├── base/                       # Base configuration
│   ├── namespace.yaml         # jenkins namespace
│   ├── serviceaccount.yaml    # Jenkins admin service account with cluster permissions
│   ├── pvc.yaml               # PersistentVolumeClaim (5Gi, no storageClass)
│   ├── deployment.yaml        # Jenkins deployment (1 replica)
│   ├── service.yaml           # ClusterIP service
│   └── kustomization.yaml
└── overlays/
    ├── oci/                   # OCI-specific configuration
    │   ├── ingress.yaml       # Ingress for jenkins.64bit.kr
    │   ├── deployment-patch.yaml  # ARM64 node selector
    │   ├── pvc-patch.yaml     # OCI FSS storageClass
    │   └── kustomization.yaml
    └── minikube/              # Minikube configuration (placeholder)
```

## Features

### Base Configuration
- **Namespace**: `jenkins`
- **Service Account**: Full cluster admin permissions (for dynamic agent provisioning)
- **Storage**: 5Gi PVC (storageClass configured in overlays)
- **Image**: `jenkins/jenkins:lts`
- **Resources**:
  - Requests: 500Mi memory, 500m CPU
  - Limits: 2Gi memory, 1000m CPU
- **Ports**: 8080 (HTTP), 50000 (JNLP)
- **Health Checks**: Liveness and Readiness probes configured

### OCI Overlay
- **Architecture**: ARM64 (aarch64) node selector
- **Image**: `jenkins/jenkins:lts-jdk17`
- **Ingress**: HTTP-only ingress at `http://jenkins.64bit.kr`
- **Storage**: Uses OCI FSS (File Storage Service) provisioner

## Deployment

### Deploy to OCI

```bash
# Preview the generated manifests
kubectl kustomize overlays/oci

# Apply the configuration
kubectl apply -k overlays/oci

# Check deployment status
kubectl get all -n jenkins
kubectl get pvc -n jenkins
kubectl get ingress -n jenkins
```

### Get Initial Admin Password

```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=jenkins-server -n jenkins --timeout=300s

# Get the initial admin password
kubectl exec -n jenkins deployment/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword
```

### Access Jenkins

- **URL**: http://jenkins.64bit.kr
- **Initial Setup**: Use the admin password from above

## Cleanup

```bash
kubectl delete -k overlays/oci
```

## Notes

- The configuration is minimal for production use
- For production, consider:
  - Enabling HTTPS/TLS on ingress
  - Adding resource quotas and limits
  - Configuring backup strategies for PVC
  - Setting up Jenkins Configuration as Code (JCasC)
  - Implementing GitOps with the Kubernetes plugin
- The minikube overlay is a placeholder for future local development configuration
