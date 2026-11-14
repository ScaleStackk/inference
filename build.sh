#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

target="${1:-all}"
platform="${DOCKER_PLATFORM:-linux/amd64}"
inference_image="${INFERENCE_IMAGE:-questacase-inference:qwen3-4b}"
load_balancer_image="${LOAD_BALANCER_IMAGE:-questacase-inference-lb:3.4.7}"
ollama_version="${OLLAMA_VERSION:-0.40.15}"
ollama_model="${OLLAMA_MODEL:-qwen3:4b}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but was not found. Nothing was installed." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but its daemon is unavailable." >&2
  exit 1
fi

build_inference() {
  echo "Building $inference_image with $ollama_model for $platform"
  docker build \
    --platform "$platform" \
    --build-arg "OLLAMA_VERSION=$ollama_version" \
    --build-arg "OLLAMA_MODEL=$ollama_model" \
    --tag "$inference_image" \
    runtime
}

build_load_balancer() {
  echo "Building $load_balancer_image for $platform"
  docker build \
    --platform "$platform" \
    --tag "$load_balancer_image" \
    load_balancer
}

case "$target" in
  all)
    build_inference
    build_load_balancer
    ;;
  inference)
    build_inference
    ;;
  load-balancer)
    build_load_balancer
    ;;
  *)
    echo "Usage: $0 [all|inference|load-balancer]" >&2
    exit 2
    ;;
esac
