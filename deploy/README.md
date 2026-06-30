# Docker Image Proxy Deploy Package

This directory is designed to be copied as-is to `/data/docker-image-proxy/`.

Pinned image versions:

- `registry:3.1.1@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33`
- `nginx:1.30.3-alpine@sha256:0d3b80406a13a767339fbe2f41406d6c7da727ab89cf8fae399e81f780f814d1`

Quick start on the server:

```bash
mkdir -p /data/docker-image-proxy
cd /data/docker-image-proxy
cp .env.example .env
sed -i "s/replace-with-64-hex-chars/$(openssl rand -hex 32)/" .env
docker compose pull
docker compose up -d
chmod +x ./scripts/validate.sh
./scripts/validate.sh
```

By default the proxy listens on `127.0.0.1:5000` to avoid exposing an
unauthenticated mirror on the public internet. Put the host gateway/CDN in front
of it, or change `PROXY_BIND_ADDR` only after access control is in place.

Or run the bundled installer from `/data/docker-image-proxy/`:

```bash
chmod +x ./scripts/install-or-update.sh
./scripts/install-or-update.sh
```

To enable Docker Hub authenticated upstream pulls, set `REGISTRY_PROXY_USERNAME`
and `REGISTRY_PROXY_PASSWORD` in `.env`, then start with:

```bash
docker compose -f docker-compose.yml -f docker-compose.with-auth.yml up -d
```

For public or cross-site use, put HTTPS/CDN in front of the source server and
restrict source access by CDN IP allowlist or origin authentication. Direct HTTP
is only suitable for controlled networks or temporary validation.

Validated production smoke test:

```bash
curl -fsSI http://127.0.0.1:5000/v2/
curl -fsSI -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  http://127.0.0.1:5000/v2/library/alpine/manifests/3.20
docker pull 127.0.0.1:5000/library/alpine:3.20
```

## Documentation

- Repository overview: [../README.md](../README.md)
- Documentation index: [../docs/README.md](../docs/README.md)
- Docker/Kubernetes client usage: [../docs/client-usage.md](../docs/client-usage.md)
- CDN and security entrypoint: [../docs/cdn-and-security.md](../docs/cdn-and-security.md)
- Operations, upgrades, rollback and GC: [../docs/operations.md](../docs/operations.md)
- Production case with simulated values: [../docs/production-case-silicon-valley.md](../docs/production-case-silicon-valley.md)

## Placeholder Policy

Public docs use simulated values such as `203.0.113.10`, `mirror.example.com`,
`10022`, `/path/to/id_ed25519`, and `replace-with-your-token`. Replace them in
your own environment, but never commit real server IPs, SSH details, tokens, or
`.env` files to this repository.
