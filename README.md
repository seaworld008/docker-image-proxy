# Docker Image Proxy

生产可用的 Docker Hub pull-through cache 部署包，用于给国内 Docker 服务器和 Kubernetes 节点提供稳定的 Docker Hub 镜像加速入口。

本仓库的目标是把一个镜像加速方案整理成可长期维护的生产级工程：部署脚本、Compose 配置、客户端接入、CDN/安全、运维升级、真实案例和 AI agent 上下文都集中在仓库中。

## 当前稳定版本

当前推荐版本（2026-06-30 已核验）：

| 组件 | 版本 | Digest |
| --- | --- | --- |
| Docker Distribution Registry | `registry:3.1.1` | `sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33` |
| Nginx | `nginx:1.30.3-alpine` | `sha256:0d3b80406a13a767339fbe2f41406d6c7da727ab89cf8fae399e81f780f814d1` |

Compose 文件已固定到 tag + digest，避免上游 tag 漂移。

## 适用场景

- 国内 Docker 服务器拉取 Docker Hub 镜像慢或不稳定。
- Kubernetes 节点需要统一配置 Docker Hub mirror。
- 小团队、多机房或自用环境需要一个可控的 Docker Hub 缓存代理。
- 需要通过 CDN、安全组和回源鉴权把海外源站安全发布给国内节点。

不适用或需要额外扩展的场景：

- 需要代理 `registry.k8s.io`、`quay.io`、`ghcr.io` 等非 Docker Hub registry。
- 需要作为私有镜像仓库写入和推送镜像。
- 超大规模公共 mirror，需额外设计多源站、对象存储、审计、配额和滥用治理。

## 快速部署

把 `deploy/` 同步到服务器 `/data/docker-image-proxy/` 后执行：

```bash
cd /data/docker-image-proxy
cp .env.example .env
sed -i "s/replace-with-64-hex-chars/$(openssl rand -hex 32)/" .env
docker compose pull
docker compose up -d
./scripts/validate.sh
```

也可以运行内置安装脚本：

```bash
cd /data/docker-image-proxy
chmod +x ./scripts/install-or-update.sh
./scripts/install-or-update.sh
```

默认入口为 `127.0.0.1:5000`，不会直接暴露公网。要给国内服务器使用，请先配置 CDN HTTPS 或受控直连入口。

## 客户端使用方式

普通 Docker 服务器：

```json
{
  "registry-mirrors": [
    "https://mirror.example.com"
  ]
}
```

Kubernetes containerd 节点：

```toml
server = "https://registry-1.docker.io"

[host."https://mirror.example.com"]
  capabilities = ["pull", "resolve"]
```

业务镜像名保持原样：

```bash
docker pull alpine:3.20
docker pull nginx:1.30.3-alpine
```

详细步骤见 [国内 Docker/Kubernetes 客户端接入手册](docs/client-usage.md)。

## 推荐生产架构

```text
国内 Docker/Kubernetes 节点
        |
        | HTTPS
        v
mirror.example.com  CDN/WAF/边缘缓存
        |
        | 受控回源
        v
硅谷/海外源站 /data/docker-image-proxy/
        |
        v
registry:3.1.1 -> Docker Hub
```

生产建议：

- 客户端统一使用 HTTPS 域名，例如 `https://mirror.example.com`。
- 源站只允许 CDN 回源 IP 或专用内网访问。
- HTTP `5000` 直连仅用于短期验证，必须做源 IP 白名单。
- Docker Hub 上游认证只使用专用低权限账号/token。
- 所有持久化数据放在 `/data/docker-image-proxy/` 下。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| [docs/README.md](docs/README.md) | 文档导航，建议先读这里 |
| [Docker Registry Mirror 自建方案（生产可用）.md](Docker%20Registry%20Mirror%20%E8%87%AA%E5%BB%BA%E6%96%B9%E6%A1%88%EF%BC%88%E7%94%9F%E4%BA%A7%E5%8F%AF%E7%94%A8%EF%BC%89.md) | 方案总览与架构决策 |
| [deploy/README.md](deploy/README.md) | 部署包说明 |
| [docs/client-usage.md](docs/client-usage.md) | Docker、Kubernetes Docker CRI、containerd、k3s、RKE2 接入 |
| [docs/cdn-and-security.md](docs/cdn-and-security.md) | 域名、CDN、源站安全、WAF、回源配置 |
| [docs/cdn-provider-setup.md](docs/cdn-provider-setup.md) | 阿里云、腾讯云、华为云、AWS CloudFront、Cloudflare CDN 逐步配置 |
| [docs/operations.md](docs/operations.md) | 日常运维、升级、回滚、清理、排错 |
| [docs/production-case-silicon-valley.md](docs/production-case-silicon-valley.md) | 硅谷源站真实部署案例，使用模拟数据展示 |
| [AGENTS.md](AGENTS.md) | 给 AI agent 和后续维护者的仓库上下文 |

## 仓库结构

```text
.
├── deploy/                         # 可复制到服务器的部署包
│   ├── docker-compose.yml
│   ├── docker-compose.with-auth.yml
│   ├── .env.example
│   ├── config/registry/config.yml
│   ├── nginx/nginx.conf
│   └── scripts/
├── docs/                           # 拆分后的生产运维文档
├── AGENTS.md                       # AI agent 维护说明
├── README.md                       # 仓库总入口
└── Docker Registry Mirror 自建方案（生产可用）.md
```

## 验证

源站本机验证：

```bash
cd /data/docker-image-proxy
./scripts/validate.sh
```

客户端验证：

```bash
docker info | sed -n '/Registry Mirrors/,+8p'
docker pull alpine:3.20
```

Kubernetes 节点验证：

```bash
crictl pull docker.io/library/alpine:3.20
kubectl run mirror-test --image=docker.io/library/alpine:3.20 --restart=Never -- sleep 60
kubectl delete pod mirror-test
```

## 安全提醒

公开仓库中只能出现模拟数据，例如：

- 公网 IP：`203.0.113.10`
- 域名：`mirror.example.com`
- SSH 端口：`10022`
- 私钥路径：`/path/to/id_ed25519`
- token：`replace-with-your-token`

上线前必须替换成自己的真实值，但真实 IP、SSH 端口、私钥路径、token、`.env` 内容不要提交到仓库。

## 参考

- Docker Hub mirror 官方文档：https://docs.docker.com/docker-hub/image-library/mirror/
- Docker Engine daemon 配置：https://docs.docker.com/reference/cli/dockerd/
- containerd registry hosts 配置：https://github.com/containerd/containerd/blob/main/docs/hosts.md
- Kubernetes container runtimes：https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- k3s private registry 配置：https://docs.k3s.io/installation/private-registry
