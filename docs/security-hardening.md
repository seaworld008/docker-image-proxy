# 安全加固手册

本文说明 Docker Image Proxy 的源站保护、Docker Hub 上游认证、CDN/WAF 放行、回源鉴权、限流、密钥管理和排障安全边界。

## 一、安全目标

生产环境至少达到以下目标：

- 源站端口不对公网裸奔。
- 只有 CDN、堡垒机、监控或明确测试 IP 能访问源站入口。
- Docker Hub 回源使用专用低权限账号和 Access Token。
- WAF 不破坏 Docker Registry `/v2/` 协议。
- 不提交真实 IP、SSH 信息、token、`.env`、证书私钥。

## 二、Docker Hub 上游认证

`.env` 必填：

```ini
REGISTRY_PROXY_USERNAME=replace-with-dockerhub-username
REGISTRY_PROXY_PASSWORD=replace-with-dockerhub-access-token
```

要求：

- 使用专用 Docker Hub 账号。
- 使用 Access Token，不使用个人主账号密码。
- 不要让该账号拥有不必要的私有镜像访问权限。
- `.env` 权限保持 `600`。

风险说明：

如果该账号可以访问私有镜像，并且 mirror 对外没有访问控制，mirror 使用者可能通过该 mirror 拉取该账号有权限访问的私有资源。

## 三、源站安全组

### CDN 回源模式

源站入方向只允许：

```text
TCP 5000 或 TCP 443:
  allow CDN 回源 IP 段
  allow 运维堡垒机 IP
  allow 监控 IP
  deny 0.0.0.0/0
```

安全组优先级高于系统防火墙。不要只依赖容器内 Nginx 拦截。

### HTTP 直连内测

只允许指定测试服务器公网 IP：

```text
TCP 5000:
  allow <国内测试服务器公网 IP>/32
  deny 0.0.0.0/0
```

验证结束后立即恢复：

```bash
cd /data/docker-image-proxy
sed -i 's/^PROXY_BIND_ADDR=.*/PROXY_BIND_ADDR=127.0.0.1/' .env
docker compose up -d
```

## 四、CDN 回源鉴权

推荐和安全组二选一或叠加：

| 方式 | 适用场景 |
| --- | --- |
| CDN 回源 IP 白名单 | CDN 回源 IP 段稳定且可维护 |
| 自定义回源 Header | 源站网关可校验 Header |
| Authenticated Origin Pulls | Cloudflare 场景，源站可校验证书 |

### 自定义 Header

CDN 回源添加：

```text
X-Origin-Auth: replace-with-random-origin-secret
```

源站 Nginx 校验：

```nginx
if ($http_x_origin_auth != "replace-with-random-origin-secret") {
  return 403;
}
```

仓库内置 Nginx 已提供可切换的 CDN 回源鉴权子配置：

```text
nginx/conf.d/default.conf           # 普通入口
nginx/conf.d/cdn-origin-auth.conf   # 校验 X-Origin-Auth
```

启用步骤：

```bash
cd /data/docker-image-proxy
cp .env .env.bak.$(date +%F-%H%M%S)
vi nginx/conf.d/cdn-origin-auth.conf
sed -i 's#^NGINX_SERVER_CONF=.*#NGINX_SERVER_CONF=./nginx/conf.d/cdn-origin-auth.conf#' .env
docker compose up -d
```

编辑 `nginx/conf.d/cdn-origin-auth.conf` 时，把 `replace-with-random-origin-secret` 替换为自己的真实随机长密钥，并在 CDN 回源 Header 中使用同一个值。

注意：

- `replace-with-random-origin-secret` 必须替换为随机长密钥。
- 不要把真实回源密钥提交到仓库。
- 如果用 `certbot` HTTP-01 验证证书，需要放行 `/.well-known/acme-challenge/`，或改用 DNS 验证。
- `cdn-origin-auth.conf` 只保护 `/v2/` 路径；`/healthz` 和容器内部 `127.0.0.1` 健康检查不需要 Header。
- 生产仍建议叠加安全组或防火墙，只允许 CDN 回源 IP 访问源站端口。

## 五、WAF 放行规则

对 `/v2/` 路径：

```text
允许方法：GET、HEAD、OPTIONS
允许请求头：Accept、Authorization、Range、If-Range、User-Agent
允许响应头：Docker-Distribution-API-Version、Content-Length、Accept-Ranges、ETag
允许大文件下载和 Range
```

跳过：

```text
JS Challenge
Managed Challenge
验证码
浏览器完整性检查
Bot Fight / 机器人挑战
需要 Cookie 的规则
```

保留：

```text
DDoS 防护
IP 黑名单
基础恶意流量规则
轻量速率限制
```

如果 Docker pull 返回 HTML、403、验证码页面，优先检查 WAF/Bot 规则。

## 六、限流策略

原则：

- 对 `/v2/*/manifests/*` 可以轻量限流。
- 对 `/v2/*/blobs/*` 不要强限流，否则大镜像层容易下载失败。
- Kubernetes 批量拉镜像时会并发访问，同一出口 IP 可能代表整批节点。

当前内置 Nginx 已对 manifests 做轻量限流：

```nginx
limit_req_zone $binary_remote_addr zone=manifest_rate:10m rate=20r/s;
limit_conn_zone $binary_remote_addr zone=addr_conn:10m;
```

如果部署在 CDN 后，优先在 CDN 边缘做速率控制，并确保不会误伤镜像层下载。

## 七、密钥和敏感信息

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

- 真实服务器 IP。
- 真实 SSH 端口。
- SSH 私钥路径和私钥内容。
- `.env`。
- Docker Hub 用户名、密码、Access Token。
- `REGISTRY_HTTP_SECRET`。
- CDN 回源密钥。
- 证书私钥。
- 云厂商 AccessKey/SecretKey。

提交前建议搜索：

```bash
rg -n "REGISTRY_HTTP_SECRET=|REGISTRY_PROXY_PASSWORD=|AKIA|ghp_|github_pat_|BEGIN .*PRIVATE KEY" .
```

## 八、日志和审计

源站日志：

```bash
cd /data/docker-image-proxy
tail -f logs/nginx/access.log
docker compose logs -f nginx registry
```

重点关注：

```text
大量 401/403/429
异常高频 manifests 请求
单 IP 大量并发 blobs
来自非 CDN IP 的源站访问
WAF 返回 HTML 或挑战页面
```

CDN 日志重点关注：

```text
命中率
回源流量
4xx/5xx
被 WAF 拦截的 /v2/ 请求
单 IP 或单地域异常拉取
```

## 九、应急处理

如果怀疑 mirror 被滥用：

1. 在 CDN 层临时限制来源 IP 或关闭加速域名。
2. 在源站安全组撤销公网临时开放。
3. 恢复 `PROXY_BIND_ADDR=127.0.0.1`。
4. 轮换 Docker Hub Access Token。
5. 检查 CDN 和源站访问日志。
6. 重新按 [验证手册](validation.md) 验证后再恢复服务。

如果 Docker Hub 429：

1. 确认 `.env` 填写了 Docker Hub 账号/token。
2. 确认 token 未过期或被撤销。
3. 检查是否有未授权客户端大量拉取。
4. 必要时加 CDN 限流、客户端白名单或拆分源站。
