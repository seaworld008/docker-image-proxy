# Docker Image Proxy

> 面向国内 Docker 服务器和 Kubernetes 节点的自建 Docker Hub pull-through cache 部署包。

[![Release](https://img.shields.io/github/v/release/seaworld008/docker-image-proxy?sort=semver&display_name=tag&label=release)](https://github.com/seaworld008/docker-image-proxy/releases)
[![Stars](https://img.shields.io/github/stars/seaworld008/docker-image-proxy?style=flat&label=stars)](https://github.com/seaworld008/docker-image-proxy/stargazers)
[![Forks](https://img.shields.io/github/forks/seaworld008/docker-image-proxy?style=flat&label=forks)](https://github.com/seaworld008/docker-image-proxy/forks)
[![Issues](https://img.shields.io/github/issues/seaworld008/docker-image-proxy?label=issues)](https://github.com/seaworld008/docker-image-proxy/issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/seaworld008/docker-image-proxy?label=prs)](https://github.com/seaworld008/docker-image-proxy/pulls)
[![Last Commit](https://img.shields.io/github/last-commit/seaworld008/docker-image-proxy?label=last%20commit)](https://github.com/seaworld008/docker-image-proxy/commits/main)
[![Registry](https://img.shields.io/badge/registry-3.1.1-blue)](https://hub.docker.com/_/registry)
[![Compose](https://img.shields.io/badge/deploy-docker%20compose-2496ED)](deploy/README.md)
[![Kubernetes](https://img.shields.io/badge/kubernetes-containerd%20%7C%20docker-326CE5)](docs/client-usage.md)
[![CDN](https://img.shields.io/badge/CDN-Aliyun%20%7C%20Tencent%20%7C%20Huawei%20%7C%20AWS%20%7C%20Cloudflare-orange)](docs/cdn-provider-setup.md)
[![Docs](https://img.shields.io/badge/docs-production%20guides-brightgreen)](docs/README.md)

Docker Image Proxy 是一个以 Docker Compose 交付的 Docker Hub registry mirror 部署包，核心目标是把 Docker Hub pull-through cache、Nginx 本地入口、CDN 发布、安全加固、客户端接入和运维验证整理成一套可复制、可审查、可长期维护的仓库。

English summary: this repository provides a self-hosted Docker Hub registry mirror / pull-through cache package with Docker Compose, Nginx, CDN guidance, Kubernetes/containerd client configuration, and production operation runbooks. The main documentation is currently written in Chinese.

**核心入口：** [文档导航](docs/README.md) | [部署包](deploy/README.md) | [客户端接入](docs/client-usage.md) | [CDN 配置](docs/cdn-provider-setup.md) | [安全加固](docs/security-hardening.md) | [端到端验证](docs/validation.md) | [Releases](https://github.com/seaworld008/docker-image-proxy/releases) | [Issues](https://github.com/seaworld008/docker-image-proxy/issues)

如果这个仓库帮你快速搭建了稳定的 Docker Hub mirror，欢迎 Star，让更多需要自建镜像加速入口的人看到它。

## 30 秒理解

| 问题 | 本仓库提供什么 |
| --- | --- |
| 国内服务器拉取 Docker Hub 慢或不稳定 | 自建 Docker Hub pull-through cache，并通过 CDN 或受控直连给客户端使用 |
| 多台 Docker/Kubernetes 节点配置分散 | 提供 Docker Engine、Docker CRI、containerd、k3s、RKE2 的接入手册 |
| 担心源站暴露和 token 泄露 | 默认本机监听，文档覆盖 CDN 回源、WAF 放行、源站白名单和敏感信息脱敏 |
| 不想从零拼命令 | `deploy/` 可以整体复制到 `/data/docker-image-proxy/`，包含 Compose、Nginx、Registry 配置和验证脚本 |

## 核心亮点

- **Docker Hub 专用 mirror：** 使用 Docker Distribution Registry 的 proxy 模式，目标上游固定为 `https://registry-1.docker.io`。
- **生产导向的部署包：** Compose、Nginx、Registry 配置、安装脚本、验证脚本和持久化目录都按 `/data/docker-image-proxy/` 组织。
- **Docker Hub 认证必填：** `.env` 必须配置 Docker Hub 用户名和 Access Token，避免匿名回源集中触发限流。
- **多运行时客户端文档：** 覆盖普通 Docker、Kubernetes Docker CRI、containerd、k3s 和 RKE2。
- **CDN 和安全手册：** 覆盖阿里云、腾讯云、华为云、AWS CloudFront、Cloudflare 的配置路径和 Docker Registry 特殊注意事项。

## 当前稳定组件

当前推荐版本（2026-06-30 已核验）：

| 组件 | 镜像 tag | 用途 |
| --- | --- | --- |
| Docker Distribution Registry | `registry:3.1.1` | Docker Hub pull-through cache |
| Nginx | `nginx:1.30.3-alpine` | 本地入口、限流、日志、反向代理 |

Compose 文件固定到明确版本 tag，便于阅读、部署和后续升级。

## 适用场景

- 国内 Docker 服务器拉取 Docker Hub 镜像慢或不稳定。
- Kubernetes 节点需要统一配置 Docker Hub mirror。
- 小团队、多机房或自用环境需要一个可控的 Docker Hub 缓存代理。
- 需要通过 CDN、安全组和回源鉴权把海外源站安全发布给国内节点。
- 需要一份可给后续维护者或 AI agent 快速理解的部署与运维文档。

不适用或需要额外扩展的场景：

- 需要透明代理 `registry.k8s.io`、`quay.io`、`ghcr.io` 等非 Docker Hub registry。
- 需要作为私有镜像仓库写入和推送镜像。
- 需要面向公网超大规模开放 mirror，需额外设计多源站、对象存储、审计、配额和滥用治理。

## 3 分钟快速开始

在海外或可稳定访问 Docker Hub 的源站上执行：

```bash
git clone https://github.com/seaworld008/docker-image-proxy.git
cd docker-image-proxy

sudo mkdir -p /data/docker-image-proxy
sudo cp -a deploy/. /data/docker-image-proxy/
cd /data/docker-image-proxy

cp .env.example .env
sed -i "s/replace-with-64-hex-chars/$(openssl rand -hex 32)/" .env
```

编辑 `.env`，把 Docker Hub 上游认证替换成自己的真实值：

```ini
REGISTRY_PROXY_USERNAME=replace-with-dockerhub-username
REGISTRY_PROXY_PASSWORD=replace-with-dockerhub-access-token
```

启动并验证：

```bash
chmod +x ./scripts/install-or-update.sh
./scripts/install-or-update.sh
```

默认入口为 `127.0.0.1:5000`，不会直接暴露公网。要给国内服务器使用，请先配置 CDN HTTPS 或受控直连入口。

> Docker Hub 账号/token 是生产必填项。自建 mirror 会集中回源 Docker Hub，匿名拉取很容易触发限流；部署脚本会在未填写时直接退出，避免服务以匿名模式悄悄上线。

## 安装部署方式

当前仓库真实支持的部署方式是 Docker Compose：

| 方式 | 状态 | 说明 |
| --- | --- | --- |
| Docker Compose | 已提供 | 使用 `deploy/docker-compose.yml`，推荐部署到 `/data/docker-image-proxy/` |
| Kubernetes / Helm | 暂未提供 | 当前只提供 Kubernetes 节点作为客户端的接入配置 |
| 源码运行 | 不适用 | 本仓库不是应用源码项目，核心服务来自官方 `registry` 和 `nginx` 镜像 |
| 包管理器安装 | 不适用 | 未发布 npm、PyPI、Go module、Maven、crates.io 等包 |

完整源站部署流程见 [源站部署手册](docs/source-deployment.md)，部署包细节见 [deploy/README.md](deploy/README.md)。

## 配置说明

部署配置来自 `/data/docker-image-proxy/.env`：

| 配置项 | 默认值 | 必填 | 说明 |
| --- | --- | --- | --- |
| `REGISTRY_HTTP_SECRET` | 无 | 是 | Registry HTTP 层稳定随机密钥，建议用 `openssl rand -hex 32` 生成 |
| `PROXY_BIND_ADDR` | `127.0.0.1` | 否 | 本地监听地址，生产默认不要直接暴露公网 |
| `PROXY_HTTP_PORT` | `5000` | 否 | Nginx 本地入口端口 |
| `REGISTRY_PROXY_USERNAME` | 无 | 是 | Docker Hub 上游认证用户名 |
| `REGISTRY_PROXY_PASSWORD` | 无 | 是 | Docker Hub Access Token，不建议使用个人主账号密码 |

公开文档中出现的 `203.0.113.10`、`mirror.example.com`、`replace-with-dockerhub-access-token` 都是模拟值，上线前必须替换成自己的真实值，但不要提交真实 `.env`、token、SSH 信息或证书私钥。

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

HTTP 内测入口需要额外加入 `insecure-registries`：

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

适用于运行时显示 `containerd://...` 的节点。containerd 推荐使用 `certs.d/docker.io/hosts.toml`：

```toml
server = "https://registry-1.docker.io"

[host."https://mirror.example.com"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
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

## 截图 / Demo / 架构图

当前仓库没有截图、在线 Demo 或 GIF。原因是本项目主要交付服务端部署包和运维文档，不是带 UI 的应用。

目前 README 使用文本图说明生产架构；后续可以补充：

- CDN + 源站 + Docker/Kubernetes 客户端的架构图。
- 源站 `docker compose ps`、`./scripts/validate.sh`、CDN 拉取验证的终端截图。
- 从国内节点拉取 `alpine:3.20` 的 Demo GIF。
- GitHub Pages 或静态文档站点。

生产建议：

- 客户端统一使用 HTTPS 域名，例如 `https://mirror.example.com`。
- 源站只允许 CDN 回源 IP 或专用内网访问。
- HTTP `5000` 直连仅用于短期验证，必须做源 IP 白名单。
- Docker Hub 上游认证是生产必填项，只使用专用低权限账号/token。
- 所有持久化数据放在 `/data/docker-image-proxy/` 下。

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

CDN endpoint 验证：

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://mirror.example.com/v2/library/alpine/manifests/3.20
```

## 文档入口

| 文档 | 用途 |
| --- | --- |
| [docs/README.md](docs/README.md) | 文档导航，建议先读这里 |
| [Docker Registry Mirror 自建方案（生产可用）.md](Docker%20Registry%20Mirror%20%E8%87%AA%E5%BB%BA%E6%96%B9%E6%A1%88%EF%BC%88%E7%94%9F%E4%BA%A7%E5%8F%AF%E7%94%A8%EF%BC%89.md) | 方案入口和阅读路径 |
| [docs/architecture.md](docs/architecture.md) | 架构设计、适用边界和生产约束 |
| [docs/source-deployment.md](docs/source-deployment.md) | 海外源站部署、入口模式和本机验证 |
| [deploy/README.md](deploy/README.md) | 部署包说明 |
| [docs/client-usage.md](docs/client-usage.md) | Docker、Kubernetes Docker CRI、containerd、k3s、RKE2 接入 |
| [docs/cdn-and-security.md](docs/cdn-and-security.md) | CDN/安全入口模式选择 |
| [docs/cdn-acceleration.md](docs/cdn-acceleration.md) | CDN 选型、缓存、Range、Header |
| [docs/cdn-provider-setup.md](docs/cdn-provider-setup.md) | 阿里云、腾讯云、华为云、AWS CloudFront、Cloudflare CDN 逐步配置 |
| [docs/security-hardening.md](docs/security-hardening.md) | 源站保护、WAF、回源鉴权、限流、密钥 |
| [docs/validation.md](docs/validation.md) | 源站、CDN、Docker、Kubernetes 端到端验证 |
| [docs/operations.md](docs/operations.md) | 日常运维、升级、回滚、清理、排错 |
| [docs/production-case-silicon-valley.md](docs/production-case-silicon-valley.md) | 硅谷源站真实部署案例，使用模拟数据展示 |
| [AGENTS.md](AGENTS.md) | 给 AI agent 和后续维护者的仓库上下文 |

## 项目结构

```text
.
├── deploy/                         # 可复制到服务器的部署包
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── config/registry/config.yml
│   ├── nginx/nginx.conf              # Nginx 主配置
│   ├── nginx/conf.d/default.conf      # 普通入口子配置
│   ├── nginx/conf.d/cdn-origin-auth.conf
│   └── scripts/
├── docs/                           # 架构、部署、CDN、安全、验证、运维文档
├── AGENTS.md                       # AI agent 维护说明
├── README.md                       # 仓库总入口
└── Docker Registry Mirror 自建方案（生产可用）.md
```

## 技术栈

| 类别 | 内容 |
| --- | --- |
| 部署方式 | Docker Compose |
| 核心服务 | Docker Distribution Registry `registry:3.1.1` |
| 本地入口 | Nginx `nginx:1.30.3-alpine` |
| 配置与脚本 | YAML、Nginx conf、POSIX shell |
| 客户端 | Docker Engine、Docker CRI、containerd、k3s、RKE2 |
| 文档 | Markdown |
| CI/CD | 暂未配置，需项目维护者确认后补充 |

## Roadmap

这些是当前基于仓库状态整理的克制型后续建议，具体优先级需维护者确认：

- [ ] 确认并补充开源许可证，例如 MIT 或 Apache-2.0。
- [ ] 增加英文 README 或英文文档摘要，方便全球开发者搜索和引用。
- [ ] 增加架构图、部署效果截图或 Demo GIF。
- [ ] 增加可运行的 Markdown/link 检查 workflow。
- [ ] 补充更多 CDN 厂商、更多 Kubernetes 发行版和真实生产验证案例。
- [ ] 增加 GitHub Pages 或静态文档站点。
- [ ] 增加 Release 检查清单，避免文档与最新 main 漂移。

## FAQ

### 这个项目是不是私有镜像仓库？

不是。当前设计是 Docker Hub pull-through cache，只适合缓存和代理 Docker Hub 拉取，不用于写入或推送私有镜像。

### 是否支持 `registry.k8s.io`、`quay.io`、`ghcr.io`？

不支持透明代理。当前 `proxy.remoteurl` 固定为 `https://registry-1.docker.io`。其他 registry 需要单独设计镜像入口和客户端配置。

### 为什么 Docker Hub 账号和 token 是必填？

自建 mirror 会代表多个客户端集中访问 Docker Hub。匿名访问更容易触发限流，生产环境建议使用专用低权限 Docker Hub 账号和 Access Token。

### 是否可以直接暴露 `5000` 端口？

只建议在受控测试或来源 IP 白名单场景使用。生产推荐 HTTPS CDN 或受控网关入口，并保护源站。

### 是否适合生产环境？

仓库提供了生产导向的部署、CDN、安全、运维和验证文档，但真实生产可用性仍取决于源站资源、CDN 配置、访问规模、Docker Hub 账号配额和团队运维能力。上线前请完整执行 [验证手册](docs/validation.md)。

### 为什么没有 License badge？

因为仓库当前还没有 `LICENSE` 文件。许可证需要维护者确认后再添加，避免误导用户。

## 参与贡献

欢迎通过 Issue 或 PR 补充真实部署经验、排错案例、CDN 厂商配置、Kubernetes 发行版配置和文档修正。开始前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

贡献时请注意：

- 不要提交真实 `.env`、公网 IP、SSH 端口、私钥路径、token、证书私钥或回源密钥。
- 文档示例统一使用 `203.0.113.10`、`mirror.example.com` 和 `replace-with-*` 这类模拟值。
- 配置变更需要同步更新 README、`docs/README.md`、`deploy/README.md` 和 `AGENTS.md` 中的入口或约束。

## 安全

安全问题请不要直接在公开 Issue 中贴出敏感细节。请优先使用 GitHub Security Advisories，或联系项目维护者。详细说明见 [SECURITY.md](SECURITY.md)。

## 许可证

当前仓库尚未声明开源许可证。使用、分发或二次开发前，请等待维护者补充 `LICENSE` 文件或联系维护者确认授权范围。

维护者可考虑 MIT 或 Apache-2.0，但最终许可证需要结合项目归属、第三方约束和发布策略确认。

## 参考

- Docker Hub mirror 官方文档：https://docs.docker.com/docker-hub/image-library/mirror/
- Docker Engine daemon 配置：https://docs.docker.com/reference/cli/dockerd/
- containerd registry hosts 配置：https://github.com/containerd/containerd/blob/main/docs/hosts.md
- Kubernetes container runtimes：https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- k3s private registry 配置：https://docs.k3s.io/installation/private-registry
