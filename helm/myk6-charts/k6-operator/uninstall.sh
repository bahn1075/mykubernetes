#!/bin/bash

# K6 Operator 제거 스크립트

set -e

echo "=========================================="
echo "  K6 Operator 제거"
echo "=========================================="
echo ""

echo "🗑️  K6 Operator 제거 중..."
helm uninstall k6-operator -n k6-operator || echo "이미 제거되었거나 설치되지 않았습니다"

echo ""
read -p "네임스페이스도 삭제하시겠습니까? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  k6-operator 네임스페이스 삭제 중..."
    kubectl delete namespace k6-operator --ignore-not-found=true
    echo "✅ 네임스페이스 삭제 완료"
else
    echo "⏭️  네임스페이스 유지"
fi

echo ""
echo "=========================================="
echo "  제거 완료!"
echo "=========================================="
