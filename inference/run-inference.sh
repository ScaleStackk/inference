#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but was not found. Nothing was installed." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but its daemon is unavailable." >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "The Docker Compose plugin is required." >&2
  exit 1
fi
if [[ ! -f .env ]]; then
  cp .env.example .env
  chmod 0600 .env
  echo "Created $SCRIPT_DIR/.env. Review it, then run this script again." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

image="${INFERENCE_IMAGE:-questacase-inference:qwen3-4b}"
if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "Image $image is missing. Run ./build.sh inference first." >&2
  exit 1
fi

compose_files=(-f compose.inference.yaml)
if [[ "${INFERENCE_GPU_ENABLED:-false}" == "true" ]]; then
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "INFERENCE_GPU_ENABLED=true but nvidia-smi is unavailable on the host." >&2
    exit 1
  fi
  if ! nvidia-smi >/dev/null 2>&1; then
    echo "The NVIDIA GPU or driver is unavailable." >&2
    exit 1
  fi
  compose_files+=(-f compose.inference.gpu.yaml)
fi

docker compose --env-file .env "${compose_files[@]}" up --detach --no-build
docker compose --env-file .env "${compose_files[@]}" ps
echo "Inference API is listening on ${INFERENCE_BIND_ADDRESS:-0.0.0.0}:${INFERENCE_PORT:-11434}"
