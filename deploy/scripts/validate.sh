#!/usr/bin/env sh
set -eu

IMAGE_REF="${2:-library/alpine}"
IMAGE_TAG="${3:-3.20}"
DEFAULT_PORT="${PROXY_HTTP_PORT:-5000}"
BASE_URL="${1:-http://127.0.0.1:${DEFAULT_PORT}}"
DOCKER_PULL_HOST="${DOCKER_PULL_HOST:-127.0.0.1:${DEFAULT_PORT}}"
tmp_headers="/tmp/docker-image-proxy-headers.$$"
trap 'rm -f "$tmp_headers"' EXIT

echo "== Compose 状态 =="
docker compose ps

echo "== 代理健康检查 =="
curl -fsS "${BASE_URL}/healthz"
curl -fsSI "${BASE_URL}/v2/" > "$tmp_headers"
sed -n '1,12p' "$tmp_headers"

echo "== 通过 mirror 获取上游 manifest =="
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  "${BASE_URL}/v2/${IMAGE_REF}/manifests/${IMAGE_TAG}" > "$tmp_headers"
sed -n '1,20p' "$tmp_headers"

echo "== 通过 mirror 执行 docker pull =="
docker pull "${DOCKER_PULL_HOST}/${IMAGE_REF}:${IMAGE_TAG}"

echo "== 缓存目录占用 =="
du -sh ./data/registry 2>/dev/null || true

echo "验证通过：${BASE_URL} 可以通过 mirror 提供 docker.io/${IMAGE_REF}:${IMAGE_TAG}。"
