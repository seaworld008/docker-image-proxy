# 域名、CDN 和安全入口配置手册

本文说明如何把 `/data/docker-image-proxy/` 上的 mirror 发布成国内 Docker/Kubernetes 节点可用的稳定入口，并避免源站被直连滥用。

## 推荐架构

```text
国内 Docker/Kubernetes 节点
        |
        | HTTPS
        v
mirror.example.com  CDN/WAF/边缘缓存
        |
        | 回源 HTTP:5000 或 HTTPS:443
        v
硅谷源站 /data/docker-image-proxy/
        |
        v
registry:3.1.1 -> Docker Hub
```

推荐客户端只使用 CDN HTTPS 域名：

```text
https://mirror.example.com
```

当前部署包默认只监听 `127.0.0.1:5000`，这是安全默认值。要给国内服务器使用，必须先选择一种受控入口。

## 入口模式选择

### 模式 A：CDN HTTPS + 源站 HTTP:5000 回源

适合当前独立 Compose 部署，不需要复用服务器已有的 80/443 Nginx。

要求：

- CDN 支持自定义回源端口 `5000`。
- 源站安全组只允许 CDN 回源 IP 段访问 TCP `5000`。
- 客户端访问 CDN HTTPS 域名，不直接访问源站 HTTP。

优点：改动少，不占用源站 80/443。

注意：如果 CDN 不支持自定义回源端口，改用模式 B。

### 模式 B：CDN HTTPS + 源站 HTTPS:443 回源

更标准的生产形态。

要求：

- 源站有 HTTPS 入口，例如独立 Nginx/Caddy/SLB/已有网关。
- CDN 使用 HTTPS 回源，证书可信或使用厂商源站证书。
- 源站只允许 CDN 回源 IP 段或启用 Authenticated Origin Pull / 回源 Header 鉴权。

优点：端到端 HTTPS，更符合多数 CDN 默认能力。

### 模式 C：HTTP:5000 直连内测

仅用于短期验证。

要求：

- 源站 `PROXY_BIND_ADDR=0.0.0.0`。
- 云安全组只允许指定国内 Docker 服务器公网 IP 访问 TCP `5000`。
- 客户端 Docker/containerd 显式配置 HTTP/insecure。

不建议把 HTTP mirror 对全网开放。

## 源站开放 HTTP:5000

在开放前先配置云安全组，至少限制：

```text
入方向 TCP 5000:
  允许 CDN 回源 IP 段
  允许临时测试的国内服务器公网 IP
  拒绝 0.0.0.0/0
```

然后在硅谷源站执行：

```bash
cd /data/docker-image-proxy
cp .env .env.bak.$(date +%F-%H%M%S)

sed -i 's/^PROXY_BIND_ADDR=.*/PROXY_BIND_ADDR=0.0.0.0/' .env
sed -i 's/^PROXY_HTTP_PORT=.*/PROXY_HTTP_PORT=5000/' .env

docker compose up -d
ss -lntp | grep ':5000'
curl -fsSI http://127.0.0.1:5000/v2/
```

从一台已放行的国内服务器验证。示例源站 IP 为 `203.0.113.10`，上线前请替换成自己的源站公网 IP：

```bash
curl -fsSI http://203.0.113.10:5000/v2/
```

## DNS 配置

推荐准备两个名字：

```text
mirror.example.com         # 给客户端使用的 CDN 加速域名
mirror-origin.example.com  # 可选，源站域名，仅给 CDN 回源使用
```

规则：

- `mirror.example.com` 指向 CDN 厂商分配的 CNAME。
- Cloudflare 场景可用 A/AAAA 指向源站并开启代理。
- CDN 回源不要指向 `mirror.example.com` 自己，避免回源环。
- 如果使用 `mirror-origin.example.com`，该域名应只给 CDN 回源使用，源站安全组仍要限制来源。

## CDN 通用配置

### 基础参数

```text
加速域名：mirror.example.com
业务类型：下载加速 / 全站加速 / 动静混合
客户端协议：HTTPS
HTTP 跳转 HTTPS：开启
回源协议：按源站能力选择 HTTP 或 HTTPS
回源地址：源站 IP 或 mirror-origin.example.com
回源 Host：mirror.example.com 或源站 Nginx 实际 server_name
允许方法：GET、HEAD、OPTIONS
Range 请求：开启
```

Docker Registry 客户端依赖 `GET`、`HEAD`、`Range` 和标准响应头。不要对 `/v2/` 开启 JS Challenge、验证码、浏览器校验等交互式防护。

### 缓存规则

推荐规则：

```text
/v2/                         不缓存或 10-60 秒
/v2/*/manifests/*            不缓存，或 60-600 秒
/v2/*/blobs/*                7-30 天
其他路径                     不缓存或短缓存
```

原因：

- `blobs` 使用 digest 路径，内容不可变，适合长缓存。
- `manifests` 可能是 tag，内容可能变化；并且 manifest 响应会受 `Accept` 头影响。

如果 CDN 支持自定义缓存键，建议对 `/v2/*/manifests/*` 把 `Accept` 请求头纳入缓存键。否则 manifests 建议不缓存或只做很短缓存。

不要缓存 4xx/5xx 错误响应，避免短时上游错误被 CDN 放大。

### 响应头与回源头

建议保留或透传：

```text
Docker-Distribution-API-Version
Content-Type
Content-Length
Accept-Ranges
Range
Authorization
```

如果 CDN 支持请求头白名单，至少放行：

```text
Accept
Authorization
Range
If-Range
User-Agent
```

## 安全配置

### 源站安全组

生产推荐：

```text
TCP 5000 或 TCP 443:
  allow CDN 回源 IP 段
  allow 运维堡垒机/监控 IP
  deny 0.0.0.0/0
```

优先在云安全组配置来源限制。本机防火墙可以作为补充，但不要只依赖容器端口暴露后的本机规则。

### CDN 回源鉴权

可选但推荐，尤其是源站无法严格维护 CDN IP 段时。

方式一：CDN 回源添加自定义 Header，例如：

```text
X-Origin-Auth: <随机长密钥>
```

源站前置 Nginx 校验：

```nginx
if ($http_x_origin_auth != "<随机长密钥>") {
  return 403;
}
```

注意：当前独立 Compose 内置 Nginx 默认没有启用 Header 鉴权。若采用此方式，需要把校验放在源站前置网关，或定制 `deploy/nginx/nginx.conf` 后再部署。

方式二：云厂商源站认证能力：

- Cloudflare：Authenticated Origin Pulls
- 阿里云/腾讯云/华为云：回源鉴权、自定义回源 Header 或访问控制

### WAF 放行规则

对 `/v2/` 路径建议：

```text
放行方法：GET、HEAD、OPTIONS
放行请求头：Accept、Authorization、Range、If-Range
关闭：JS Challenge、验证码、浏览器完整性校验、机器人挑战
允许：大文件下载、Range、长连接
```

### 限流建议

入口层可对 manifest 做轻量限流，对 blob 下载保持宽松。

```text
/v2/*/manifests/*   可按 IP 限制请求速率
/v2/*/blobs/*       不建议强限流，可按带宽限速
```

如果限制过严，Kubernetes 批量拉镜像时容易出现 `ImagePullBackOff` 或超时。

### 不建议的做法

- 不要把未鉴权 HTTP mirror 对公网开放。
- 不要在 CDN/WAF 对 `/v2/` 开启验证码或 JS Challenge。
- 不要让 CDN 回源到同一个加速域名。
- 不要把 Docker Hub 个人主账号 token 写入公共 mirror；如需上游认证，使用专用低权限账号/token。
- 不要默认给 transparent mirror 加 Basic Auth，Docker daemon 的 `registry-mirrors` 场景通常不适合依赖交互式客户端认证。

## 阿里云 CDN 配置要点

控制台路径可能随版本变化，按以下参数对应填写：

```text
域名管理 -> 添加域名
  加速域名：mirror.example.com
  业务类型：下载加速或全站加速

源站信息
  源站类型：源站 IP 或源站域名
  源站地址：203.0.113.10 或 mirror-origin.example.com
  回源协议：HTTP:5000 或 HTTPS:443
  回源 Host：mirror.example.com

HTTPS 配置
  开启 HTTPS
  HTTP 自动跳转 HTTPS

缓存配置
  /v2/*/blobs/*      7-30 天
  /v2/*/manifests/*  不缓存或 60-600 秒

高级配置
  Range 回源：开启
  WAF/访问控制：放行 /v2/
  源站保护：限制源站只允许 CDN 回源 IP
```

## 腾讯云 CDN 配置要点

```text
域名管理 -> 添加域名
  加速域名：mirror.example.com
  业务类型：下载加速或动静加速

源站配置
  源站类型：自有源
  源站地址：203.0.113.10 或 mirror-origin.example.com
  回源协议：HTTP:5000 或 HTTPS:443
  回源 Host：mirror.example.com

HTTPS 配置
  开启 HTTPS
  强制 HTTPS

缓存规则
  /v2/*/blobs/*      7-30 天
  /v2/*/manifests/*  不缓存或 60-600 秒

访问控制
  Range 回源：开启
  WAF：放行 /v2/
```

## 华为云 CDN 配置要点

```text
域名管理 -> 添加域名
  加速域名：mirror.example.com
  业务类型：下载加速

源站设置
  源站类型：源站 IP 或源站域名
  源站地址：203.0.113.10 或 mirror-origin.example.com
  回源协议：HTTP:5000 或 HTTPS:443
  Host 头：mirror.example.com

HTTPS 配置
  上传证书或使用托管证书
  强制 HTTPS

缓存规则
  /v2/*/blobs/*      7-30 天
  /v2/*/manifests/*  不缓存或 60-600 秒

高级设置
  Range：开启
  WAF：放行 /v2/
```

## Cloudflare 配置要点

```text
DNS
  mirror.example.com -> 源站 IP
  Proxy status：Proxied

SSL/TLS
  推荐 Full (strict)
  源站使用可信证书或 Cloudflare Origin CA

Cache Rules
  */v2/*/blobs/*      Cache eligible，7-30 天
  */v2/*/manifests/*  Bypass cache 或 60-600 秒

WAF
  Skip rule for /v2/*
  跳过 JS Challenge、Managed Challenge、Bot Fight 对 /v2/ 的影响

Origin protection
  Authenticated Origin Pulls 或源站安全组只放行 Cloudflare IP 段
```

Cloudflare 不同套餐对大文件、缓存行为和规则数量可能有限制，生产前用真实镜像做完整拉取验证。

## CDN 上线验证

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

源站同步观察：

```bash
cd /data/docker-image-proxy
tail -f logs/nginx/access.log
docker compose logs -f nginx registry
```

CDN 命中验证：

```bash
curl -fsSI https://mirror.example.com/v2/library/alpine/manifests/3.20
```

查看厂商返回的命中头，例如 `X-Cache`、`CF-Cache-Status` 或类似字段。首次 MISS、后续 HIT 是正常预期；manifests 如果配置为不缓存则可能一直 BYPASS。

## 回滚

如果 CDN 入口异常：

1. 暂停国内服务器使用该 mirror，移除或注释客户端 `registry-mirrors`。
2. 恢复源站本机监听：

```bash
cd /data/docker-image-proxy
sed -i 's/^PROXY_BIND_ADDR=.*/PROXY_BIND_ADDR=127.0.0.1/' .env
docker compose up -d
```

3. 关闭源站安全组中临时开放的 TCP `5000` 公网入口。
