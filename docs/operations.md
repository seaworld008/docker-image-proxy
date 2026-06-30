# 日常运维手册

本文覆盖 Docker Image Proxy 的安装、验证、升级、回滚、日志、备份、缓存清理和常见排错。

## 目录约定

生产部署目录固定为：

```bash
/data/docker-image-proxy/
```

目录结构：

```text
/data/docker-image-proxy/
├── docker-compose.yml
├── docker-compose.with-auth.yml
├── .env
├── config/registry/config.yml
├── nginx/nginx.conf
├── data/registry/
├── logs/nginx/
└── scripts/
```

`.env`、`data/registry/`、`logs/nginx/` 不应提交到仓库。

## 安装或更新部署包

```bash
mkdir -p /data/docker-image-proxy
cd /data/docker-image-proxy
```

把仓库 `deploy/` 中的文件同步到该目录，然后执行：

```bash
chmod +x ./scripts/install-or-update.sh
./scripts/install-or-update.sh
```

脚本会：

- 创建必要目录。
- 生成或检查 `REGISTRY_HTTP_SECRET`。
- 拉取固定 digest 的镜像。
- 启动 Compose 服务。
- 执行健康检查和真实 `docker pull` 验证。

## 启用 Docker Hub 上游认证

仅使用专用低权限 Docker Hub 账号/token。不要使用可访问私有镜像的个人主账号，除非 mirror 已做好访问控制。

编辑 `.env`：

```ini
REGISTRY_PROXY_USERNAME=your-dockerhub-user
REGISTRY_PROXY_PASSWORD=replace-with-your-token
```

启动认证覆盖文件：

```bash
docker compose -f docker-compose.yml -f docker-compose.with-auth.yml up -d
./scripts/validate.sh
```

## 运行状态检查

```bash
cd /data/docker-image-proxy
docker compose ps
docker compose logs --tail=100 nginx registry
curl -fsSI http://127.0.0.1:5000/v2/
./scripts/validate.sh
```

检查端口监听：

```bash
ss -lntp | grep ':5000'
```

默认应该是：

```text
127.0.0.1:5000
```

若看到 `0.0.0.0:5000`，请确认云安全组已经限制来源 IP。

## 发布给国内服务器

生产推荐：

1. 按 [CDN 和安全入口手册](cdn-and-security.md) 发布 `https://mirror.example.com`。
2. 按 [客户端接入手册](client-usage.md) 配置国内 Docker/Kubernetes 节点。
3. 从国内节点执行真实拉取：

```bash
docker pull alpine:3.20
crictl pull docker.io/library/alpine:3.20
```

临时内测才开放 HTTP `5000`：

```bash
cd /data/docker-image-proxy
cp .env .env.bak.$(date +%F-%H%M%S)
sed -i 's/^PROXY_BIND_ADDR=.*/PROXY_BIND_ADDR=0.0.0.0/' .env
sed -i 's/^PROXY_HTTP_PORT=.*/PROXY_HTTP_PORT=5000/' .env
docker compose up -d
```

开放前必须先在云安全组限制来源 IP。

## 升级流程

升级前检查：

```bash
cd /data/docker-image-proxy
docker compose ps
du -sh data/registry logs/nginx
cp .env .env.bak.$(date +%F-%H%M%S)
cp docker-compose.yml docker-compose.yml.bak.$(date +%F-%H%M%S)
```

同步新版部署包后：

```bash
docker compose pull
docker compose up -d
./scripts/validate.sh
```

观察日志：

```bash
docker compose logs -f --tail=100 nginx registry
```

升级原则：

- 镜像版本和 digest 必须同时更新。
- 先在测试节点验证 `docker pull` 和 `crictl pull`。
- 不要在同一次变更中同时改镜像版本、入口模式、CDN 缓存规则和客户端配置。

## 回滚流程

如果升级后拉取失败：

```bash
cd /data/docker-image-proxy
docker compose down
cp docker-compose.yml.bak.<timestamp> docker-compose.yml
docker compose up -d
./scripts/validate.sh
```

如果是入口配置问题，先恢复本机监听：

```bash
sed -i 's/^PROXY_BIND_ADDR=.*/PROXY_BIND_ADDR=127.0.0.1/' .env
docker compose up -d
```

然后暂停 CDN 切换或回滚客户端 `registry-mirrors`。

## 日志

Nginx 访问日志：

```bash
tail -f /data/docker-image-proxy/logs/nginx/access.log
```

容器日志：

```bash
cd /data/docker-image-proxy
docker compose logs -f nginx registry
```

常看字段：

- `status`：HTTP 状态码。
- `request_time`：请求总耗时。
- `upstream_response_time`：registry 上游响应耗时。
- `Range` 下载失败时检查 CDN/WAF 是否改写请求头。

## 备份

建议备份：

```text
.env
docker-compose.yml
docker-compose.with-auth.yml
config/registry/config.yml
nginx/nginx.conf
```

缓存目录 `data/registry/` 可以备份，但通常可由 Docker Hub 重新回源生成。若磁盘和时间成本较高，可只备份配置，不备份缓存。

示例：

```bash
cd /data
tar czf docker-image-proxy-config-$(date +%F).tgz \
  docker-image-proxy/.env \
  docker-image-proxy/docker-compose.yml \
  docker-image-proxy/docker-compose.with-auth.yml \
  docker-image-proxy/config \
  docker-image-proxy/nginx
```

备份文件如果包含 `.env`，必须按密钥文件管理，不要上传公开仓库。

## 缓存容量治理

查看容量：

```bash
du -sh /data/docker-image-proxy/data/registry
docker system df
```

Registry GC 需要停止服务后执行：

```bash
cd /data/docker-image-proxy
docker compose down
docker run --rm \
  -v /data/docker-image-proxy/data/registry:/var/lib/registry \
  -v /data/docker-image-proxy/config/registry/config.yml:/etc/distribution/config.yml:ro \
  registry:3.1.1@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33 \
  garbage-collect /etc/distribution/config.yml
docker compose up -d
./scripts/validate.sh
```

不要直接手工删除 `data/registry/docker/registry/v2/` 内部目录。

## 常见排错

### `/v2/` 不通

```bash
cd /data/docker-image-proxy
docker compose ps
docker compose logs --tail=100 nginx registry
curl -v http://127.0.0.1:5000/v2/
```

检查 `.env` 中 `PROXY_BIND_ADDR` 和 `PROXY_HTTP_PORT`。

### manifest 能访问但 `docker pull` 失败

检查 Nginx/CDN 是否允许 Range：

```bash
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  http://127.0.0.1:5000/v2/library/alpine/manifests/3.20
```

再从客户端用 daemon mirror 拉取：

```bash
docker pull alpine:3.20
```

### 国内节点没有走 mirror

Docker：

```bash
docker info | sed -n '/Registry Mirrors/,+8p'
systemctl cat docker
```

containerd：

```bash
containerd --version
grep -n 'config_path' /etc/containerd/config.toml
cat /etc/containerd/certs.d/docker.io/hosts.toml
crictl pull docker.io/library/alpine:3.20
```

### Docker Hub 429 或回源失败

考虑启用 Docker Hub 上游认证：

```bash
docker compose -f docker-compose.yml -f docker-compose.with-auth.yml up -d
```

同时检查是否有大量未授权客户端滥用 mirror。
