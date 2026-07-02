# 验证手册

本文给出 Docker Image Proxy 从源站到 CDN，再到 Docker/Kubernetes 客户端的端到端验证步骤。

## 一、验证顺序

推荐按顺序验证：

1. 源站本机。
2. 源站对 CDN 回源入口。
3. CDN HTTPS 域名。
4. Docker 客户端。
5. containerd/Kubernetes 客户端。
6. CDN 缓存命中和源站日志。

不要跳过源站本机验证。否则 CDN 或客户端失败时很难判断问题在哪一层。

## 二、源站本机验证

```bash
cd /data/docker-image-proxy
docker compose ps
./scripts/validate.sh
```

手动验证：

```bash
curl -fsSI http://127.0.0.1:5000/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  http://127.0.0.1:5000/v2/library/alpine/manifests/3.20
docker pull 127.0.0.1:5000/library/alpine:3.20
```

预期：

```text
/v2/ 返回 200 或 Registry 协议可识别响应
manifest 返回 200
docker pull 成功
data/registry/ 有缓存写入
```

检查缓存目录：

```bash
du -sh data/registry
```

## 三、源站回源入口验证

如果 CDN 回源 HTTP `5000`：

```bash
curl -fsSI http://203.0.113.10:5000/v2/
```

如果 CDN 回源 HTTPS `443`：

```bash
curl -fsSI https://mirror-origin.example.com/v2/
```

注意：

- 上述命令应只从被安全组放行的机器执行。
- 如果公网任意 IP 都能访问源站入口，说明源站保护没有做好。

## 四、CDN 域名验证

从国内服务器执行：

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://mirror.example.com/v2/library/alpine/manifests/3.20
```

响应应是 Registry 协议响应，不应出现：

```text
HTML 页面
验证码页面
登录页
301/302 回源环
403 WAF Challenge
```

## 五、Docker 客户端验证

配置 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": [
    "https://mirror.example.com"
  ]
}
```

重启：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

验证：

```bash
docker info | sed -n '/Registry Mirrors/,+8p'
docker pull alpine:3.20
docker pull nginx:1.30.3-alpine
```

如果使用 HTTP 内测入口，还要确认：

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

## 六、containerd 验证

确认运行时：

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,RUNTIME:.status.nodeInfo.containerRuntimeVersion
```

containerd 节点验证：

```bash
sudo crictl pull docker.io/library/alpine:3.20
sudo crictl pull docker.io/library/nginx:1.30.3-alpine
```

如果需要检查 hosts 配置：

```bash
grep -n 'config_path' /etc/containerd/config.toml
cat /etc/containerd/certs.d/docker.io/hosts.toml
```

完整配置见 [客户端接入手册](client-usage.md)。

## 七、Kubernetes Pod 验证

创建临时 Pod：

```bash
kubectl run mirror-test \
  --image=docker.io/library/alpine:3.20 \
  --restart=Never \
  -- sleep 60
```

查看状态：

```bash
kubectl get pod mirror-test -o wide
kubectl describe pod mirror-test
```

清理：

```bash
kubectl delete pod mirror-test
```

如果出现 `ImagePullBackOff`，先在同节点执行：

```bash
sudo crictl pull docker.io/library/alpine:3.20
```

## 八、CDN 缓存命中验证

查看响应头：

```bash
curl -fsSI https://mirror.example.com/v2/library/alpine/manifests/3.20
```

常见命中头：

```text
CF-Cache-Status
X-Cache
Age
Via
```

更适合观察 blob 的缓存效果：

1. 先执行一次 `docker pull`。
2. 清理本地镜像或换一台客户端再拉取。
3. 查看 CDN 日志中的 `/blobs/sha256:` 请求命中状态。

预期：

- manifest 可能不缓存或短缓存。
- blob 首次 MISS，后续 HIT。
- 源站日志中的重复 blob 回源应减少。

## 九、源站日志验证

```bash
cd /data/docker-image-proxy
tail -f logs/nginx/access.log
docker compose logs -f nginx registry
```

关注：

```text
状态码 200/206 是否正常
是否存在大量 403/429/5xx
请求是否来自 CDN 回源 IP
Range 请求是否正常
```

## 十、常见失败定位

| 现象 | 优先检查 |
| --- | --- |
| `/v2/` 返回 HTML | CDN/WAF 返回了网页，不是 Registry 响应 |
| `docker pull` 403 | WAF、回源 Header、源站安全组 |
| `docker pull` 429 | Docker Hub 上游认证、滥用流量、限流策略 |
| manifest 正常但 blob 失败 | Range、回源超时、大文件限制、CDN 缓存规则 |
| Docker 未走 mirror | `docker info`、daemon.json、Docker 重启 |
| containerd 未走 mirror | `config_path`、`hosts.toml`、containerd 重启 |
| Kubernetes Pod 拉取失败 | 节点运行时、`crictl pull`、kubelet 日志 |

## 十一、上线检查清单

- [ ] 源站 `./scripts/validate.sh` 通过。
- [ ] `.env` 已填写 Docker Hub 用户名和 Access Token。
- [ ] 源站默认不对公网裸露，或已限制来源 IP。
- [ ] CDN HTTPS 域名可访问 `/v2/`。
- [ ] `/v2/*/blobs/*` 长缓存已配置。
- [ ] `/v2/*/manifests/*` 不缓存或短缓存。
- [ ] Range 回源已开启或确认支持。
- [ ] WAF 对 `/v2/` 跳过验证码和浏览器挑战。
- [ ] Docker 客户端 `docker pull alpine:3.20` 成功。
- [ ] Kubernetes 节点 `crictl pull docker.io/library/alpine:3.20` 成功。
- [ ] 源站日志显示 CDN 回源请求正常。

## 十二、回滚验证

如果 CDN 或客户端配置异常：

1. 从客户端移除 mirror endpoint。
2. 源站恢复本机监听：

```bash
cd /data/docker-image-proxy
sed -i 's/^PROXY_BIND_ADDR=.*/PROXY_BIND_ADDR=127.0.0.1/' .env
docker compose up -d
curl -fsSI http://127.0.0.1:5000/v2/
```

3. 关闭安全组中临时开放的公网端口。
4. 保留源站本机验证能力，等待 CDN/客户端修复后再重新发布。
