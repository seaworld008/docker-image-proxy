# 架构设计说明

本文说明 Docker Image Proxy 的生产架构、适用边界、核心组件和关键约束。具体部署步骤见 [源站部署手册](source-deployment.md)，CDN 配置见 [CDN 加速配置手册](cdn-acceleration.md)，安全加固见 [安全加固手册](security-hardening.md)。

## 一、目标

本仓库要解决的是：在可控海外源站上自建 Docker Hub pull-through cache，再通过 HTTPS/CDN 给国内 Docker 服务器和 Kubernetes 节点使用。

客户端仍然拉取原始镜像名：

```bash
docker pull alpine:3.20
crictl pull docker.io/library/alpine:3.20
```

客户端只在运行时配置 mirror endpoint：

```text
https://mirror.example.com
```

## 二、生产架构

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
registry:3.1.1 -> https://registry-1.docker.io
```

源站由两个容器组成：

| 组件 | 作用 | 暴露方式 |
| --- | --- | --- |
| `nginx` | 本地入口、限流、日志、反代 registry | 默认 `127.0.0.1:5000` |
| `registry` | Docker Distribution pull-through cache | 只在 Compose 网络内暴露 |

## 三、当前固定版本

| 组件 | 固定镜像 |
| --- | --- |
| Registry | `registry:3.1.1@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33` |
| Nginx | `nginx:1.30.3-alpine@sha256:0d3b80406a13a767339fbe2f41406d6c7da727ab89cf8fae399e81f780f814d1` |

更新镜像时必须同时更新 tag 和 digest，并重新执行 [验证手册](validation.md) 中的源站、CDN、客户端验证。

## 四、生产约束

除非明确要改架构，否则保持这些约束：

- 部署目录固定为 `/data/docker-image-proxy/`。
- 持久化数据、日志、配置都放在 `/data/docker-image-proxy/` 下。
- `registry` 不直接暴露给公网，只有 `nginx` 作为本地入口。
- 默认监听 `127.0.0.1:5000`，公网或跨站访问必须走 CDN/HTTPS 或受控直连。
- Docker Hub 上游认证必填，必须配置 `REGISTRY_PROXY_USERNAME` 和 `REGISTRY_PROXY_PASSWORD`。
- `REGISTRY_PROXY_PASSWORD` 使用 Docker Hub Access Token，不使用个人主账号密码。
- 本服务只做 Docker Hub pull-through cache，不作为私有镜像仓库使用。

## 五、镜像代理边界

当前配置只代理 Docker Hub：

```yaml
proxy:
  remoteurl: https://registry-1.docker.io
```

不会透明加速：

```text
registry.k8s.io
quay.io
ghcr.io
私有镜像仓库
```

如果需要加速这些 registry，应分别配置对应的 mirror、代理或私有仓库策略，不要把本 Docker Hub mirror 当成万能入口。

## 六、访问路径选择

推荐顺序：

| 模式 | 用途 | 推荐度 |
| --- | --- | --- |
| CDN HTTPS + 源站 HTTPS `443` | 标准生产入口，端到端 HTTPS，适合长期使用 | 推荐 |
| CDN HTTPS + 源站 HTTP `5000` | 当前独立 Compose 改动少，适合 CDN 支持自定义回源端口的场景 | 可用 |
| HTTP `5000` 直连 | 仅用于短期内测和排障 | 临时 |

选择细节见 [源站部署手册](source-deployment.md) 和 [CDN 加速配置手册](cdn-acceleration.md)。

## 七、缓存策略

Registry 源站缓存：

```yaml
proxy:
  ttl: 168h
```

CDN 边缘缓存建议：

| 路径 | 建议缓存 | 原因 |
| --- | --- | --- |
| `/v2/` | 不缓存或 10-60 秒 | 协议探测入口，不需要长缓存 |
| `/v2/*/manifests/*` | 不缓存或 60-600 秒 | tag 可能变化，且受 `Accept` 头影响 |
| `/v2/*/blobs/*` | 7-30 天 | digest 路径内容不可变，适合长缓存 |

详细配置见 [CDN 加速配置手册](cdn-acceleration.md)。

## 八、数据和容量

建议中小规模起步配置：

| 场景 | CPU/内存 | 磁盘 | 网络 |
| --- | --- | --- | --- |
| 个人或小团队 | 2C/4G | 200GB+ | 50Mbps+ |
| 多节点 Kubernetes | 4C/8G | 500GB+ | 100Mbps+ |

缓存目录：

```text
/data/docker-image-proxy/data/registry/
```

容量治理原则：

- 定期检查磁盘占用。
- 大规模清理前先停服务，再执行 registry garbage-collect。
- 不要手工删除 registry 内部目录。

## 九、安全模型

安全目标分三层：

1. 源站不裸奔：源站端口只允许 CDN 回源 IP、堡垒机或临时测试 IP。
2. CDN 不破坏协议：`/v2/` 跳过验证码、JS Challenge、Bot Challenge，允许 Range。
3. 上游不匿名：Docker Hub 回源使用专用低权限账号和 Access Token。

完整安全配置见 [安全加固手册](security-hardening.md)。

## 十、相关文档

| 文档 | 用途 |
| --- | --- |
| [源站部署手册](source-deployment.md) | `/data/docker-image-proxy/` 如何部署和开放入口 |
| [CDN 加速配置手册](cdn-acceleration.md) | CDN 选型、缓存、回源、Header、Range |
| [CDN 厂商配置手册](cdn-provider-setup.md) | 阿里云、腾讯云、华为云、AWS、Cloudflare 控制台步骤 |
| [安全加固手册](security-hardening.md) | 源站保护、WAF、回源鉴权、限流、密钥管理 |
| [验证手册](validation.md) | 源站、CDN、Docker、Kubernetes 端到端验证 |
| [客户端接入手册](client-usage.md) | Docker、containerd、k3s、RKE2 客户端配置 |
