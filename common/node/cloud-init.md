# 근본적인 해결책
## 방법 1: OCI Node Pool의 Cloud-Init 설정 (가장 확실)
새 노드가 생성될 때부터 설정을 적용:
bash# cloud-init 스크립트 작성
```
cat <<'EOF' > node-init-cloud-config.yaml
#cloud-config
write_files:
  - path: /etc/containers/registries.conf
    permissions: '0644'
    content: |
      short-name-mode = "disabled"
      unqualified-search-registries = ["docker.io"]
      
      [[registry]]
      prefix = "docker.io"
      location = "docker.io"
      
      [[registry]]
      prefix = "quay.io"
      location = "quay.io"
      
      [[registry]]
      prefix = "gcr.io"
      location = "gcr.io"

runcmd:
  - systemctl restart crio
EOF
# base64 인코딩
cat node-init-cloud-config.yaml | base64 -w 0 > node-init-base64.txt
```
# OCI Console에서 적용:

1. OKE 클러스터 → Node Pools → 해당 Node Pool 선택
2. Edit 클릭
3. Show Advanced Options → Cloud Init Script
4. 위 cloud-config 내용 붙여넣기
5. Save Changes

OCI CLI로 적용:
```
# Node Pool OCID 확인
oci ce node-pool list \
  --compartment-id <your-compartment-ocid> \
  --cluster-id <your-cluster-ocid>

# Node Pool 업데이트
oci ce node-pool update \
  --node-pool-id <node-pool-ocid> \
  --node-metadata "{\"user_data\": \"$(cat node-init-cloud-config.yaml | base64 -w 0)\"}"
```

## 방법 2: DaemonSet 개선 (자가 치유)
주기적으로 설정을 검사하고 수정하도록 변경:
```
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fix-crio-shortname
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: fix-crio-shortname
  template:
    metadata:
      labels:
        app: fix-crio-shortname
    spec:
      hostPID: true
      hostNetwork: true
      containers:
      - name: monitor-and-fix
        image: docker.io/busybox:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "Starting configuration monitor..."
          
          while true; do
            # 현재 설정 확인
            CURRENT_MODE=$(grep 'short-name-mode' /host/etc/containers/registries.conf | cut -d'"' -f2)
            
            if [ "$CURRENT_MODE" != "disabled" ]; then
              echo "[$(date)] Detected incorrect short-name-mode: $CURRENT_MODE"
              echo "[$(date)] Fixing configuration..."
              
              # 백업
              cp /host/etc/containers/registries.conf /host/etc/containers/registries.conf.bak || true
              
              # 수정
              sed -i 's/short-name-mode = ".*"/short-name-mode = "disabled"/' /host/etc/containers/registries.conf
              
              # unqualified-search-registries 추가
              if ! grep -q 'unqualified-search-registries' /host/etc/containers/registries.conf; then
                echo 'unqualified-search-registries = ["docker.io"]' >> /host/etc/containers/registries.conf
              fi
              
              # CRI-O 재시작
              echo "[$(date)] Restarting CRI-O..."
              nsenter --target 1 --mount --uts --ipc --net --pid -- systemctl restart crio
              
              echo "[$(date)] Configuration fixed!"
            else
              echo "[$(date)] Configuration OK (short-name-mode: disabled)"
            fi
            
            # 5분마다 체크
            sleep 300
          done
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-etc
          mountPath: /host/etc
        resources:
          limits:
            cpu: 50m
            memory: 64Mi
          requests:
            cpu: 10m
            memory: 32Mi
      volumes:
      - name: host-etc
        hostPath:
          path: /etc
      tolerations:
      - effect: NoSchedule
        operator: Exists
```        