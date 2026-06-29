#!/usr/bin/env sh
set -eu

IMAGE_REF="${2:-library/alpine}"
IMAGE_TAG="${3:-3.20}"
DEFAULT_PORT="${PROXY_HTTP_PORT:-5000}"
BASE_URL="${1:-http://127.0.0.1:${DEFAULT_PORT}}"
DOCKER_PULL_HOST="${DOCKER_PULL_HOST:-127.0.0.1:${DEFAULT_PORT}}"
tmp_headers="/tmp/docker-image-proxy-headers.$$"
trap 'rm -f "$tmp_headers"' EXIT

echo "== compose status =="
docker compose ps

echo "== proxy health =="
curl -fsS "${BASE_URL}/healthz"
curl -fsSI "${BASE_URL}/v2/" > "$tmp_headers"
sed -n '1,12p' "$tmp_headers"

echo "== upstream manifest through mirror =="
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  "${BASE_URL}/v2/${IMAGE_REF}/manifests/${IMAGE_TAG}" > "$tmp_headers"
sed -n '1,20p' "$tmp_headers"

echo "== docker pull through mirror =="
docker pull "${DOCKER_PULL_HOST}/${IMAGE_REF}:${IMAGE_TAG}"

echo "== cache footprint =="
du -sh ./data/registry 2>/dev/null || true

echo "Validation OK: ${BASE_URL} can serve docker.io/${IMAGE_REF}:${IMAGE_TAG} through the mirror."
