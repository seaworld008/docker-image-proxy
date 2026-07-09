# CDN 加速配置手册

本文专门说明 Docker Image Proxy 的 CDN 选型、回源模式、缓存规则、Header/Range 透传和上线验证。各云厂商控制台逐步配置见 [CDN 厂商配置手册](cdn-provider-setup.md)，安全加固细节见 [安全加固手册](security-hardening.md)。

## 一、结论

推荐 CDN 类型：

| 优先级 | 类型 | 结论 |
| --- | --- | --- |
| 1 | 下载加速 / 大文件下载 | 最推荐，镜像层 blob 是大文件且适合边缘缓存 |
| 2 | 全站加速 / 动静态混合 / DCDN | 推荐，适合同时处理短缓存 manifest 和长缓存 blob |
| 3 | 纯动态加速 | 不推荐作为首选，通常不重点缓存大文件 |
| 4 | 静态网站加速 | 谨慎，必须确认支持 `/v2/`、Range、请求头透传 |

如果控制台要求选择业务类型，优先选择：

```text
下载加速 / 大文件下载 / 文件下载
```

没有下载加速时选择：

```text
全站加速 / 动静态混合 / DCDN
```

不要只为了“看起来更智能”选择纯动态加速。Docker 镜像加速最重要的收益来自 `/v2/*/blobs/*` 的大文件边缘缓存。

## 二、CDN 域名和源站域名

建议准备两个名字：

```text
mirror.example.com         # 客户端使用的 CDN 加速域名
mirror-origin.example.com  # 可选，只给 CDN 回源使用
```

规则：

- `mirror.example.com` 指向 CDN 厂商分配的 CNAME，或在 Cloudflare 中开启代理。
- CDN 回源不要指向 `mirror.example.com` 自己，避免回源环。
- `mirror-origin.example.com` 可以解析到源站 IP，但源站安全组仍要限制来源。

## 三、回源模式

### 模式 A：CDN HTTPS + 源站 HTTP `5000`

适合当前独立 Compose 部署。

```text
客户端 HTTPS -> CDN -> HTTP:5000 -> 源站 nginx -> registry
```

CDN 回源参数：

```text
源站地址：203.0.113.10 或 mirror-origin.example.com
回源协议：HTTP
回源端口：5000
回源 Host：mirror.example.com
```

安全要求：

- 源站 TCP `5000` 只允许 CDN 回源 IP 段。
- 如 CDN 支持自定义回源 Header，可把 `.env` 中 `NGINX_SERVER_CONF` 切到 `./nginx/conf.d/cdn-origin-auth.conf`，并在 CDN 回源添加 `X-Origin-Auth`。
- 不允许 `0.0.0.0/0` 直连。
- WAF 对 `/v2/` 不启用浏览器挑战。

### 模式 B：CDN HTTPS + 源站 HTTPS `443`

推荐长期生产使用。

```text
客户端 HTTPS -> CDN -> HTTPS:443 -> 源站网关 -> 127.0.0.1:5000
```

CDN 回源参数：

```text
源站地址：mirror-origin.example.com
回源协议：HTTPS
回源端口：443
回源 Host：mirror-origin.example.com 或源站网关实际 server_name
```

安全要求：

- 源站证书可信，或使用云厂商支持的源站证书。
- 源站安全组只允许 CDN 回源 IP。
- 可叠加回源 Header 鉴权或 Authenticated Origin Pulls。

## 四、必须保留的 Registry 协议能力

CDN 必须允许：

```text
GET
HEAD
OPTIONS
Range
If-Range
Accept
Authorization
User-Agent
Docker-Distribution-API-Version
```

建议配置：

| 项 | 配置 |
| --- | --- |
| 允许方法 | `GET`、`HEAD`、`OPTIONS` |
| 请求头放行 | `Accept`、`Authorization`、`Range`、`If-Range`、`User-Agent` |
| 响应头保留 | `Docker-Distribution-API-Version`、`Content-Type`、`Content-Length`、`Accept-Ranges`、`ETag` |
| Range 回源 | 开启或确认默认支持 |
| 大文件下载 | 开启或确认不限制 |

不要开放 `PUT`、`POST`、`PATCH`、`DELETE`。本服务只做 pull-through cache，不支持客户端推送镜像。

## 五、缓存规则

Docker Registry 请求主要分三类：

| 路径 | 内容 | 建议 |
| --- | --- | --- |
| `/v2/` | 协议探测 | 不缓存或 10-60 秒 |
| `/v2/*/manifests/*` | 镜像清单，tag 可能变化 | 不缓存或 60-600 秒 |
| `/v2/*/blobs/*` | 镜像层，digest 路径 | 7-30 天 |

推荐规则：

```text
/v2/*/blobs/*       7-30 天
/v2/*/manifests/*   不缓存，或 60-600 秒
/v2/                不缓存，或 10-60 秒
其他路径             不缓存
```

如果 CDN 支持自定义缓存键：

- `blobs` 不需要把 `Authorization`、`User-Agent` 放进缓存键，避免缓存碎片。
- `manifests` 如果缓存，缓存键应包含 `Accept` 请求头。
- 不要缓存 401、403、404、429、5xx。

## 六、WAF 和 Bot 防护

对 `/v2/` 路径必须跳过交互式防护：

```text
JS Challenge
Managed Challenge
验证码
浏览器完整性校验
需要 Cookie 的机器人挑战
```

原因：Docker CLI、containerd、kubelet 都不是浏览器，无法通过交互式挑战。

可以保留：

```text
DDoS 防护
IP 黑名单
轻量速率限制
基础恶意流量规则
```

更完整规则见 [安全加固手册](security-hardening.md)。

## 七、主流 CDN 配置入口

详细控制台步骤见 [CDN 厂商配置手册](cdn-provider-setup.md)：

| 厂商 | 推荐产品 | 文档入口 |
| --- | --- | --- |
| 阿里云 | CDN 下载加速 / DCDN | [阿里云 CDN / DCDN 配置](cdn-provider-setup.md#aliyun-cdn) |
| 腾讯云 | CDN 下载加速 / ECDN | [腾讯云 CDN / ECDN 配置](cdn-provider-setup.md#tencent-cdn) |
| 华为云 | CDN 下载加速 / 全站加速 | [华为云 CDN 配置](cdn-provider-setup.md#huawei-cdn) |
| AWS | CloudFront | [AWS CloudFront 配置](cdn-provider-setup.md#aws-cloudfront) |
| Cloudflare | DNS 代理 + Cache Rules | [Cloudflare 配置](cdn-provider-setup.md#cloudflare) |

## 八、上线验证

从国内服务器执行：

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://mirror.example.com/v2/library/alpine/manifests/3.20
```

配置 Docker 后验证：

```bash
docker pull alpine:3.20
docker pull nginx:1.30.3-alpine
```

观察 CDN 命中：

```bash
curl -fsSI https://mirror.example.com/v2/library/alpine/manifests/3.20
```

常见命中头：

```text
X-Cache
CF-Cache-Status
Age
Via
```

预期：

- `blobs` 首次 `MISS`，后续可能 `HIT`。
- `manifests` 如果设置为不缓存，应保持 `BYPASS`、`MISS` 或类似状态。
- 不应返回 HTML、验证码页、登录页或 3xx 回源环。

完整验证流程见 [验证手册](validation.md)。

## 九、参考文档

- Docker Hub mirror：https://docs.docker.com/docker-hub/image-library/mirror/
- Docker Engine daemon 配置：https://docs.docker.com/reference/cli/dockerd/
- Docker Distribution 配置：https://distribution.github.io/distribution/about/configuration/
- AWS CloudFront 缓存行为：https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistValuesCacheBehavior.html
- AWS CloudFront 自定义回源 Header：https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html
- Cloudflare Cache Rules：https://developers.cloudflare.com/cache/how-to/cache-rules/
- Cloudflare Origin Rules：https://developers.cloudflare.com/rules/origin-rules/
- Cloudflare Authenticated Origin Pulls：https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/
