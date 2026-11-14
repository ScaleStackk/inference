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
  echo "Created $SCRIPT_DIR/.env. Set INFERENCE_NODES, then run this script again." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${INFERENCE_NODES:?Set INFERENCE_NODES to comma-separated private-host:port entries}"
image="${LOAD_BALANCER_IMAGE:-questacase-inference-lb:3.4.7}"
network="${DOCKER_NETWORK:-questacase}"

if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "Image $image is missing. Run ./build.sh load-balancer first." >&2
  exit 1
fi
if ! docker network inspect "$network" >/dev/null 2>&1; then
  docker network create "$network" >/dev/null
fi

docker compose --env-file .env -f compose.load-balancer.yaml up --detach --no-build
docker compose --env-file .env -f compose.load-balancer.yaml ps
echo "Web API containers on $network can use http://inference:11434"
echo "Host-only endpoint: http://${LOAD_BALANCER_BIND_ADDRESS:-127.0.0.1}:${LOAD_BALANCER_PORT:-11435}"
