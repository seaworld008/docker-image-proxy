# Docker Registry Mirror 自建方案（生产可用）

本文是方案入口。原来的长篇部署方案已经拆分到 `docs/` 下的专题文档，避免一个文件同时承载架构、部署、CDN、安全、客户端、验证和运维，后续维护也更清晰。

## 一、推荐方案

当前推荐生产架构：

```text
国内 Docker/Kubernetes 节点
        |
        | HTTPS
        v
mirror.example.com  CDN/WAF/边缘缓存
        |
        | 受控回源
        v
海外源站 /data/docker-image-proxy/
        |
        | Docker Hub 认证回源
        v
registry:3.1.1 -> Docker Hub
```

核心约束：

- 源站部署目录固定为 `/data/docker-image-proxy/`。
- 源站默认只监听 `127.0.0.1:5000`。
- 公网或跨站访问必须通过 HTTPS/CDN 或严格受控的网络路径。
- Docker Hub 上游认证是生产必填项，必须配置专用账号和 Access Token。
- `registry` 不直接暴露，Nginx 是本地唯一入口。
- 本服务只代理 Docker Hub，不透明加速 `registry.k8s.io`、`quay.io`、`ghcr.io` 或私有仓库。

## 二、当前固定版本

| 组件 | 固定镜像 |
| --- | --- |
| Registry | `registry:3.1.1` |
| Nginx | `nginx:1.30.3-alpine` |

## 三、按目标阅读

| 目标 | 阅读文档 |
| --- | --- |
| 了解整体架构和边界 | [架构设计说明](docs/architecture.md) |
| 在海外服务器部署源站 | [源站部署手册](docs/source-deployment.md) |
| 配置 CDN 加速和缓存 | [CDN 加速配置手册](docs/cdn-acceleration.md) |
| 按云厂商控制台逐步配置 | [CDN 厂商配置手册](docs/cdn-provider-setup.md) |
| 做源站、CDN、WAF 安全加固 | [安全加固手册](docs/security-hardening.md) |
| 配置 Docker/Kubernetes 客户端 | [客户端接入手册](docs/client-usage.md) |
| 做端到端验证和排错 | [验证手册](docs/validation.md) |
| 做升级、回滚、备份、GC | [日常运维手册](docs/operations.md) |
| 查看真实部署案例 | [硅谷源站真实部署案例](docs/production-case-silicon-valley.md) |

## 四、最快落地路径

1. 阅读 [架构设计说明](docs/architecture.md)，确认本服务只代理 Docker Hub。
2. 按 [源站部署手册](docs/source-deployment.md) 把 `deploy/` 同步到 `/data/docker-image-proxy/`。
3. 在 `.env` 中填写 Docker Hub 专用用户名和 Access Token。
4. 运行：

```bash
cd /data/docker-image-proxy
chmod +x ./scripts/install-or-update.sh
./scripts/install-or-update.sh
```

5. 按 [CDN 加速配置手册](docs/cdn-acceleration.md) 配置 `https://mirror.example.com`。
6. 按 [安全加固手册](docs/security-hardening.md) 限制源站访问和 WAF 行为。
7. 按 [验证手册](docs/validation.md) 验证源站、CDN、Docker、Kubernetes。
8. 按 [客户端接入手册](docs/client-usage.md) 配置国内节点。

## 五、CDN 和安全要点

CDN 选型：

- 优先选下载加速、大文件下载、全站加速或动静态混合。
- 不建议把纯动态加速作为首选。
- `/v2/*/blobs/*` 适合长缓存 7-30 天。
- `/v2/*/manifests/*` 建议不缓存或短缓存 60-600 秒。
- `/v2/` 不缓存或只做极短缓存。

安全要点：

- 源站安全组只允许 CDN 回源 IP、堡垒机或临时测试 IP。
- 如 CDN 支持自定义回源 Header，可启用 `nginx/conf.d/cdn-origin-auth.conf` 校验 `X-Origin-Auth`。
- 对 `/v2/` 跳过 JS Challenge、验证码、Bot Challenge。
- 允许 `GET`、`HEAD`、`OPTIONS` 和 Range 请求。
- 不要把未鉴权 HTTP mirror 对公网开放。
- 不要把真实 Docker Hub token、回源密钥、证书私钥、`.env` 提交到仓库。

## 六、模拟值规则

公开文档只使用模拟值：

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

上线前必须替换成自己的真实值，但真实敏感信息不要提交到仓库。

## 七、参考

- Docker Hub mirror 官方文档：https://docs.docker.com/docker-hub/image-library/mirror/
- Docker Engine daemon 配置：https://docs.docker.com/reference/cli/dockerd/
- Docker Distribution 配置：https://distribution.github.io/distribution/about/configuration/
- containerd registry hosts 配置：https://github.com/containerd/containerd/blob/main/docs/hosts.md
- k3s private registry 配置：https://docs.k3s.io/installation/private-registry
