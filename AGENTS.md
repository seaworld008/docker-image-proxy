# AI Agent 指南

本仓库维护一个生产可用的 Docker Hub pull-through cache 部署包。

当 AI agent、代码助手或自动化机器人处理本仓库时，请先阅读本文档，再阅读对应任务文档。

## 仓库用途

本仓库提供：

- 基于 Docker Distribution Registry proxy mirror 模式的 Docker Compose 部署包。
- 带生产默认配置的 Nginx 前置容器。
- Docker Engine、Kubernetes Docker CRI、containerd、k3s、RKE2 客户端接入文档。
- CDN、DNS、WAF、源站保护、运维、升级、回滚、验证 runbook。
- 使用模拟公网信息编写的硅谷源站真实部署案例。

当前 mirror 只代理 Docker Hub：

```text
proxy.remoteurl = https://registry-1.docker.io
```

它不会透明加速 `registry.k8s.io`、`quay.io`、`ghcr.io` 或私有镜像仓库。

## 先读这里

- 人类入口：`README.md`
- 文档导航：`docs/README.md`
- 方案入口：`Docker Registry Mirror 自建方案（生产可用）.md`
- 架构设计：`docs/architecture.md`
- 源站部署：`docs/source-deployment.md`
- 部署包说明：`deploy/README.md`
- 客户端配置：`docs/client-usage.md`
- CDN 和安全：`docs/cdn-and-security.md`
- CDN 加速配置：`docs/cdn-acceleration.md`
- CDN 厂商配置：`docs/cdn-provider-setup.md`
- 安全加固：`docs/security-hardening.md`
- 端到端验证：`docs/validation.md`
- 运维手册：`docs/operations.md`
- 模拟值生产案例：`docs/production-case-silicon-valley.md`

## 生产约束

除非用户明确要求改变架构，否则保持以下约束：

- 部署目录固定为 `/data/docker-image-proxy/`。
- 持久化数据、日志、本地配置都放在 `/data/docker-image-proxy/` 下。
- 默认监听地址为 `127.0.0.1:5000`。
- 公网或跨站访问必须通过 HTTPS/CDN 或严格受控的网络路径。
- 直接 HTTP 访问只用于受控测试，并且必须限制来源 IP。
- 生产部署必须通过 `REGISTRY_PROXY_USERNAME` 和 `REGISTRY_PROXY_PASSWORD` 配置 Docker Hub 上游认证。
- `REGISTRY_PROXY_PASSWORD` 应使用 Docker Hub Access Token，不要使用个人主账号密码。
- Compose 镜像必须固定到明确版本 tag。
- `registry` 不直接暴露，Nginx 是本地唯一入口。
- 本服务是 pull-through cache，不是通用私有镜像仓库。

## 当前固定镜像

```text
registry:3.1.1
nginx:1.30.3-alpine
```

更新任一镜像时：

1. 先确认上游最新稳定版本。
2. 更新对应镜像 tag。
3. 按需更新 `README.md`、`deploy/README.md`、`docs/architecture.md`、`docs/source-deployment.md`、`docs/operations.md` 和方案入口文档。
4. 运行本地验证；如果有可用服务器，再运行真实环境验证。

## 模拟数据规则

公开文档只能使用模拟值：

```text
203.0.113.10
mirror.example.com
mirror-origin.example.com
10022
/path/to/id_ed25519
replace-with-dockerhub-username
replace-with-dockerhub-access-token
replace-with-random-origin-secret
```

禁止提交：

- 真实公网服务器 IP。
- SSH 私钥或真实工作站上的私钥路径。
- 能识别服务器的真实 SSH 端口。
- Docker Hub 用户名、密码、Access Token。
- `.env` 文件。
- 云厂商凭据。
- `REGISTRY_HTTP_SECRET`。
- 真实 `REGISTRY_PROXY_USERNAME` 或 `REGISTRY_PROXY_PASSWORD`。

如果记录真实部署案例，必须把敏感值替换成上面的模拟值，并明确说明用户上线前要替换成自己的真实值。

## 验证命令

源站服务器：

```bash
cd /data/docker-image-proxy
docker compose ps
./scripts/validate.sh
curl -fsSI http://127.0.0.1:5000/v2/
```

Docker 客户端：

```bash
docker info | sed -n '/Registry Mirrors/,+8p'
docker pull alpine:3.20
```

containerd/Kubernetes 客户端：

```bash
crictl pull docker.io/library/alpine:3.20
kubectl run mirror-test --image=docker.io/library/alpine:3.20 --restart=Never -- sleep 60
kubectl delete pod mirror-test
```

CDN 入口：

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://mirror.example.com/v2/library/alpine/manifests/3.20
```

## 编辑规则

- 优先做小而聚焦的改动。
- README 保持简洁，长步骤放到 `docs/`。
- 新增、重命名或删除文档时，同步更新 `docs/README.md`。
- 文档、脚本注释、示例说明默认使用中文；配置键、命令、第三方协议字段保持原样。
- 占位符在各文档中保持一致。
- 不要加入真实密钥、真实机器路径或可识别服务器的信息。
- 修改 Docker、containerd、Kubernetes、k3s、CDN 运行配置指导时，优先参考官方文档。
- 提交前运行 `git diff --check`。

## 常见用户目标

部署最新稳定版：

1. 确认当前上游最新稳定版本。
2. 如果需要，更新镜像 tag。
3. 从 `deploy/` 部署到 `/data/docker-image-proxy/`。
4. 在 `.env` 中填写专用 Docker Hub 用户名和 Access Token。
5. 运行 `./scripts/validate.sh`。
6. 记录生产验证结论。

配置国内服务器使用：

1. 确认源站入口可通过 HTTPS/CDN 或受控 HTTP 访问。
2. 确认客户端运行时是 Docker、Docker CRI、containerd、k3s 还是 RKE2。
3. 按 `docs/client-usage.md` 配置。
4. 用真实 `docker pull` 或 `crictl pull` 验证。

加固公网访问：

1. 从 `docs/cdn-and-security.md` 选择入口模式。
2. 优先使用 HTTPS CDN 入口。
3. 按 `docs/cdn-acceleration.md` 配置 CDN 缓存、Range 和 Header。
4. 按 `docs/cdn-provider-setup.md` 配置具体 CDN 厂商。
5. 按 `docs/security-hardening.md` 用 CDN 回源 IP 白名单或回源鉴权限制源站访问。
6. `/v2/` 路径不要启用会破坏 Docker 客户端的 WAF 人机挑战。
