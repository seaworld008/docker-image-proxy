# Docker Registry Mirror 自建方案（生产可用）

本文提供两个可直接落地的 Docker Hub 镜像加速方案，均基于官方 `registry:2` 的 **proxy mirror** 模式，可缓存已拉取的镜像层，显著提升国内拉取速度与稳定性。

## 方案选择

- 方案 A：**利用你已有的机场订阅代理（本地/内网）**，部署一个内网镜像加速服务，走你的代理出海。
- 方案 B：**部署在外网服务器 + CDN 加速**，全球访问更快，适合团队或多地机房使用。

> 说明：Docker 的 `registry-mirrors` 只针对 Docker Hub（`docker.io`）生效，不影响其它私有仓库。

---

## 适用规模（中小规模）

本方案更适合 **中小规模** 场景：小团队/多节点环境、拉取频次中等、缓存规模可控。  
当出现大规模并发、大量私有镜像、全球多区域高频访问时，建议进一步拆分多源站或使用专用镜像服务。

---

## 中小规模推荐配置（参考范围）

以下为经验范围，便于快速落地，实际按并发量与镜像体积调整。

- **方案 A（内网代理）**：2C/2-4G，磁盘 100-300GB，内网带宽 1Gbps+  
- **方案 B（海外源站）**：2-4C/4-8G，磁盘 200-500GB，公网带宽 50-200Mbps  
- **缓存策略**：`proxy.ttl` 168h；CDN `blobs` 7-30 天、`manifests` 1-10 分钟  
- **并发与稳定**：避免超高并发短时间集中拉取，可配合预热/分批拉取  
- **清理周期**：每 2-4 周评估一次磁盘空间，必要时执行 GC

---

## 方案前提条件（务必确认）

### 方案 A 前提（内网代理出海）

- **稳定代理**：可用且稳定的出网通道，例如机场订阅、企业 VPN、可访问外网的代理/VPN 网络；要求支持 HTTP/HTTPS 代理或可提供可用的出网网关，并且支持 TLS 透传（不做 TLS 劫持）。  
- **网络可达**：代理允许访问 Docker Hub 相关域名（如 `registry-1.docker.io`、`auth.docker.io` 等）。  
- **内网可达**：内网客户端可访问镜像代理服务的 `5000` 端口。  
- **系统与资源**：64 位 Linux，建议 2C2G+、SSD/高速盘、磁盘空间视缓存规模而定。  
- **Docker 环境**：已安装 Docker 与 Docker Compose。  
- **安全要求**：如使用 HTTP 镜像，仅限内网访问并配置防火墙/ACL。

### 方案 B 前提（海外源站 + CDN）

- **公网源站**：海外服务器可稳定访问外网，带宽与磁盘满足缓存需求。  
- **域名与 DNS**：已准备域名并可解析到源站或 CDN。  
- **CDN 能力**：支持大文件缓存、Range 请求、HTTPS 回源。  
- **证书**：可用 TLS 证书（CDN 证书或源站证书）。  
- **端口开放**：源站开放 80/443，CDN 回源可访问。  
- **回源地址**：回源应指向**源站 IP 或独立源站域名**（不要与加速域名相同，避免回源环）。  
- **安全策略**：建议配置回源鉴权或源站白名单，避免源站被直连攻击。

---

## 方案 A：使用你已有的代理出海（内网加速）

### 架构

本地或内网部署一个 `registry:2` 镜像缓存代理，所有拉取请求经由你的代理服务器 `192.168.110.210:7897` 出海访问 Docker Hub。

### 1) 目录准备

```bash
mkdir -p /data/registry-mirror/{data,config}
cd /data/registry-mirror
```

### 2) 写入 Registry 配置

创建 `/data/registry-mirror/config/config.yml`：

```yaml
version: 0.1
log:
  level: info
storage:
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
proxy:
  remoteurl: https://registry-1.docker.io
  ttl: 168h
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
```

### 3) 写入环境变量（代理 + Docker Hub 账号，必填）

创建 `/data/registry-mirror/.env`（将地址替换成你真实代理；示例 `http://192.168.110.210:7897` 为本地 Clash 代理地址；建议注册自己的 Docker Hub 账号并创建 Access Token）：

```ini
HTTP_PROXY=http://192.168.110.210:7897
HTTPS_PROXY=http://192.168.110.210:7897
NO_PROXY=localhost,127.0.0.1,registry,registry-mirror
DOCKERHUB_USER=your_dockerhub_user
DOCKERHUB_PASS=your_dockerhub_token
```

**为什么必填？**  
Docker Hub 对匿名拉取有严格的速率限制（尤其是多节点/高并发时更明显）。  
镜像代理一旦并发拉取或多人共用，匿名额度很快耗尽，表现为拉取失败或速度极慢。  
配置账号与 Token 后，镜像代理会使用认证通道拉取，显著提高稳定性，避免被限流。

**Docker Hub 注册地址：** https://hub.docker.com/signup

### 4) Docker Compose 部署

创建 `/data/registry-mirror/docker-compose.yml`：

```yaml
services:
  registry:
    image: registry:2.8.2
    container_name: registry-mirror
    restart: unless-stopped
    ports:
      - "5000:5000"
    environment:
      HTTP_PROXY: ${HTTP_PROXY}
      HTTPS_PROXY: ${HTTPS_PROXY}
      NO_PROXY: ${NO_PROXY}
      REGISTRY_PROXY_USERNAME: ${DOCKERHUB_USER}
      REGISTRY_PROXY_PASSWORD: ${DOCKERHUB_PASS}
    volumes:
      - ./data:/var/lib/registry
      - ./config/config.yml:/etc/docker/registry/config.yml:ro
```

启动：

```bash
docker compose up -d
```

### 5) 配置 Docker 客户端使用镜像加速

编辑 Docker 引擎配置 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": ["http://<你的内网IP>:5000"],
  "insecure-registries": ["<你的内网IP>:5000"]
}
```

重启 Docker：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

验证：

```bash
docker info | sed -n "/Registry Mirrors/,+3p"
docker pull hello-world
```

---

## 方案 B：外网服务器 + CDN 加速（生产推荐）

### 架构

外网服务器运行 Registry Mirror，前置 Nginx 终止 TLS，CDN 作为全球缓存入口。

### 1) 服务器准备

- 公网服务器（建议 2C4G+，磁盘 200GB+）
- 已安装 Docker + Docker Compose
- 已准备域名，例如 `mirror.example.com`
- CDN 已开通并支持回源

### 2) 目录准备

```bash
mkdir -p /data/registry-mirror/{data,config,nginx}
cd /data/registry-mirror
```

### 3) Registry 配置

创建 `/data/registry-mirror/config/config.yml`：

```yaml
version: 0.1
log:
  level: info
storage:
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
proxy:
  remoteurl: https://registry-1.docker.io
  ttl: 168h
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
```

### 4) Nginx 配置（TLS 终止 + 反代）

创建 `/data/registry-mirror/nginx/nginx.conf`：

```nginx
events {}

http {
  server {
    listen 80;
    server_name mirror.example.com;
    return 301 https://$host$request_uri;
  }

  server {
    listen 443 ssl http2;
    server_name mirror.example.com;

    ssl_certificate     /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    client_max_body_size 0;
    proxy_read_timeout 900s;
    proxy_request_buffering off;

    location /v2/ {
      proxy_pass                          http://registry:5000;
      proxy_set_header Host               $host;
      proxy_set_header X-Real-IP          $remote_addr;
      proxy_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto  $scheme;
    }
  }
}
```

> 证书准备：你可以用 `certbot` 或 CDN 提供的源站证书。证书文件放在 `/data/registry-mirror/nginx/ssl/` 目录。

### 5) Docker Compose 部署

创建 `/data/registry-mirror/docker-compose.yml`：

```yaml
services:
  registry:
    image: registry:2.8.2
    container_name: registry-mirror
    restart: unless-stopped
    environment:
      # 建议必配：避免 Docker Hub 拉取限流
      REGISTRY_PROXY_USERNAME: ${DOCKERHUB_USER}
      REGISTRY_PROXY_PASSWORD: ${DOCKERHUB_PASS}
    volumes:
      - ./data:/var/lib/registry
      - ./config/config.yml:/etc/docker/registry/config.yml:ro

  nginx:
    image: nginx:1.27
    container_name: registry-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - registry
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
```

创建 `/data/registry-mirror/.env`（建议必配，避免 Docker Hub 拉取限流）：

```ini
DOCKERHUB_USER=your_dockerhub_user
DOCKERHUB_PASS=your_dockerhub_token
```

**为什么建议必配？**  
海外源站作为公共入口，回源拉取更频繁；匿名额度容易被快速耗尽。  
配置账号与 Token 可显著提高回源稳定性，减少 429/拉取失败问题。

启动：

```bash
docker compose up -d
```

### 6) CDN 建议配置（通用）

- 回源地址：源站 IP 或独立源站域名（不要与加速域名相同）
- 回源协议：优先 HTTPS（与 Nginx 443 保持一致）
- 缓存规则：
  - `/v2/*/blobs/*` 缓存 7-30 天
  - `/v2/*/manifests/*` 缓存 1-10 分钟
- 允许 Range 请求
- 保留 `Docker-Distribution-API-Version` 头

### 6.1) CDN 大致配置步骤（通用）

> 不同云厂商界面略有差异，但核心步骤一致，按下列要点设置即可。

1) **新增加速域名**  
   - 加速域名：`mirror.example.com`  
   - 业务类型：下载/动态静态混合（若可选）

2) **配置回源**  
   - 回源类型：源站域名/源站 IP  
   - 回源地址：源站 IP 或独立源站域名（不要与加速域名相同）  
   - 回源协议：HTTPS（优先）  
   - 回源端口：443  
   - 回源 Host 头：保持为 `mirror.example.com`

3) **配置 HTTPS**  
   - 证书来源：上传源站证书或 CDN 托管证书  
   - 访问协议：仅 HTTPS 或 HTTP 自动跳转 HTTPS  
   - TLS 版本：建议 TLS 1.2+

4) **配置缓存规则**  
   - 路径规则 `/v2/*/blobs/*`：缓存 7-30 天  
   - 路径规则 `/v2/*/manifests/*`：缓存 1-10 分钟  
   - 默认规则：可设置较短缓存或不缓存  
   - 缓存键：保留查询参数（默认即可）

5) **请求/响应设置**  
   - 允许 Range 请求  
   - 透传/保留响应头：`Docker-Distribution-API-Version`  
   - 允许方法：GET、HEAD、OPTIONS（通常已默认允许）

6) **配置回源鉴权（可选）**  
   - 若启用 WAF/鉴权，注意放行 `/v2/` 路径  
   - 如需限制来源，可用 IP 白名单或签名回源

### 6.2) 各云厂商控制台配置示例

以下步骤为“控制台点选路径 + 关键参数”，请按你实际界面名称微调。

#### 阿里云 CDN

1) CDN 控制台 → **域名管理** → **添加域名**  
   - 加速域名：`mirror.example.com`  
   - 业务类型：下载/全站加速  
2) **源站信息**  
   - 源站类型：源站域名/源站 IP  
   - 源站地址：源站 IP 或独立源站域名  
   - 协议：HTTPS，端口 443  
   - 回源 Host：`mirror.example.com`  
3) **HTTPS 配置**  
   - 上传证书或选择托管证书  
   - 强制 HTTPS（或 HTTP→HTTPS）  
4) **缓存配置**  
   - 目录 `/v2/*/blobs/*` 缓存 7-30 天  
   - 目录 `/v2/*/manifests/*` 缓存 1-10 分钟  
5) **高级设置**  
   - 允许 Range 请求  
   - 响应头保留：`Docker-Distribution-API-Version`

#### 腾讯云 CDN

1) CDN 控制台 → **域名管理** → **添加域名**  
   - 加速域名：`mirror.example.com`  
   - 业务类型：下载/静态加速  
2) **源站配置**  
   - 源站类型：自有源（源站域名/源站 IP）  
   - 源站地址：源站 IP 或独立源站域名  
   - 回源协议：HTTPS  
   - 回源 Host：`mirror.example.com`  
3) **HTTPS 配置**  
   - 上传证书或选择托管证书  
   - 开启 HTTPS 访问与强制跳转  
4) **缓存规则**  
   - `/v2/*/blobs/*`：7-30 天  
   - `/v2/*/manifests/*`：1-10 分钟  
5) **回源与头部**  
   - 开启 Range 回源  
   - 保留响应头：`Docker-Distribution-API-Version`

#### 华为云 CDN

1) CDN 控制台 → **域名管理** → **添加域名**  
   - 加速域名：`mirror.example.com`  
   - 业务类型：下载加速  
2) **源站设置**  
   - 源站类型：源站域名/源站 IP  
   - 源站地址：源站 IP 或独立源站域名  
   - 回源协议：HTTPS，端口 443  
   - Host 头：`mirror.example.com`  
3) **HTTPS 配置**  
   - 上传证书或启用托管证书  
   - 强制 HTTPS  
4) **缓存规则**  
   - `/v2/*/blobs/*`：7-30 天  
   - `/v2/*/manifests/*`：1-10 分钟  
5) **高级设置**  
   - Range 请求：启用  
   - 响应头保留：`Docker-Distribution-API-Version`

#### Cloudflare

1) Cloudflare 控制台 → **Websites** → 选择域名  
2) **DNS**  
   - 添加 `mirror.example.com` 记录指向源站 IP（A/AAAA）  
   - 记录需开启代理（橙云）  
3) **SSL/TLS**  
   - 模式选择 **Full (strict)**  
   - 上传源站证书或用 Cloudflare Origin CA  
4) **Caching**  
   - 页面规则或缓存规则  
   - `*/v2/*/blobs/*`：缓存 7-30 天  
   - `*/v2/*/manifests/*`：缓存 1-10 分钟  
5) **Network**  
   - 保持 Range 请求支持（默认支持）  
   - 如启用 WAF，自定义规则放行 `/v2/`

### 6.3) 源站鉴权/回源签名/WAF 放行规则（开启时）

目标：**只允许 CDN 回源访问源站**，拦截外部直连，同时不影响 Docker 客户端拉取。

**推荐方案（二选一即可）：**
- 方案 1：**回源鉴权/签名 + 源站校验**  
  CDN 回源时附加自定义 Header（或签名参数），源站只接受带该 Header 的请求。
- 方案 2：**源站 IP 白名单**  
  源站防火墙仅放行 CDN 回源 IP 段，其它一律拒绝。

**Nginx 源站校验示例（Header 方式）**  
在 `server` 中加入：

```nginx
# 仅示例：把 your-shared-secret 换成你的随机值
if ($http_x_cdn_auth != "your-shared-secret") { return 403; }
```

**WAF 放行规则要点：**
- 放行路径：`/v2/`（包含 `blobs`、`manifests`）
- 放行方法：`GET`、`HEAD`、`OPTIONS`
- 放行请求头：`Authorization`、`Range`
- 关闭 JS Challenge/验证码/机器人拦截（对 `/v2/` 路径）
- 允许大文件与分块下载（Range）

**各云厂商配置指引（简要）：**

- 阿里云 CDN：  
  - 位置：域名管理 → 访问控制/安全 → **回源鉴权**  
  - 方式：自定义 Header 或 Token 鉴权  
  - WAF：放行 `/v2/`，关闭挑战/验证码

- 腾讯云 CDN：  
  - 位置：域名管理 → 安全配置 → **回源鉴权**  
  - 方式：自定义回源 Header 或签名参数  
  - WAF：规则放行 `/v2/`，允许 Range

- 华为云 CDN：  
  - 位置：域名管理 → 安全设置 → **回源鉴权**  
  - 方式：自定义 Header/Token 鉴权  
  - WAF：放行 `/v2/`，关闭拦截类规则

- Cloudflare：  
  - 回源保护：**Authenticated Origin Pulls** 或 **自定义 Header**  
  - WAF：Firewall Rules 放行 `/v2/`，禁用 Bot Fight/JS Challenge

### 7) 配置 Docker 客户端使用镜像加速

客户端 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": ["https://mirror.example.com"]
}
```

重启 Docker 并验证：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
docker pull hello-world
```

---

## K8S 节点配置（Docker / containerd）

> 需要在 **每个节点** 上配置。生产建议优先使用 HTTPS 镜像地址；若是内网 HTTP，请确保仅限内网访问并做好防火墙控制。

### A) K8S 使用 Docker（cri-dockerd）

1) 编辑 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": ["https://mirror.example.com"]
}
```

> 若使用内网 HTTP 镜像，加上 `insecure-registries`：

```json
{
  "registry-mirrors": ["http://<内网IP>:5000"],
  "insecure-registries": ["<内网IP>:5000"]
}
```

2) 重启服务：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl restart cri-docker
sudo systemctl restart kubelet
```

3) 验证：

```bash
docker info | sed -n "/Registry Mirrors/,+3p"
crictl pull docker.io/library/alpine:3.20
```

### B) K8S 使用 containerd（推荐）

1) 生成并开启配置（如果尚未存在；已有配置请勿覆盖）：

```bash
sudo mkdir -p /etc/containerd
[ -f /etc/containerd/config.toml ] || containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
```

2) 配置 `config_path`（启用 hosts.toml 方式）：

编辑 `/etc/containerd/config.toml`，确保：

```toml
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
```

3) 添加镜像加速 Hosts 配置：

```bash
sudo mkdir -p /etc/containerd/certs.d/docker.io
```

创建 `/etc/containerd/certs.d/docker.io/hosts.toml`：

```toml
server = "https://registry-1.docker.io"

[host."https://mirror.example.com"]
  capabilities = ["pull", "resolve"]
```

> 若使用内网 HTTP 镜像（不推荐，仅限内网）：  
> 将 `host` 改为 `http://<内网IP>:5000`，并确保内网访问可达。

4) 重启服务：

```bash
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

5) 验证：

```bash
crictl info | grep -E "registry|mirror|config_path"
crictl pull docker.io/library/alpine:3.20
```

### C) kubeadm 集群（containerd 为默认）

> kubeadm 默认使用 `containerd`，镜像加速配置必须在 **init/join 之前** 完成并同步到所有节点。

1) 按上面的 **B) containerd** 完成镜像加速配置并重启 `containerd`。  
2) 初始化/加入集群（显式声明 cri socket，避免歧义）：

```bash
# 初始化控制面（示例）
sudo kubeadm init --cri-socket unix:///run/containerd/containerd.sock

# 工作节点加入（示例）
sudo kubeadm join <control-plane>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///run/containerd/containerd.sock
```

3) 验证：

```bash
kubectl get nodes
crictl pull docker.io/library/alpine:3.20
```

> 说明：kubeadm 组件镜像主要来自 `registry.k8s.io`，不走 Docker Hub。  
> 若需加速 `registry.k8s.io`，可按相同方式在 `/etc/containerd/certs.d/registry.k8s.io/hosts.toml` 配置镜像源。

### D) k3s 集群（使用 registries.yaml）

> k3s 使用内置 containerd，**不要直接修改** `config.toml`，应通过 `registries.yaml` 注入配置。

1) 在每个节点创建 `/etc/rancher/k3s/registries.yaml`：

```yaml
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.example.com"
```

> 若使用内网 HTTP 镜像（不推荐，仅限内网）：  
> 把 endpoint 改为 `http://<内网IP>:5000`，并加上：

```yaml
configs:
  "<内网IP>:5000":
    tls:
      insecure_skip_verify: true
```

2) 重启服务（按节点角色）：

```bash
sudo systemctl restart k3s
# 或
sudo systemctl restart k3s-agent
```

3) 验证：

```bash
crictl info | grep -E "registry|mirror"
crictl pull docker.io/library/alpine:3.20
```

---

## 运维与优化建议

- 镜像缓存目录要放在性能好的磁盘，定期监控容量
- 建议设置 `proxy.ttl` 为 168h（或按需调整）
- 若需要清理历史镜像层，需停止服务后执行 GC：

```bash
docker compose down
docker run --rm \
  -v /data/registry-mirror/data:/var/lib/registry \
  -v /data/registry-mirror/config/config.yml:/etc/docker/registry/config.yml:ro \
  registry:2.8.2 garbage-collect /etc/docker/registry/config.yml
docker compose up -d
```

---

## 测速与链路评估（方案 A/方案 B 通用）

建议在部署前后做一次测速，判断瓶颈在“代理/源站/本地网络”还是“CDN 命中率”。

### 1) 安装测速工具（iperf3）

```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y iperf3

# CentOS/RHEL
sudo yum install -y iperf3

# Rocky/Alma/Fedora
sudo dnf install -y iperf3

# Alpine
sudo apk add iperf3
```

### 2) 代理链路测速（方案 A）

在你的代理出口附近（或海外 VPS）起一个 iperf3 服务器：

```bash
iperf3 -s
```

在内网客户端执行测试（可加 `-p` 指定端口）：

```bash
iperf3 -c <iperf_server_ip> -t 10
```

> 如果代理走的是 SOCKS5/HTTP，可先在本机设置系统代理，再运行 iperf3；或在 VPS 上测试代理出口带宽。

### 3) CDN/源站链路测速（方案 B）

用 `curl` 测试源站与 CDN 的响应时延（吞吐以 `docker pull` 为准）：

```bash
# CDN 入口（国内客户端）
curl -I https://mirror.example.com/v2/
```

### 4) Docker 拉取测速

```bash
time docker pull alpine:3.20
```

首次拉取慢是正常的，第二次（命中缓存/本地缓存）应显著加快。

---

## 快速排错

- 服务是否可用：
  ```bash
  # 方案 A（内网 HTTP）
  curl -I http://<内网IP>:5000/v2/

  # 方案 B（CDN HTTPS）
  curl -I https://mirror.example.com/v2/
  ```
- Docker 是否使用镜像加速：
  ```bash
  docker info | sed -n "/Registry Mirrors/,+3p"
  ```
- 拉取某个镜像测试：
  ```bash
  docker pull alpine:3.20
  ```

---

如果你需要：
- 增加访问控制（IP 白名单、WAF、限流）
- 多地域多节点镜像同步
- 监控告警（Prometheus/Grafana）

告诉我你的目标规模，我可以给你更进一步的生产化方案。
