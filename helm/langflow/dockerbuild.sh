#!/usr/bin/env bash
set -euo pipefail

# dockerbuild.sh
# Build script for Langflow backend image
# Supports multi-architecture builds (amd64/aarch64)
# Always pulls latest base images before building

# Image names
BACKEND_IMAGE="bahn1075/langflow-custom"

# Detect architecture
UNAME_M=$(uname -m)
case "${UNAME_M}" in
  x86_64|amd64)
    ARCH_TAG="amd64"
    ;;
  aarch64|arm64)
    ARCH_TAG="aarch64"
    ;;
  *)
    echo "Unsupported architecture detected: ${UNAME_M}" >&2
    exit 1
    ;;
esac

echo "========================================="
echo "Detected host architecture: ${UNAME_M}"
echo "Using architecture tag: ${ARCH_TAG}"
echo "========================================="

# Check docker is available
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed or not in PATH." >&2
  exit 3
fi

# Require Docker Hub login before building images that will be pushed.
if ! docker info 2>/dev/null | grep -q "Username:"; then
  echo "Error: docker is not logged in. Run 'docker login' before building and pushing images." >&2
  exit 4
fi

# Generate date tag (yyyymmdd-hhmm format)
DATE_TAG=$(date +%Y%m%d-%H%M)

# Simple cache prune
echo "Pruning Docker builder and image caches..."
docker builder prune --all --force || true

echo ""
echo "========================================="
echo "Building Backend Image"
echo "========================================="

BACKEND_ARCH_TAG="${BACKEND_IMAGE}:${ARCH_TAG}"
BACKEND_DATE_TAG="${BACKEND_IMAGE}:${ARCH_TAG}-${DATE_TAG}"
BACKEND_LATEST_TAG="${BACKEND_IMAGE}:latest"

echo "Building ${BACKEND_ARCH_TAG}, ${BACKEND_DATE_TAG}, and ${BACKEND_LATEST_TAG}..."
docker build \
  --build-arg ARCH=${ARCH_TAG} \
  --pull \
  -f Dockerfile \
  -t "${BACKEND_ARCH_TAG}" \
  -t "${BACKEND_DATE_TAG}" \
  -t "${BACKEND_LATEST_TAG}" \
  . --progress=plain

echo "Pushing backend images..."
docker push "${BACKEND_ARCH_TAG}"
docker push "${BACKEND_DATE_TAG}"
docker push "${BACKEND_LATEST_TAG}"

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo "Backend tags pushed:"
echo "  - ${BACKEND_ARCH_TAG}"
echo "  - ${BACKEND_DATE_TAG}"
echo "  - ${BACKEND_LATEST_TAG}"
echo "========================================="
