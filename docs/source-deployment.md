# 源站部署手册

本文说明如何按当前仓库配置把 Docker Image Proxy 部署到海外源站 `/data/docker-image-proxy/`，并为 CDN 或受控客户端提供入口。

## 一、部署前准备

服务器要求：

- Linux x86_64。
- 已安装 Docker Engine 和 Docker Compose v2。
- 能访问 Docker Hub。
- 预留 `/data/docker-image-proxy/` 作为部署和持久化目录。
- 准备一个专用 Docker Hub 账号和 Access Token。

模拟值约定：

```text
源站公网 IP：203.0.113.10
加速域名：mirror.example.com
源站域名：mirror-origin.example.com
Docker Hub 用户名：replace-with-dockerhub-username
Docker Hub token：replace-with-dockerhub-access-token
回源鉴权密钥：replace-with-random-origin-secret
```

上线前必须替换为自己的真实值，不要提交真实 IP、token、回源密钥、`.env` 或 SSH 信息。

## 二、目录结构

部署目录固定为：

```bash
/data/docker-image-proxy/
```

目标结构：

```text
/data/docker-image-proxy/
├── docker-compose.yml
├── .env
├── .env.example
├── config/registry/config.yml
├── nginx/nginx.conf
├── data/registry/
├── logs/nginx/
└── scripts/
```

所有持久化数据都留在这个目录下，便于备份、迁移和排障。

## 三、复制部署包

在服务器上执行：

```bash
mkdir -p /data/docker-image-proxy
cd /data/docker-image-proxy
```

把仓库 `deploy/` 目录中的文件同步到 `/data/docker-image-proxy/`，然后生成 `.env`：

```bash
cp .env.example .env
sed -i "s/replace-with-64-hex-chars/$(openssl rand -hex 32)/" .env
```

编辑 `.env`，填写 Docker Hub 上游认证：

```ini
REGISTRY_PROXY_USERNAME=replace-with-dockerhub-username
REGISTRY_PROXY_PASSWORD=replace-with-dockerhub-access-token
```

说明：

- 这两个值是生产必填项。
- `REGISTRY_PROXY_PASSWORD` 使用 Docker Hub Access Token。
- 不要使用有大量私有镜像权限的个人主账号 token。

## 四、启动服务

推荐使用内置脚本：

```bash
chmod +x ./scripts/install-or-update.sh
./scripts/install-or-update.sh
```

脚本会做这些事：

- 创建 `data/registry`、`logs/nginx` 等目录。
- 自动生成或检查 `REGISTRY_HTTP_SECRET`。
- 检查 Docker Hub 用户名和 Access Token，未填写时直接退出。
- 拉取固定 tag + digest 的镜像。
- 启动 Compose 服务。
- 执行真实 `/v2/`、manifest、`docker pull` 验证。

也可以手动启动：

```bash
docker compose pull
docker compose up -d
docker compose ps
./scripts/validate.sh
```

## 五、默认入口

默认 `.env`：

```ini
PROXY_BIND_ADDR=127.0.0.1
PROXY_HTTP_PORT=5000
```

也就是只监听本机：

```text
127.0.0.1:5000
```

这是安全默认值。此时只能在源站本机验证：

```bash
curl -fsSI http://127.0.0.1:5000/v2/
docker pull 127.0.0.1:5000/library/alpine:3.20
```

## 六、发布给 CDN 的两种入口

<a id="mode-a-cdn-http-5000"></a>
### 模式 A：CDN 回源 HTTP `5000`

适合不复用源站已有 Nginx，只使用仓库内置 Compose 的场景。

前提：

- CDN 支持自定义回源端口 `5000`。
- 云安全组先限制 TCP `5000` 只允许 CDN 回源 IP 段和临时测试 IP。
- 客户端只访问 `https://mirror.example.com`，不直接访问源站 HTTP。

源站调整：

```bash
cd /data/docker-image-proxy
cp .env .env.bak.$(date +%F-%H%M%S)
sed -i 's/^PROXY_BIND_ADDR=.*/PROXY_BIND_ADDR=0.0.0.0/' .env
sed -i 's/^PROXY_HTTP_PORT=.*/PROXY_HTTP_PORT=5000/' .env
docker compose up -d
ss -lntp | grep ':5000'
curl -fsSI http://127.0.0.1:5000/v2/
```

安全组示例：

```text
入方向 TCP 5000:
  allow CDN 回源 IP 段
  allow 运维或临时测试公网 IP
  deny 0.0.0.0/0
```

<a id="mode-b-cdn-https-443"></a>
### 模式 B：CDN 回源 HTTPS `443`

更标准的生产形态。

前提：

- 源站有独立 HTTPS 网关，例如 Nginx、Caddy、SLB 或云负载均衡。
- 网关转发到 `http://127.0.0.1:5000`。
- CDN 使用 HTTPS 回源。
- 源站只允许 CDN 回源 IP 或启用回源鉴权。

Nginx 网关示例：

```nginx
server {
  listen 443 ssl http2;
  server_name mirror-origin.example.com;

  ssl_certificate     /etc/nginx/ssl/fullchain.pem;
  ssl_certificate_key /etc/nginx/ssl/privkey.pem;

  client_max_body_size 0;
  proxy_read_timeout 900s;
  proxy_send_timeout 900s;
  proxy_request_buffering off;
  proxy_buffering off;

  location /v2/ {
    proxy_pass http://127.0.0.1:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Range $http_range;
    proxy_set_header If-Range $http_if_range;
  }
}
```

如果启用 CDN 回源 Header 鉴权，校验逻辑应放在这个源站网关里。完整安全建议见 [安全加固手册](security-hardening.md)。

<a id="direct-http-test"></a>
## 七、直连内测

HTTP `5000` 直连只用于短期验证：

```text
http://203.0.113.10:5000
```

必须同时满足：

- 云安全组只允许指定国内服务器公网 IP。
- Docker Engine 配置 `insecure-registries`。
- containerd/k3s 明确配置 HTTP endpoint。
- 验证结束后关闭公网直连或切到 CDN HTTPS。

Docker 内测配置示例：

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

## 八、源站验证

部署后执行：

```bash
cd /data/docker-image-proxy
docker compose ps
./scripts/validate.sh
curl -fsSI http://127.0.0.1:5000/v2/
```

检查日志：

```bash
tail -f logs/nginx/access.log
docker compose logs -f nginx registry
```

如果要验证缓存写入：

```bash
du -sh data/registry
docker pull 127.0.0.1:5000/library/alpine:3.20
du -sh data/registry
```

## 九、部署后下一步

1. 按 [CDN 加速配置手册](cdn-acceleration.md) 配置 `mirror.example.com`。
2. 按 [安全加固手册](security-hardening.md) 限制源站和 WAF。
3. 按 [验证手册](validation.md) 做源站、CDN、客户端端到端验证。
4. 按 [客户端接入手册](client-usage.md) 配置国内 Docker/Kubernetes 节点。
