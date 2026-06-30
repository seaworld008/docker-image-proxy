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

客户端只需要配置 mirror endpoint，不需要改业务镜像名：

```text
生产推荐：https://mirror.example.com
内测直连：http://203.0.113.10:5000
```

注意：

- endpoint 不要带 `/v2/` 后缀。
- `203.0.113.10` 是文档模拟 IP，上线前替换成自己的源站 IP。
- 生产建议只使用 HTTPS 域名；HTTP 直连必须限制来源 IP。
- 该 mirror 只代理 Docker Hub，也就是 `docker.io`。

### 普通 Docker 服务器

编辑 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": [
    "https://mirror.example.com"
  ]
}
```

重启并验证：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
docker info | sed -n '/Registry Mirrors/,+8p'
docker pull alpine:3.20
```

如果是 HTTP 内测入口，需要额外加入 `insecure-registries`：

```json
{
  "registry-mirrors": [
    "http://203.0.113.10:5000"
  ],
  "insecure-registries": [
    "203.0.113.10:5000"
  ]
}
```

### Kubernetes 使用 Docker 作为 CRI

先识别节点运行时：

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,RUNTIME:.status.nodeInfo.containerRuntimeVersion
```

适用于运行时显示 `docker://...` 的节点。每个节点都按“普通 Docker 服务器”配置 `/etc/docker/daemon.json`，然后重启：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl restart cri-docker || sudo systemctl restart cri-dockerd
sudo systemctl restart kubelet
```

验证：

```bash
docker pull alpine:3.20
sudo crictl pull docker.io/library/alpine:3.20
```

生产集群建议逐台节点 `drain -> 配置 -> 验证 -> uncordon`。

### Kubernetes 使用 containerd 作为 CRI

适用于运行时显示 `containerd://...` 的节点，每个节点都要配置。containerd 推荐使用 `certs.d/docker.io/hosts.toml`：

```toml
server = "https://registry-1.docker.io"

[host."https://mirror.example.com"]
  capabilities = ["pull", "resolve"]
```

最小配置流程：

```bash
sudo mkdir -p /etc/containerd/certs.d/docker.io
sudo tee /etc/containerd/certs.d/docker.io/hosts.toml >/dev/null <<'EOF'
server = "https://registry-1.docker.io"

[host."https://mirror.example.com"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF

sudo systemctl restart containerd
sudo systemctl restart kubelet
sudo crictl pull docker.io/library/alpine:3.20
```

还需要确认 `/etc/containerd/config.toml` 已启用 `config_path = "/etc/containerd/certs.d"`。containerd 1.x 和 2.x 的 plugin path 不同，完整配置见 [客户端接入手册](docs/client-usage.md#三kubernetes-使用-containerd-作为-cri)。

### k3s / RKE2

k3s 和 RKE2 使用内置 containerd，优先改 `registries.yaml`，不要直接改生成的 containerd 配置。

k3s：

```bash
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<'EOF'
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.example.com"
EOF

sudo systemctl restart k3s || sudo systemctl restart k3s-agent
sudo crictl pull docker.io/library/alpine:3.20
```

RKE2：

```bash
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/registries.yaml >/dev/null <<'EOF'
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.example.com"
EOF

sudo systemctl restart rke2-server || sudo systemctl restart rke2-agent
sudo crictl pull docker.io/library/alpine:3.20
```

业务镜像名保持原样：

```bash
docker pull alpine:3.20
docker pull nginx:1.30.3-alpine
kubectl run mirror-test --image=docker.io/library/alpine:3.20 --restart=Never -- sleep 60
```

完整步骤、HTTP 内测、自签名证书、kubeadm、逐台节点发布和排错见 [国内 Docker/Kubernetes 客户端接入手册](docs/client-usage.md)。

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
