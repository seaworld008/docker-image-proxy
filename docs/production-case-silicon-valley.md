# 硅谷源站真实部署案例（模拟数据版）

本文记录一次真实部署验证过程，供后续复用。公网 IP、SSH 端口、密钥路径、私有 token 等敏感信息均替换为模拟数据。上线前必须替换为自己的真实值，真实敏感信息不要提交到仓库。

本文使用的模拟值：

```text
源站公网 IP：203.0.113.10
SSH 端口：10022
SSH 私钥路径：/path/to/id_ed25519
CDN 域名：mirror.example.com
源站域名：mirror-origin.example.com
Docker Hub token：replace-with-your-token
```

## 部署目标

```text
部署目录：/data/docker-image-proxy/
部署方式：独立 Docker Compose
入口模式：默认本机监听 127.0.0.1:5000
用途：Docker Hub pull-through cache
```

本案例没有复用服务器上已有的 Nginx 网关，mirror 使用仓库 `deploy/` 包里的独立 Nginx 容器。

## 服务器环境

```text
区域：美国硅谷云主机
公网 IP：203.0.113.10
SSH：ssh -i /path/to/id_ed25519 -p 10022 root@203.0.113.10
操作系统：Linux x86_64
Docker Engine：29.0.x
Docker Compose：v2.40.x
```

安全原则：

- 私钥不上传仓库。
- `.env` 不上传仓库。
- Docker Hub token 不上传仓库。
- 真实公网 IP、SSH 端口、私钥路径不写入公开文档；公开文档只使用上述模拟值。

## 部署版本

部署包固定使用：

```text
registry:3.1.1@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33
nginx:1.30.3-alpine@sha256:0d3b80406a13a767339fbe2f41406d6c7da727ab89cf8fae399e81f780f814d1
```

## 部署目录结构

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

所有持久化数据、配置和日志都集中在 `/data/docker-image-proxy/` 下，便于备份、迁移和容量治理。

## 实际部署命令

```bash
cd /data/docker-image-proxy
./scripts/install-or-update.sh
```

脚本完成：

- 检查 `.env`。
- 生成 `REGISTRY_HTTP_SECRET`。
- 拉取固定版本镜像。
- 启动 `registry` 与 `nginx`。
- 执行 `/v2/`、manifest、真实 `docker pull` 验证。

## 运行状态

部署完成后容器状态：

```text
docker-image-proxy-nginx     healthy  127.0.0.1:5000->80/tcp
docker-image-proxy-registry  up       internal 5000/tcp
```

源站默认只监听本机：

```text
127.0.0.1:5000
```

这避免了未鉴权 mirror 直接暴露到公网。国内服务器需要使用时，应先按 `docs/cdn-and-security.md` 配置 CDN 或受控直连入口。

## 真实验证结果

源站本机验证：

```bash
curl -fsSI http://127.0.0.1:5000/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  http://127.0.0.1:5000/v2/library/alpine/manifests/3.20
docker pull 127.0.0.1:5000/library/alpine:3.20
```

结果：

```text
/v2/ 返回 200
library/alpine:3.20 manifest 返回 200
docker pull 127.0.0.1:5000/library/alpine:3.20 成功
缓存写入 /data/docker-image-proxy/data/registry/
```

一次验证中 `library/alpine:3.20` manifest digest：

```text
sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
```

该 digest 仅作为当次验证记录，后续以实时 manifest 为准。

## 国内服务器接入方式

推荐路径：

1. 使用 CDN 发布 `https://mirror.example.com`。
2. 源站安全组只允许 CDN 回源 IP 段访问。
3. 国内 Docker/Kubernetes 节点按 `docs/client-usage.md` 配置。
4. 用 `docker pull alpine:3.20` 或 `crictl pull docker.io/library/alpine:3.20` 验证。

临时内测路径：

1. 源站改为监听 `0.0.0.0:5000`。
2. 云安全组只允许指定国内服务器公网 IP 访问 TCP `5000`。
3. 客户端配置 HTTP mirror，例如 `http://203.0.113.10:5000`，并开启对应 insecure 配置。
4. 验证完成后关闭公网直连或切换到 CDN HTTPS。

## 运维检查项

```bash
cd /data/docker-image-proxy
docker compose ps
docker compose logs --tail=100 nginx registry
du -sh data/registry logs/nginx
./scripts/validate.sh
```

容量治理：

- 定期检查 `/data/docker-image-proxy/data/registry/`。
- 大规模清理前先停服务，再执行 registry garbage-collect。
- 不要直接删除 registry 内部目录，避免缓存索引不一致。

## 已去敏信息清单

以下信息不得写入公开仓库：

- 真实公网 IP。
- SSH 私钥路径和私钥内容。
- SSH 登录端口。
- Docker Hub 用户名和 token。
- `.env` 里的 `REGISTRY_HTTP_SECRET`。
- 云厂商控制台账号、AccessKey、SecretKey。
