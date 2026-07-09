#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/data/docker-image-proxy}"

cd "$APP_DIR"

mkdir -p data/registry logs/nginx config/registry nginx/conf.d scripts

if [ ! -f .env ]; then
  cp .env.example .env
fi

if grep -q 'replace-with-64-hex-chars' .env; then
  secret="$(openssl rand -hex 32)"
  sed -i "s/replace-with-64-hex-chars/${secret}/" .env
fi

get_env_value() {
  key="$1"
  value="$(sed -n "s/^${key}=//p" .env | tail -n 1 | tr -d '\r')"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s' "$value"
}

dockerhub_user="$(get_env_value REGISTRY_PROXY_USERNAME)"
dockerhub_pass="$(get_env_value REGISTRY_PROXY_PASSWORD)"

if [ -z "$dockerhub_user" ] || [ "$dockerhub_user" = "replace-with-dockerhub-username" ]; then
  echo "错误：必须先在 .env 中填写 REGISTRY_PROXY_USERNAME，也就是 Docker Hub 用户名。" >&2
  echo "建议使用专用低权限 Docker Hub 账号，避免匿名拉取触发限流。" >&2
  exit 1
fi

if [ -z "$dockerhub_pass" ] || [ "$dockerhub_pass" = "replace-with-dockerhub-access-token" ]; then
  echo "错误：必须先在 .env 中填写 REGISTRY_PROXY_PASSWORD，也就是 Docker Hub Access Token。" >&2
  echo "请在 Docker Hub 创建 Access Token 后再部署，避免后续拉取镜像被限流。" >&2
  exit 1
fi

chmod 600 .env
chmod 644 docker-compose.yml .env.example README.md
chmod 644 config/registry/config.yml nginx/nginx.conf nginx/conf.d/*.conf
chmod 755 scripts scripts/install-or-update.sh scripts/validate.sh
chmod 755 data data/registry logs logs/nginx

docker compose pull
docker compose up -d
docker compose ps

chmod +x ./scripts/validate.sh
./scripts/validate.sh
