# CDN 和安全入口

本文是 CDN 与安全配置的入口文档。详细配置已经拆分为：

- [CDN 加速配置手册](cdn-acceleration.md)：CDN 选型、回源、缓存、Header、Range、上线验证。
- [CDN 厂商配置手册](cdn-provider-setup.md)：阿里云、腾讯云、华为云、AWS CloudFront、Cloudflare 控制台步骤。
- [安全加固手册](security-hardening.md)：源站安全组、回源鉴权、WAF、限流、密钥管理。
- [验证手册](validation.md)：源站、CDN、Docker、Kubernetes 端到端验证。

## 一、推荐入口模式

### 模式 A：CDN HTTPS + 源站 HTTP `5000`

适合当前独立 Compose 部署，不复用服务器已有 Nginx。

```text
Docker/Kubernetes 客户端 -> https://mirror.example.com -> CDN -> http://源站:5000
```

要求：

- CDN 支持自定义回源端口 `5000`。
- 源站安全组只允许 CDN 回源 IP 段访问 TCP `5000`。
- 客户端只使用 CDN HTTPS 域名，不直接访问源站 HTTP。

源站开放步骤见 [源站部署手册 - 模式 A](source-deployment.md#mode-a-cdn-http-5000)。

### 模式 B：CDN HTTPS + 源站 HTTPS `443`

推荐长期生产形态。

```text
Docker/Kubernetes 客户端 -> https://mirror.example.com -> CDN -> https://mirror-origin.example.com
```

要求：

- 源站有 HTTPS 网关、SLB、Caddy、Nginx 或已有入口。
- 源站网关转发到 `http://127.0.0.1:5000`。
- CDN 使用 HTTPS 回源。
- 源站只允许 CDN 回源 IP 或启用回源鉴权。

源站网关示例见 [源站部署手册 - 模式 B](source-deployment.md#mode-b-cdn-https-443)。

### 模式 C：HTTP `5000` 直连内测

只用于短期验证。

```text
Docker/Kubernetes 客户端 -> http://203.0.113.10:5000
```

要求：

- 源站安全组只允许指定测试服务器公网 IP。
- Docker Engine 配置 `insecure-registries`。
- containerd/k3s 明确使用 HTTP endpoint。
- 验证结束后关闭公网直连。

直连内测步骤见 [源站部署手册 - 直连内测](source-deployment.md#direct-http-test)。

## 二、最快上线路径

1. 按 [源站部署手册](source-deployment.md) 部署 `/data/docker-image-proxy/`。
2. 选择上面的入口模式。
3. 按 [CDN 加速配置手册](cdn-acceleration.md) 配置缓存、Range、Header。
4. 按 [CDN 厂商配置手册](cdn-provider-setup.md) 在具体云厂商控制台落地。
5. 按 [安全加固手册](security-hardening.md) 限制源站访问和 WAF 行为。
6. 按 [验证手册](validation.md) 做端到端验证。
7. 按 [客户端接入手册](client-usage.md) 配置国内节点。

## 三、必须满足的安全条件

上线前确认：

- [ ] Docker Hub 上游认证已配置，`.env` 中有 `REGISTRY_PROXY_USERNAME` 和 `REGISTRY_PROXY_PASSWORD`。
- [ ] 源站没有把 HTTP mirror 对公网无条件开放。
- [ ] 源站安全组只允许 CDN 回源 IP、堡垒机或临时测试 IP。
- [ ] `/v2/` 路径跳过验证码、JS Challenge、Bot Challenge。
- [ ] CDN 允许 `GET`、`HEAD`、`OPTIONS`、`Range`、`If-Range`。
- [ ] `/v2/*/blobs/*` 长缓存，`/v2/*/manifests/*` 不缓存或短缓存。
- [ ] 真实 IP、SSH 信息、Docker Hub token、回源密钥和 `.env` 没有进入仓库。

## 四、相关文档

| 文档 | 用途 |
| --- | --- |
| [架构设计说明](architecture.md) | 整体架构、边界和生产约束 |
| [源站部署手册](source-deployment.md) | 源站部署和开放入口 |
| [CDN 加速配置手册](cdn-acceleration.md) | CDN 选型和通用缓存规则 |
| [CDN 厂商配置手册](cdn-provider-setup.md) | 主流云控制台逐步配置 |
| [安全加固手册](security-hardening.md) | 源站、WAF、回源鉴权、限流、密钥 |
| [验证手册](validation.md) | 端到端验证和故障定位 |
