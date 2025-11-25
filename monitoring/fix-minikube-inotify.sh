#!/bin/bash

# Minikube 노드 inotify 설정 스크립트
# "too many open files" 에러 해결을 위한 inotify 제한 증가

set -e

echo "=========================================="
echo "Minikube 노드 inotify 설정 스크립트"
echo "=========================================="
echo ""

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# minikube 실행 확인
if ! command -v minikube &> /dev/null; then
    echo -e "${RED}Error: minikube 명령을 찾을 수 없습니다.${NC}"
    exit 1
fi

# minikube 상태 확인
if ! minikube status &> /dev/null; then
    echo -e "${RED}Error: minikube가 실행 중이 아닙니다.${NC}"
    exit 1
fi

echo -e "${YELLOW}모든 minikube 노드 목록:${NC}"
minikube node list
echo ""

# 모든 노드 이름 가져오기
NODES=$(minikube node list | awk '{print $1}')

echo -e "${YELLOW}각 노드의 현재 inotify 설정:${NC}"
echo ""

for node in $NODES; do
    echo "=== $node ==="
    echo -n "  max_user_instances: "
    minikube ssh -n $node -- cat /proc/sys/fs/inotify/max_user_instances
    echo -n "  max_user_watches: "
    minikube ssh -n $node -- cat /proc/sys/fs/inotify/max_user_watches
    echo ""
done

echo ""
read -p "inotify 설정을 변경하시겠습니까? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
echo -e "${GREEN}inotify 설정 변경 중...${NC}"
echo ""

# 설정 값
MAX_USER_INSTANCES=1024
MAX_USER_WATCHES=524288

for node in $NODES; do
    echo "=== $node 설정 중 ==="
    
    # inotify 설정 변경
    minikube ssh -n $node -- "sudo sysctl -w fs.inotify.max_user_instances=$MAX_USER_INSTANCES" > /dev/null
    minikube ssh -n $node -- "sudo sysctl -w fs.inotify.max_user_watches=$MAX_USER_WATCHES" > /dev/null
    
    echo -e "  ${GREEN}✓${NC} max_user_instances: $MAX_USER_INSTANCES"
    echo -e "  ${GREEN}✓${NC} max_user_watches: $MAX_USER_WATCHES"
    echo ""
done

echo ""
echo -e "${GREEN}=========================================="
echo "설정이 완료되었습니다!"
echo "==========================================${NC}"
echo ""
echo -e "${YELLOW}참고:${NC}"
echo "- 이 설정은 minikube 재시작 시 초기화됩니다."
echo "- minikube를 재시작한 후에는 이 스크립트를 다시 실행하세요."
echo ""
echo -e "${YELLOW}영구 적용 방법 (호스트 시스템):${NC}"
echo "호스트 시스템에서 다음 설정을 추가하면 영구 적용됩니다:"
echo ""
echo "  sudo tee /etc/sysctl.d/minikube.conf <<EOF"
echo "  fs.inotify.max_user_watches = 524288"
echo "  fs.inotify.max_user_instances = 1024"
echo "  EOF"
echo ""
echo "  sudo sysctl --system"
echo ""
echo "참고: https://00formicapunk00.wordpress.com/2024/12/10/too-many-open-files-in-minikube-pod/"
echo ""

# 검증
echo -e "${YELLOW}변경된 설정 확인:${NC}"
echo ""

for node in $NODES; do
    echo "=== $node ==="
    instances=$(minikube ssh -n $node -- cat /proc/sys/fs/inotify/max_user_instances)
    watches=$(minikube ssh -n $node -- cat /proc/sys/fs/inotify/max_user_watches)
    
    if [ "$instances" -eq "$MAX_USER_INSTANCES" ] && [ "$watches" -eq "$MAX_USER_WATCHES" ]; then
        echo -e "  ${GREEN}✓ 설정 적용 확인됨${NC}"
    else
        echo -e "  ${RED}✗ 설정 적용 실패${NC}"
    fi
    echo ""
done

echo ""
echo -e "${GREEN}완료!${NC}"
