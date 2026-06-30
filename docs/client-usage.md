# 国内 Docker/Kubernetes 客户端接入手册

本文说明国内 Docker 服务器和 Kubernetes 节点如何使用本仓库部署的 Docker Hub pull-through cache。

## 先确认镜像加速入口

客户端只需要一个 mirror endpoint：

- 生产推荐：`https://mirror.example.com`
- 内测直连：`http://203.0.113.10:5000`

推荐优先使用 `https://mirror.example.com`。HTTP 直连只适合短期验证或受控内网，并且必须用云安全组或防火墙限制来源 IP。

客户端配置时不要带 `/v2/` 后缀：

```text
正确：https://mirror.example.com
错误：https://mirror.example.com/v2/
```

业务镜像名保持不变：

```bash
docker pull alpine:3.20
docker pull nginx:1.30.3-alpine
```

不要把业务镜像名改成 mirror 地址。下面这种只适合源站直连测试：

```bash
docker pull mirror.example.com/library/alpine:3.20
```

## 适用边界

- `registry-mirrors` 主要加速 Docker Hub，也就是 `docker.io`。
- `registry.k8s.io`、`quay.io`、`ghcr.io`、私有仓库不会因为 Docker Hub mirror 自动加速，需要分别配置对应 registry 的 mirror 或代理策略。
- Kubernetes 节点修改运行时配置后通常需要重启 Docker/containerd/kubelet。生产集群建议逐台 drain、配置、验证、uncordon。

## 节点运行时识别

在 Kubernetes 集群侧查看每个节点的容器运行时：

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,RUNTIME:.status.nodeInfo.containerRuntimeVersion
```

常见结果：

```text
docker://20.10.x       # Docker Engine + cri-dockerd 或旧 dockershim
containerd://1.7.x    # containerd
containerd://2.x      # containerd 2.x
```

在节点本机也可以检查服务：

```bash
systemctl status docker --no-pager
systemctl status cri-docker --no-pager || systemctl status cri-dockerd --no-pager
systemctl status containerd --no-pager
systemctl status kubelet --no-pager
```

## 一、普通 Docker 服务器

适用于非 Kubernetes 的 Docker Engine 服务器。

### HTTPS mirror 配置

备份并编辑 `/etc/docker/daemon.json`：

```bash
sudo mkdir -p /etc/docker
sudo cp -a /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%F-%H%M%S) 2>/dev/null || true
```

如果原文件不存在，可直接写入：

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://mirror.example.com"
  ]
}
EOF
```

如果原文件已存在，请把 `registry-mirrors` 合并进去，不要覆盖已有的 `data-root`、`log-driver`、`exec-opts` 等配置。

重启并验证：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
docker info | sed -n '/Registry Mirrors/,+8p'
docker pull alpine:3.20
```

### HTTP 直连内测配置

仅在受控网络使用。源站安全组必须只允许国内 Docker 服务器公网 IP 访问 TCP `5000`。示例源站 IP 为 `203.0.113.10`，上线前请替换成自己的源站公网 IP。

```bash
sudo mkdir -p /etc/docker
sudo cp -a /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%F-%H%M%S) 2>/dev/null || true

sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "http://203.0.113.10:5000"
  ],
  "insecure-registries": [
    "203.0.113.10:5000"
  ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
docker info | sed -n '/Registry Mirrors/,+10p'
docker pull alpine:3.20
```

`insecure-registries` 只在 HTTP 或自签名证书测试时使用。生产 HTTPS 域名不要配置它。

## 二、Kubernetes 使用 Docker 作为 CRI

适用于节点运行时显示 `docker://...` 的集群。Kubernetes 1.24 起移除了内置 dockershim，Docker 作为 CRI 时通常依赖 `cri-dockerd`。

### 变更流程

建议逐台节点操作：

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

按上文“普通 Docker 服务器”配置 `/etc/docker/daemon.json`。

重启服务：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl restart cri-docker || sudo systemctl restart cri-dockerd
sudo systemctl restart kubelet
```

验证 Docker 与 CRI 拉取：

```bash
docker info | sed -n '/Registry Mirrors/,+8p'
docker pull alpine:3.20

sudo crictl --runtime-endpoint unix:///var/run/cri-dockerd.sock pull docker.io/library/alpine:3.20 \
  || sudo crictl --runtime-endpoint unix:///run/cri-dockerd.sock pull docker.io/library/alpine:3.20
```

恢复调度：

```bash
kubectl uncordon <node-name>
```

再创建一个临时 Pod 验证 kubelet 能正常拉镜像：

```bash
kubectl run mirror-test-docker --image=docker.io/library/alpine:3.20 --restart=Never -- sleep 60
kubectl get pod mirror-test-docker -o wide
kubectl delete pod mirror-test-docker
```

## 三、Kubernetes 使用 containerd 作为 CRI

适用于节点运行时显示 `containerd://...` 的集群。

### 变更流程

建议逐台节点操作：

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

确认或生成 containerd 配置：

```bash
sudo mkdir -p /etc/containerd
[ -f /etc/containerd/config.toml ] || containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
containerd --version
```

### containerd 1.x 配置入口

如果是 containerd 1.x，编辑 `/etc/containerd/config.toml`，确保存在：

```toml
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
```

### containerd 2.x 配置入口

如果是 containerd 2.x，并且配置文件使用 v3 配置格式，编辑 `/etc/containerd/config.toml`，确保存在：

```toml
version = 3

[plugins."io.containerd.cri.v1.images".registry]
  config_path = "/etc/containerd/certs.d"
```

不要同时写入 1.x 和 2.x 两套 plugin path。以当前节点 containerd 版本和现有配置格式为准。

### 配置 docker.io hosts.toml

创建目录：

```bash
sudo mkdir -p /etc/containerd/certs.d/docker.io
```

生产 HTTPS mirror：

```bash
sudo tee /etc/containerd/certs.d/docker.io/hosts.toml >/dev/null <<'EOF'
server = "https://registry-1.docker.io"

[host."https://mirror.example.com"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF
```

HTTP 直连内测，示例源站 IP 为 `203.0.113.10`，上线前请替换成自己的源站公网 IP：

```bash
sudo tee /etc/containerd/certs.d/docker.io/hosts.toml >/dev/null <<'EOF'
server = "https://registry-1.docker.io"

[host."http://203.0.113.10:5000"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF
```

自签名 HTTPS 测试时才使用 `skip_verify`：

```toml
[host."https://mirror.example.com"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
```

重启并验证：

```bash
sudo systemctl restart containerd
sudo systemctl restart kubelet

sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock pull docker.io/library/alpine:3.20
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock images | grep alpine
```

恢复调度：

```bash
kubectl uncordon <node-name>
```

验证 kubelet 拉取：

```bash
kubectl run mirror-test-containerd --image=docker.io/library/alpine:3.20 --restart=Never -- sleep 60
kubectl get pod mirror-test-containerd -o wide
kubectl delete pod mirror-test-containerd
```

## 四、kubeadm 集群注意事项

新建 kubeadm 集群时，建议在 `kubeadm init` 和 `kubeadm join` 之前完成所有节点的 Docker/containerd mirror 配置。

containerd 示例：

```bash
sudo kubeadm init --cri-socket unix:///run/containerd/containerd.sock
```

工作节点加入示例：

```bash
sudo kubeadm join <control-plane>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///run/containerd/containerd.sock
```

Docker + cri-dockerd 示例：

```bash
sudo kubeadm init --cri-socket unix:///var/run/cri-dockerd.sock
```

kubeadm 组件镜像主要来自 `registry.k8s.io`，这部分不走 Docker Hub mirror。如需加速 `registry.k8s.io`，需要额外为 `registry.k8s.io` 配置 mirror。

## 五、k3s 集群

k3s 使用内置 containerd，不建议直接改生成出来的 containerd `config.toml`。应在每个节点配置 `/etc/rancher/k3s/registries.yaml`。

HTTPS mirror：

```bash
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<'EOF'
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.example.com"
EOF
```

HTTP 直连内测，示例源站 IP 为 `203.0.113.10`，上线前请替换成自己的源站公网 IP：

```bash
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<'EOF'
mirrors:
  docker.io:
    endpoint:
      - "http://203.0.113.10:5000"
EOF
```

自签名 HTTPS 测试时才加：

```yaml
configs:
  "mirror.example.com":
    tls:
      insecure_skip_verify: true
```

重启并验证：

```bash
sudo systemctl restart k3s || sudo systemctl restart k3s-agent
sudo crictl pull docker.io/library/alpine:3.20
```

## 六、RKE2 集群

RKE2 也使用 containerd，配置文件路径是 `/etc/rancher/rke2/registries.yaml`，格式与 k3s 基本一致。

```bash
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/registries.yaml >/dev/null <<'EOF'
mirrors:
  docker.io:
    endpoint:
      - "https://mirror.example.com"
EOF

sudo systemctl restart rke2-server || sudo systemctl restart rke2-agent
sudo crictl pull docker.io/library/alpine:3.20
```

## 七、源站侧验证

在硅谷源站查看访问是否真实打到 mirror：

```bash
cd /data/docker-image-proxy
tail -f logs/nginx/access.log
docker compose logs -f nginx registry
```

验证源站本身：

```bash
cd /data/docker-image-proxy
./scripts/validate.sh
```

验证 CDN 入口：

```bash
curl -fsSI https://mirror.example.com/v2/
curl -fsSI \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://mirror.example.com/v2/library/alpine/manifests/3.20
```

## 八、常见问题

### `http: server gave HTTP response to HTTPS client`

客户端把 HTTP mirror 当成 HTTPS registry 访问了。Docker Engine 需要配置 `insecure-registries`；containerd/k3s 需要 endpoint 明确写成 `http://...`。

### `x509: certificate signed by unknown authority`

生产建议使用公网可信证书。自签名证书需要给节点安装 CA，或仅在临时测试中使用 `skip_verify` / `insecure_skip_verify`。

### `ImagePullBackOff`

先在出问题节点直接用 CRI 验证：

```bash
sudo crictl pull docker.io/library/alpine:3.20
kubectl describe pod <pod-name> -n <namespace>
```

如果 `crictl pull` 失败，优先检查节点运行时配置、源站/CDN 连通性和安全组。

### Docker Hub 以外镜像仍然慢

这是预期行为。当前 mirror 只代理 Docker Hub。`registry.k8s.io`、`quay.io`、`ghcr.io` 需要分别配置。
