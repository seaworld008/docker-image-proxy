# AI Agent Guide

This repository maintains a production-ready Docker Hub pull-through cache deployment package.

Use this file as the first context document when an AI agent, coding assistant, or automation bot works on the repo.

## What This Repo Does

The repo provides:

- A Docker Compose deploy package for Docker Distribution Registry in proxy mirror mode.
- An Nginx front container with production-oriented defaults.
- Documentation for Docker Engine, Kubernetes Docker CRI, containerd, k3s, and RKE2 clients.
- CDN, DNS, WAF, origin protection, operations, upgrade, rollback, and validation runbooks.
- A real deployment case for a Silicon Valley source server, documented with simulated public values.

The mirror targets Docker Hub only:

```text
proxy.remoteurl = https://registry-1.docker.io
```

It does not transparently accelerate `registry.k8s.io`, `quay.io`, `ghcr.io`, or private registries.

## Start Here

- Human entrypoint: `README.md`
- Documentation index: `docs/README.md`
- Architecture overview: `Docker Registry Mirror 自建方案（生产可用）.md`
- Deploy package: `deploy/README.md`
- Client configuration: `docs/client-usage.md`
- CDN and security: `docs/cdn-and-security.md`
- CDN provider setup: `docs/cdn-provider-setup.md`
- Operations: `docs/operations.md`
- Real deployment case with simulated values: `docs/production-case-silicon-valley.md`

## Production Invariants

Keep these properties unless the user explicitly asks for a different architecture:

- Deployment directory is `/data/docker-image-proxy/`.
- Persistent data, logs, and local config stay under `/data/docker-image-proxy/`.
- Default bind address is `127.0.0.1:5000`.
- Public or cross-site access must go through HTTPS/CDN or a tightly controlled network path.
- Direct HTTP access is only for controlled testing and must be source-IP restricted.
- Compose images are pinned by tag and digest.
- `registry` is not exposed directly; Nginx is the only local entrypoint.
- This service is a pull-through cache, not a general private registry.

## Current Pinned Images

```text
registry:3.1.1@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33
nginx:1.30.3-alpine@sha256:0d3b80406a13a767339fbe2f41406d6c7da727ab89cf8fae399e81f780f814d1
```

When updating either image:

1. Verify the latest stable upstream release.
2. Update tag and digest together.
3. Update `README.md`, `deploy/README.md`, `docs/operations.md`, and the architecture overview if needed.
4. Run local validation and, when available, live server validation.

## Simulated Data Policy

Public docs may use simulated values only:

```text
203.0.113.10
mirror.example.com
mirror-origin.example.com
10022
/path/to/id_ed25519
replace-with-your-token
```

Never commit:

- Real public server IPs.
- SSH private keys or private key paths from a real workstation.
- Real SSH ports if they identify a server.
- Docker Hub usernames/tokens.
- `.env` files.
- Cloud provider credentials.
- `REGISTRY_HTTP_SECRET`.

If a real deployment case is documented, replace sensitive values with the simulated examples above and explicitly state that users must replace them before production use.

## Validation Commands

Source server:

```bash
cd /data/docker-image-proxy
docker compose ps
./scripts/validate.sh
curl -fsSI http://127.0.0.1:5000/v2/
```

Docker client:

```bash
docker info | sed -n '/Registry Mirrors/,+8p'
docker pull alpine:3.20
```

containerd/Kubernetes client:

```bash
crictl pull docker.io/library/alpine:3.20
kubectl run mirror-test --image=docker.io/library/alpine:3.20 --restart=Never -- sleep 60
kubectl delete pod mirror-test
```

CDN endpoint:

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://mirror.example.com/v2/library/alpine/manifests/3.20
```

## Editing Rules

- Prefer small, focused docs changes.
- Keep README concise; move long operational steps into `docs/`.
- Update `docs/README.md` whenever adding, renaming, or removing docs.
- Keep placeholders consistent across docs.
- Do not add secrets or machine-specific real paths.
- Use official docs for Docker, containerd, Kubernetes, k3s, and CDN behavior when changing runtime configuration guidance.
- Run `git diff --check` before committing.

## Common User Goals

For "deploy latest stable version":

1. Verify current upstream versions.
2. Update image pins if needed.
3. Deploy from `deploy/` to `/data/docker-image-proxy/`.
4. Run `./scripts/validate.sh`.
5. Document any production findings.

For "configure domestic servers":

1. Ensure source endpoint is reachable through HTTPS/CDN or controlled HTTP.
2. Identify client runtime: Docker, Docker CRI, containerd, k3s, or RKE2.
3. Apply `docs/client-usage.md`.
4. Validate with real `docker pull` or `crictl pull`.

For "harden public access":

1. Start from `docs/cdn-and-security.md`.
2. Prefer HTTPS CDN entrypoint.
3. Use `docs/cdn-provider-setup.md` for provider-specific CDN steps.
4. Restrict source access by CDN IP allowlist or origin authentication.
5. Keep WAF challenges disabled for `/v2/`.
