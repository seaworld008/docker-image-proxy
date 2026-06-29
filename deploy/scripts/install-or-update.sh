#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/data/docker-image-proxy}"
COMPOSE_FILES="-f docker-compose.yml"

if [ "${ENABLE_DOCKERHUB_AUTH:-0}" = "1" ]; then
  COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.with-auth.yml"
fi

cd "$APP_DIR"

mkdir -p data/registry logs/nginx config/registry nginx scripts

if [ ! -f .env ]; then
  cp .env.example .env
fi

if grep -q 'replace-with-64-hex-chars' .env; then
  secret="$(openssl rand -hex 32)"
  sed -i "s/replace-with-64-hex-chars/${secret}/" .env
fi

chmod 600 .env
chmod 644 docker-compose.yml docker-compose.with-auth.yml .env.example README.md .gitignore
chmod 644 config/registry/config.yml nginx/nginx.conf
chmod 755 scripts scripts/install-or-update.sh scripts/validate.sh
chmod 755 data data/registry logs logs/nginx

docker compose $COMPOSE_FILES pull
docker compose $COMPOSE_FILES up -d
docker compose ps

chmod +x ./scripts/validate.sh
./scripts/validate.sh
