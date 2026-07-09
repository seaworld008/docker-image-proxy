# CDN 厂商配置手册

本文给出 Docker Image Proxy 的 CDN 选型和主流厂商控制台配置步骤，覆盖阿里云、腾讯云、华为云、AWS CloudFront、Cloudflare。

示例值均为模拟数据：

```text
加速域名：mirror.example.com
源站域名：mirror-origin.example.com
源站公网 IP：203.0.113.10
源站 HTTP 端口：5000
源站 HTTPS 端口：443
回源鉴权 Header：X-Origin-Auth: replace-with-random-origin-secret
```

上线前必须替换成自己的真实值，真实 IP、token、证书私钥、回源密钥不要提交到仓库。

## 一、CDN 选型结论

Docker Registry Mirror 的请求大致分两类：

```text
/v2/*/blobs/*       镜像层，大文件，digest 路径，内容不可变，适合长缓存
/v2/*/manifests/*   镜像清单，tag 可能变化，受 Accept 头影响，适合不缓存或短缓存
```

因此 CDN 类型推荐：

| 优先级 | 类型 | 是否推荐 | 原因 |
| --- | --- | --- | --- |
| 1 | 下载加速 / 大文件下载加速 | 推荐 | 最适合镜像层 blob，大文件、Range、边缘缓存收益最大 |
| 2 | 全站加速 / 动静态混合 / DCDN | 推荐 | 能同时处理短缓存 manifest 和长缓存 blob，适合有 WAF/规则需求 |
| 3 | 纯动态加速 | 不推荐 | 通常主要优化链路和回源，不重点缓存大文件，成本收益不匹配 |
| 4 | 静态网站加速 | 谨慎 | 如果不能正确透传 `/v2/`、Range、请求头，就不要选 |

国内厂商控制台如果必须选“业务类型”，优先选：

```text
下载加速 / 大文件下载 / 文件下载
```

如果没有下载加速，选择：

```text
全站加速 / 动静态混合 / DCDN
```

不要选择只面向 API 的纯动态加速，除非你的目标只是跨境链路优化且不需要边缘缓存。

## 二、源站接入模式

### 模式 A：CDN HTTPS + 源站 HTTP:5000

适合当前独立 Compose 部署，改动最少。

前提：

- CDN 支持自定义回源端口 `5000`。
- 源站安全组只允许 CDN 回源 IP 段访问 TCP `5000`。
- 客户端只访问 `https://mirror.example.com`。

源站开放：

```bash
cd /data/docker-image-proxy
cp .env .env.bak.$(date +%F-%H%M%S)
sed -i 's/^PROXY_BIND_ADDR=.*/PROXY_BIND_ADDR=0.0.0.0/' .env
sed -i 's/^PROXY_HTTP_PORT=.*/PROXY_HTTP_PORT=5000/' .env
docker compose up -d
curl -fsSI http://127.0.0.1:5000/v2/
```

CDN 回源填写：

```text
源站地址：203.0.113.10 或 mirror-origin.example.com
回源协议：HTTP
回源端口：5000
回源 Host：mirror.example.com
```

### 模式 B：CDN HTTPS + 源站 HTTPS:443

更标准的生产形态。

前提：

- 源站前面有 HTTPS 网关、SLB、Caddy、Nginx 或已有入口。
- 入口转发到 `http://127.0.0.1:5000`。
- 源站证书可信，或使用云厂商源站证书。

CDN 回源填写：

```text
源站地址：mirror-origin.example.com 或 203.0.113.10
回源协议：HTTPS
回源端口：443
回源 Host：mirror.example.com
```

### 模式 C：HTTP:5000 直连内测

仅用于临时验证，不作为生产入口。

```text
客户端 -> http://203.0.113.10:5000 -> 源站 mirror
```

必须：

- 云安全组只允许指定国内服务器公网 IP 访问 TCP `5000`。
- Docker Engine 配置 `insecure-registries`。
- containerd/k3s endpoint 明确写 `http://203.0.113.10:5000`。

## 三、所有 CDN 都应配置的规则

### 域名和 DNS

```text
mirror.example.com         给 Docker/Kubernetes 客户端使用
mirror-origin.example.com  可选，只给 CDN 回源使用
```

规则：

- `mirror.example.com` 指向 CDN 分配的 CNAME，或在 Cloudflare 中开启代理。
- CDN 回源不要指向 `mirror.example.com` 自己，避免回源环。
- `mirror-origin.example.com` 可以解析到源站 IP，但源站仍要限制只允许 CDN 回源访问。

### HTTPS

```text
客户端访问协议：HTTPS
HTTP -> HTTPS：开启
TLS 最低版本：TLS 1.2
证书：使用 CDN 托管证书或上传证书
```

### 允许方法

```text
GET
HEAD
OPTIONS
```

不要开放 `PUT`、`POST`、`PATCH`、`DELETE`，本方案只做 pull-through cache，不提供推送镜像能力。

### 请求头放行

至少放行：

```text
Accept
Authorization
Range
If-Range
User-Agent
```

说明：

- `Accept` 会影响 manifest 返回格式。
- `Range`、`If-Range` 用于大文件分片下载。
- `Authorization` 可能在 Docker Registry 协议挑战流程中出现。

### 响应头保留

建议保留：

```text
Docker-Distribution-API-Version
Content-Type
Content-Length
Accept-Ranges
ETag
Last-Modified
```

### 缓存规则

推荐：

```text
/v2/                         不缓存，或 10-60 秒
/v2/*/manifests/*            不缓存，或 60-600 秒
/v2/*/blobs/*                7-30 天
其他路径                     不缓存
```

如果 CDN 支持把请求头纳入缓存键：

```text
/v2/*/manifests/* 缓存键加入 Accept
```

如果 CDN 不支持按 `Accept` 细分缓存键，manifests 建议不缓存或只缓存 60 秒。

不要缓存：

```text
401
403
404
429
5xx
```

避免短时认证、限流或上游故障被边缘节点放大。

### WAF 和 Bot 防护

对 `/v2/` 路径：

```text
放行 Docker CLI / containerd / kubelet User-Agent
关闭 JS Challenge
关闭验证码
关闭浏览器完整性校验
关闭需要 Cookie 的机器人挑战
允许大文件和 Range 下载
```

Docker、containerd、kubelet 都不是浏览器，任何交互式挑战都会导致拉取失败。

### 源站保护

推荐至少做一种：

```text
方案 1：源站安全组只允许 CDN 回源 IP 段
方案 2：CDN 回源添加 X-Origin-Auth，源站网关校验
方案 3：Cloudflare Authenticated Origin Pulls
```

如果用 Header 鉴权，CDN 回源添加：

```text
X-Origin-Auth: replace-with-random-origin-secret
```

源站前置 Nginx 示例：

```nginx
if ($http_x_origin_auth != "replace-with-random-origin-secret") {
  return 403;
}
```

如果直接让 CDN 回源到本仓库内置 Nginx，可以启用 CDN 专用入口：

```bash
cd /data/docker-image-proxy
cp .env .env.bak.$(date +%F-%H%M%S)
vi nginx/conf.d/cdn-origin-auth.conf
sed -i 's#^NGINX_SERVER_CONF=.*#NGINX_SERVER_CONF=./nginx/conf.d/cdn-origin-auth.conf#' .env
docker compose up -d
```

编辑 `nginx/conf.d/cdn-origin-auth.conf` 时，把 `replace-with-random-origin-secret` 替换为自己的真实随机长密钥，并在 CDN 回源 Header 中使用同一个值。`nginx/conf.d/default.conf` 是普通入口，`nginx/conf.d/cdn-origin-auth.conf` 是校验 `X-Origin-Auth` 的 CDN 回源入口。不要把真实回源密钥提交到仓库。

<a id="aliyun-cdn"></a>
## 四、阿里云 CDN / DCDN 配置

### 产品选择

优先级：

```text
CDN 下载加速 / 大文件下载
DCDN 全站加速 / 动静态加速
```

如果你的域名要在中国内地节点加速，通常需要完成 ICP 备案。只使用海外节点时按账号和产品要求确认。

### 添加域名

控制台路径大致为：

```text
CDN 或 DCDN 控制台 -> 域名管理 -> 添加域名
```

填写：

```text
加速域名：mirror.example.com
业务类型：下载加速；没有该项时选全站加速/动静态加速
加速区域：中国内地 / 全球 / 全球不含中国内地，按实际资质选择
```

源站配置：

```text
源站类型：源站 IP 或源站域名
源站地址：203.0.113.10 或 mirror-origin.example.com
端口：
  模式 A：HTTP 5000
  模式 B：HTTPS 443
回源 Host：mirror.example.com
```

DNS：

```text
把 mirror.example.com CNAME 到阿里云分配的 CNAME 地址
```

### HTTPS

```text
HTTPS：开启
证书：上传证书或使用云盾/托管证书
HTTP 强制跳转 HTTPS：开启
TLS 版本：TLS 1.2+
```

### 缓存

路径规则：

```text
/v2/*/blobs/*       7-30 天
/v2/*/manifests/*   不缓存或 60-600 秒
/v2/                不缓存或 10-60 秒
```

如果控制台不支持星号形式，按目录规则拆：

```text
/v2/                默认短缓存
包含 /blobs/        长缓存
包含 /manifests/    不缓存或短缓存
```

### Range 和回源

开启或确认：

```text
Range 回源 / 分片回源：开启
回源协议：HTTP 或 HTTPS，按源站模式
回源超时：适当调大，例如 60-180 秒
```

### 访问控制和 WAF

```text
Referer 防盗链：不要用于 /v2/
UA 黑白名单：如启用，放行 Docker-Client、containerd、kubelet
IP 黑白名单：可限制只允许自己的国内服务器出口 IP
WAF：对 /v2/ 放行，关闭验证码/JS Challenge
源站保护：安全组只允许阿里云 CDN 回源 IP 段访问源站端口
```

### 验证

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://mirror.example.com/v2/library/alpine/manifests/3.20
docker pull alpine:3.20
```

查看响应头中的 CDN 命中字段，例如 `X-Cache`、`Via`、`Age` 或厂商自定义头。

<a id="tencent-cdn"></a>
## 五、腾讯云 CDN / ECDN 配置

### 产品选择

优先级：

```text
CDN 下载加速
CDN 动静加速
ECDN / 全站加速
```

如果在中国境内加速，通常需要域名完成 ICP 备案。

### 添加域名

控制台路径大致为：

```text
CDN 控制台 -> 域名管理 -> 添加域名
```

填写：

```text
加速域名：mirror.example.com
业务类型：下载加速；没有该项时选动静加速/全站加速
源站类型：自有源
源站地址：203.0.113.10 或 mirror-origin.example.com
回源协议：
  模式 A：HTTP
  模式 B：HTTPS
回源端口：
  模式 A：5000
  模式 B：443
回源 Host：mirror.example.com
```

DNS：

```text
把 mirror.example.com CNAME 到腾讯云分配的 CNAME 地址
```

### HTTPS

```text
HTTPS：开启
强制 HTTPS：开启
证书：腾讯云托管证书或上传证书
TLS 版本：TLS 1.2+
```

### 缓存

缓存过期配置：

```text
/v2/*/blobs/*       7-30 天
/v2/*/manifests/*   不缓存或 60-600 秒
/v2/                不缓存或 10-60 秒
```

若支持“忽略参数/缓存键”设置：

```text
不要错误忽略影响内容协商的请求头
manifests 如需缓存，尽量按 Accept 区分
```

### Range 和回源

开启：

```text
Range 回源 / 分片回源：开启
回源跟随 301/302：可按需开启
回源超时：适当调大
```

### 访问控制和 WAF

```text
防盗链：不要依赖 Referer
UA 规则：放行 Docker-Client、containerd、kubelet
IP 访问控制：可只允许自己的服务器出口 IP
WAF/Bot：对 /v2/ 跳过验证码、JS Challenge、浏览器校验
源站保护：源站安全组只允许腾讯云 CDN 回源 IP 段
```

### 验证

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI https://mirror.example.com/v2/library/alpine/manifests/3.20
docker pull alpine:3.20
```

查看 `X-Cache-Lookup`、`Age`、`Via` 等命中信息。

<a id="huawei-cdn"></a>
## 六、华为云 CDN 配置

### 产品选择

优先级：

```text
下载加速
全站加速 / 动静态加速
```

中国大陆加速通常需要备案域名。

### 添加域名

控制台路径大致为：

```text
CDN 控制台 -> 域名管理 -> 添加域名
```

填写：

```text
加速域名：mirror.example.com
业务类型：下载加速；没有该项时选全站加速/动静态
源站类型：源站 IP 或源站域名
源站地址：203.0.113.10 或 mirror-origin.example.com
回源协议：
  模式 A：HTTP
  模式 B：HTTPS
回源端口：
  模式 A：5000
  模式 B：443
回源 Host：mirror.example.com
```

DNS：

```text
把 mirror.example.com CNAME 到华为云分配的 CNAME 地址
```

### HTTPS

```text
HTTPS：开启
HTTP 强制跳转 HTTPS：开启
证书：托管证书或上传证书
TLS 版本：TLS 1.2+
```

### 缓存

```text
/v2/*/blobs/*       7-30 天
/v2/*/manifests/*   不缓存或 60-600 秒
/v2/                不缓存或 10-60 秒
```

### Range 和回源

```text
Range 回源：开启
回源协议：按模式选择
回源超时：适当调大
```

### 访问控制和 WAF

```text
Referer 防盗链：不要用于 /v2/
IP 黑白名单：按需限制客户端来源
WAF：对 /v2/ 放行非浏览器客户端
源站保护：只允许华为云 CDN 回源 IP 段访问源站端口
```

### 验证

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI https://mirror.example.com/v2/library/alpine/manifests/3.20
docker pull alpine:3.20
```

<a id="aws-cloudfront"></a>
## 七、AWS CloudFront 配置

CloudFront 更适合全球加速。如果主要服务中国大陆，实际效果和合规要求要结合备案、网络路径和账号区域评估。

### 创建 Distribution

控制台路径：

```text
CloudFront -> Distributions -> Create distribution
```

Origin：

```text
Origin domain：mirror-origin.example.com 或 203.0.113.10 对应的 DNS 名称
Origin protocol policy：
  模式 A：HTTP only
  模式 B：HTTPS only
HTTP port：
  模式 A：5000
  默认：80
HTTPS port：
  模式 B：443
Origin path：留空
Name：docker-image-proxy-origin
```

如果源站需要 Header 鉴权：

```text
Add custom header:
  Header name：X-Origin-Auth
  Header value：replace-with-random-origin-secret
```

注意：CloudFront 的 Origin domain 通常应填域名。若只有 IP，建议先创建 `mirror-origin.example.com` 指向源站 IP。

### Default behavior

```text
Viewer protocol policy：Redirect HTTP to HTTPS
Allowed HTTP methods：GET, HEAD, OPTIONS
Cached HTTP methods：GET, HEAD
Cache key and origin requests：使用自定义 Cache policy / Origin request policy
Compress objects automatically：关闭或保持默认；镜像层本身不依赖此项
```

### Cache behaviors

建议创建三个行为，顺序从具体到通用：

```text
Path pattern: /v2/*/blobs/*
  TTL: 7-30 天
  Cache key: 不需要 query string
  Origin request: 转发 Range、If-Range、User-Agent

Path pattern: /v2/*/manifests/*
  TTL: 0 或 60-600 秒
  Cache key: 包含 Accept header
  Origin request: 转发 Accept、Authorization、User-Agent

Path pattern: /v2/*
  TTL: 0 或 10-60 秒
  Origin request: 转发必要请求头
```

如果你不想管理复杂缓存键，直接让 `/v2/*/manifests/*` TTL 为 `0`，只缓存 blobs。

### Cache policy

blobs policy：

```text
Minimum TTL：0
Default TTL：604800
Maximum TTL：2592000
Headers included in cache key：None
Query strings：None
Cookies：None
```

manifests policy：

```text
Minimum TTL：0
Default TTL：0 或 60
Maximum TTL：600
Headers included in cache key：Accept
Query strings：None
Cookies：None
```

### Origin request policy

转发：

```text
Accept
Authorization
Range
If-Range
User-Agent
```

### 证书和域名

```text
Alternate domain name (CNAME)：mirror.example.com
Custom SSL certificate：在 us-east-1 的 ACM 证书
DNS：把 mirror.example.com CNAME 到 CloudFront distribution domain
```

### WAF

如使用 AWS WAF：

```text
对 /v2/* 跳过 Bot Control、CAPTCHA、Challenge
允许 GET、HEAD、OPTIONS
限制来源 IP 或速率时，不要误伤批量拉镜像节点
```

### 源站保护

推荐：

```text
CloudFront Origin Custom Header + 源站 Nginx 校验
源站安全组只允许 CloudFront managed prefix list 或 CloudFront 回源 IP 段
```

### 验证

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://mirror.example.com/v2/library/alpine/manifests/3.20
docker pull alpine:3.20
```

查看：

```text
X-Cache: Miss from cloudfront / Hit from cloudfront
Age
Via
```

<a id="cloudflare"></a>
## 八、Cloudflare 配置

Cloudflare 适合全球入口和安全能力统一管理。中国大陆访问效果取决于套餐、网络路径和是否使用中国网络合作方案。

### DNS

```text
Cloudflare -> Websites -> 选择域名 -> DNS
```

添加：

```text
Type：A 或 CNAME
Name：mirror
Target：203.0.113.10 或 mirror-origin.example.com
Proxy status：Proxied
```

注意：如果源站是 HTTP `5000`，Cloudflare 默认代理端口不一定覆盖 `5000`。更推荐模式 B：让源站提供 HTTPS `443`，Cloudflare 回源到 `443`。如果必须用非标准端口，请先确认当前套餐和端口支持情况。

### SSL/TLS

```text
SSL/TLS mode：Full (strict)
Edge Certificates：开启 Always Use HTTPS
Minimum TLS Version：TLS 1.2
Origin certificate：使用公网可信证书或 Cloudflare Origin CA
```

不要使用 Flexible 模式，避免客户端 HTTPS、源站 HTTP 之间出现协议和重定向问题。

### Cache Rules

创建规则，顺序从具体到通用。

规则 1：blobs 长缓存

```text
If incoming requests match:
  URI Path contains "/blobs/"
  URI Path starts with "/v2/"
Then:
  Cache eligibility: Eligible for cache
  Edge TTL: 7-30 days
  Browser TTL: Respect origin or short
```

规则 2：manifests 不缓存或短缓存

```text
If incoming requests match:
  URI Path contains "/manifests/"
  URI Path starts with "/v2/"
Then:
  Cache eligibility: Bypass cache
```

如果你明确要缓存 manifests：

```text
Edge TTL: 60-600 seconds
Custom cache key: include Accept header if your plan supports it
```

规则 3：其他 `/v2/`

```text
If URI Path starts with "/v2/"
Then:
  Bypass cache 或 Edge TTL 10-60 seconds
```

### WAF Skip Rule

```text
Security -> WAF -> Custom rules / Skip rules
```

对路径：

```text
URI Path starts with "/v2/"
```

跳过：

```text
Managed Challenge
JS Challenge
Browser Integrity Check
Bot Fight Mode
CAPTCHA
```

仍可保留：

```text
DDoS 防护
基础速率限制
IP 黑名单
```

### Origin Rules / Transform Rules

如果做 Header 鉴权，给回源请求加：

```text
X-Origin-Auth: replace-with-random-origin-secret
```

也可以使用：

```text
Authenticated Origin Pulls
```

源站只接受 Cloudflare 认证过的回源请求。

### 验证

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI https://mirror.example.com/v2/library/alpine/manifests/3.20
docker pull alpine:3.20
```

查看：

```text
CF-Cache-Status
cf-ray
Age
```

预期：

- `/v2/*/blobs/*` 首次 `MISS`，后续可能 `HIT`。
- `/v2/*/manifests/*` 如果设置 Bypass，应该一直 `BYPASS` 或类似状态。

## 九、客户端配置

CDN 配好后，Docker 客户端只配置 HTTPS 域名：

```json
{
  "registry-mirrors": [
    "https://mirror.example.com"
  ]
}
```

重启 Docker：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
docker info | sed -n '/Registry Mirrors/,+8p'
docker pull alpine:3.20
```

containerd、k3s、RKE2 详见 [客户端接入手册](client-usage.md)。

## 十、上线检查清单

上线前逐项确认：

- [ ] 选择了下载加速、大文件下载、全站加速或动静混合，不是纯动态加速。
- [ ] `mirror.example.com` 已 CNAME 到 CDN。
- [ ] CDN 客户端 HTTPS 可用。
- [ ] 源站回源没有指向 `mirror.example.com` 自己。
- [ ] `/v2/*/blobs/*` 长缓存已配置。
- [ ] `/v2/*/manifests/*` 不缓存或短缓存已配置。
- [ ] Range 回源/分片回源已开启或确认支持。
- [ ] WAF 对 `/v2/` 跳过 JS Challenge、验证码、浏览器挑战。
- [ ] 源站安全组只允许 CDN 回源 IP 段或启用了回源鉴权。
- [ ] 国内 Docker 节点 `docker pull alpine:3.20` 成功。
- [ ] 源站 `logs/nginx/access.log` 能看到 CDN 回源请求。
- [ ] CDN 日志或响应头能看到 blobs 的缓存命中。

## 十一、常见问题

### 选动态加速为什么不合适？

动态加速主要优化链路和回源，不一定缓存大文件。Docker 镜像加速最有价值的是缓存 `/v2/*/blobs/*` 镜像层，所以下载加速或动静混合更合适。

### CDN 回源 5000 不通怎么办？

检查：

```text
CDN 是否支持自定义回源端口 5000
源站安全组是否允许 CDN 回源 IP 访问 TCP 5000
源站 PROXY_BIND_ADDR 是否为 0.0.0.0
```

如果厂商不支持 `5000` 回源，改用源站 HTTPS `443`。

### Docker pull 报 403/验证码/HTML 页面

通常是 WAF 或 Bot 防护拦截了 `/v2/`。对 `/v2/` 路径关闭验证码、JS Challenge、浏览器校验，并确认返回的是 Registry 协议响应，不是 HTML。

### manifest 被错误缓存导致 tag 不更新

把 `/v2/*/manifests/*` 改成不缓存，或短缓存 60 秒。如果必须缓存，缓存键要包含 `Accept` 请求头。

### blobs 缓存不命中

检查：

```text
CDN 是否把 Authorization、Range 等请求头导致缓存键过度碎片化
是否缓存了 302/401/403 等非 blob 正文响应
是否开启了 Range 回源
源站是否返回可缓存的 200/206 响应
```

## 十二、参考文档

- Docker Hub mirror：https://docs.docker.com/docker-hub/image-library/mirror/
- Docker daemon registry mirrors：https://docs.docker.com/reference/cli/dockerd/
- AWS CloudFront custom origins：https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistS3AndCustomOrigins.html
- AWS CloudFront allowed methods：https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistValuesCacheBehavior.html
- AWS CloudFront custom origin headers：https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html
- Cloudflare Cache Rules：https://developers.cloudflare.com/cache/how-to/cache-rules/
- Cloudflare Authenticated Origin Pulls：https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/
