#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"

mode=${1:-}
sha=$(git rev-parse HEAD)

build_and_push() {
  image=$1
  docker build -f docker/Dockerfile -t "${image}:latest" -t "${image}:${sha}" "$root"
  docker push "${image}:latest"
  docker push "${image}:${sha}"
  printf '%s\n' "${image}:${sha}"
}

case "$mode" in
  local)
    build_and_push "localhost:5000/leaf-agent"
    ;;
  remote)
    if [[ -z "${LEAF_REGISTRY:-}" ]]; then
      echo "LEAF_REGISTRY is required" >&2
      exit 1
    fi
    if [[ -z "${LEAF_REGISTRY_USER:-}" || -z "${LEAF_REGISTRY_PASSWORD:-}" ]]; then
      echo "LEAF_REGISTRY_USER and LEAF_REGISTRY_PASSWORD are required" >&2
      exit 1
    fi
    printf '%s' "$LEAF_REGISTRY_PASSWORD" | docker login "$LEAF_REGISTRY" --username "$LEAF_REGISTRY_USER" --password-stdin
    build_and_push "${LEAF_REGISTRY%/}/leaf-agent"
    ;;
  *)
    echo "usage: bash custom/bin/publish-image.sh local|remote" >&2
    exit 1
    ;;
esac
