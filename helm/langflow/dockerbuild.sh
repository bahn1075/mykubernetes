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
# Recent Docker CLI releases dropped the "Username:" line from `docker info`,
# so inspect the CLI config / credential store instead.
DOCKER_CFG_FILE="${DOCKER_CONFIG:-${HOME}/.docker}/config.json"
HUB_REGISTRY="https://index.docker.io/v1/"

docker_logged_in() {
  [[ -f "${DOCKER_CFG_FILE}" ]] || return 1

  # Credentials kept in an external helper (osxkeychain, desktop, pass, ...)
  local store
  store=$(sed -n 's/.*"credsStore"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${DOCKER_CFG_FILE}")
  if [[ -n "${store}" ]] && command -v "docker-credential-${store}" >/dev/null 2>&1; then
    echo "${HUB_REGISTRY}" | "docker-credential-${store}" get >/dev/null 2>&1 && return 0
  fi

  # Credentials kept inline in config.json
  grep -q 'index\.docker\.io' "${DOCKER_CFG_FILE}"
}

if ! docker_logged_in; then
  echo "Error: docker is not logged in to Docker Hub. Run 'docker login' before building and pushing images." >&2
  exit 4
fi

# Detect a TLS-inspecting proxy and hand its CA chain to the build.
# pip inside the container trusts only certifi's bundle, so an intercepting
# corporate root CA makes every PyPI request fail certificate verification.
# Collect whatever CAs this network presents for PyPI and pass them as a
# BuildKit secret (build-time only -- see the Dockerfile comment).
# Override with CORP_CA_FILE=/path/to/ca.pem to supply your own bundle.
CA_SECRET_ARGS=()
CORP_CA_FILE="${CORP_CA_FILE:-}"

if [[ -z "${CORP_CA_FILE}" ]]; then
  PROXY_CA_FILE="$(mktemp -t pypi-chain-ca)"
  trap 'rm -f "${PROXY_CA_FILE}"' EXIT
  # -showcerts prints the full presented chain; drop cert #1 (the leaf) and
  # keep the signing CA(s). On an unproxied network these are public CAs and
  # appending them is a harmless no-op.
  if echo | openssl s_client -connect pypi.org:443 -servername pypi.org -showcerts 2>/dev/null \
      | awk '/-----BEGIN CERTIFICATE-----/{n++} n>1' > "${PROXY_CA_FILE}" \
      && [[ -s "${PROXY_CA_FILE}" ]]; then
    CORP_CA_FILE="${PROXY_CA_FILE}"
  else
    rm -f "${PROXY_CA_FILE}"
  fi
fi

if [[ -n "${CORP_CA_FILE}" && -s "${CORP_CA_FILE}" ]]; then
  CA_SUBJECT=$(openssl x509 -in "${CORP_CA_FILE}" -noout -subject 2>/dev/null || echo "unknown")
  echo "Passing PyPI CA chain to the build: ${CA_SUBJECT}"
  CA_SECRET_ARGS=(--secret "id=corp_ca,src=${CORP_CA_FILE}")
else
  echo "No extra PyPI CA chain detected; building with the image's default trust store."
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

echo "Building ${BACKEND_ARCH_TAG} and ${BACKEND_DATE_TAG}..."
docker build \
  --build-arg ARCH=${ARCH_TAG} \
  ${CA_SECRET_ARGS[@]+"${CA_SECRET_ARGS[@]}"} \
  --pull \
  -f Dockerfile \
  -t "${BACKEND_ARCH_TAG}" \
  -t "${BACKEND_DATE_TAG}" \
  . --progress=plain

echo "Pushing backend images..."
docker push "${BACKEND_ARCH_TAG}"
docker push "${BACKEND_DATE_TAG}"

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo "Backend tags pushed:"
echo "  - ${BACKEND_ARCH_TAG}"
echo "  - ${BACKEND_DATE_TAG}"
echo ""
echo "Next: set backend.image.tag to ${ARCH_TAG}-${DATE_TAG} in values.yaml and commit."
echo "========================================="
