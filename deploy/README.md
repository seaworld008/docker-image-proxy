# Docker Image Proxy 部署包

本目录设计为可以整体复制到服务器 `/data/docker-image-proxy/` 直接部署。

固定镜像版本：

- `registry:3.1.1@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33`
- `nginx:1.30.3-alpine@sha256:0d3b80406a13a767339fbe2f41406d6c7da727ab89cf8fae399e81f780f814d1`

## 快速开始

先把 `.env.example` 复制成 `.env`，生成 `REGISTRY_HTTP_SECRET`，然后必须填写 Docker Hub 用户名和 Access Token：

```bash
mkdir -p /data/docker-image-proxy
cd /data/docker-image-proxy
cp .env.example .env
sed -i "s/replace-with-64-hex-chars/$(openssl rand -hex 32)/" .env
```

编辑 `.env`，把下面占位符替换成自己的真实值：

```ini
REGISTRY_PROXY_USERNAME=replace-with-dockerhub-username
REGISTRY_PROXY_PASSWORD=replace-with-dockerhub-access-token
```

然后启动：

```bash
chmod +x ./scripts/install-or-update.sh
./scripts/install-or-update.sh
```

默认监听 `127.0.0.1:5000`，避免 mirror 直接暴露到公网。需要给外部服务器使用时，请先配置 HTTPS/CDN、云安全组白名单或回源鉴权，再调整 `PROXY_BIND_ADDR`。

## 为什么 Docker Hub 账号/token 是必填

自建 mirror 会集中代表多个客户端回源 Docker Hub。匿名拉取很容易触发 Docker Hub 限流，表现为镜像拉取失败、速度变慢或返回 429。生产部署必须使用认证回源，避免后续稳定性问题。

建议：

- 使用专用低权限 Docker Hub 账号和 Access Token。
- 不要使用可访问私有镜像的个人主账号，除非 mirror 已做访问控制。
- `.env` 权限保持 `600`，不要提交到仓库。

## 公网或跨站访问

公网或跨站使用时，请在源站前配置 HTTPS/CDN，并通过 CDN 回源 IP 白名单或回源鉴权限制源站访问。直接 HTTP 只适合受控网络或临时验证。

## 生产验证

```bash
curl -fsSI http://127.0.0.1:5000/v2/
curl -fsSI -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  http://127.0.0.1:5000/v2/library/alpine/manifests/3.20
docker pull 127.0.0.1:5000/library/alpine:3.20
```

## 文档入口

- 仓库总览：[../README.md](../README.md)
- 文档导航：[../docs/README.md](../docs/README.md)
- 架构设计：[../docs/architecture.md](../docs/architecture.md)
- 源站部署：[../docs/source-deployment.md](../docs/source-deployment.md)
- Docker/Kubernetes 客户端接入：[../docs/client-usage.md](../docs/client-usage.md)
- CDN 和安全入口：[../docs/cdn-and-security.md](../docs/cdn-and-security.md)
- CDN 加速配置：[../docs/cdn-acceleration.md](../docs/cdn-acceleration.md)
- CDN 厂商配置：[../docs/cdn-provider-setup.md](../docs/cdn-provider-setup.md)
- 安全加固：[../docs/security-hardening.md](../docs/security-hardening.md)
- 端到端验证：[../docs/validation.md](../docs/validation.md)
- 运维、升级、回滚和 GC：[../docs/operations.md](../docs/operations.md)
- 生产案例模拟数据版：[../docs/production-case-silicon-valley.md](../docs/production-case-silicon-valley.md)

## 示例值规则

公开文档使用模拟值，例如 `203.0.113.10`、`mirror.example.com`、`10022`、`/path/to/id_ed25519`、`replace-with-dockerhub-username`、`replace-with-dockerhub-access-token` 和 `replace-with-random-origin-secret`。部署时请替换成自己的真实值，但不要把真实服务器 IP、SSH 信息、token、回源密钥或 `.env` 文件提交到仓库。
