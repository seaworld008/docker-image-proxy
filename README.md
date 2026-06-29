# Docker 镜像加速自建方案

本仓库提供 Docker Hub pull-through cache 镜像加速方案和一套可直接部署的 Docker Compose 包。

当前推荐版本（2026-06-29 已核验）：

- `registry:3.1.1@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33`
- `nginx:1.30.3-alpine@sha256:0d3b80406a13a767339fbe2f41406d6c7da727ab89cf8fae399e81f780f814d1`

部署包位于 [deploy](deploy)，推荐同步到服务器 `/data/docker-image-proxy/` 后启动，所有配置、缓存和日志都保存在该目录内。

完整方案请阅读：[Docker Registry Mirror 自建方案（生产可用）.md](Docker%20Registry%20Mirror%20%E8%87%AA%E5%BB%BA%E6%96%B9%E6%A1%88%EF%BC%88%E7%94%9F%E4%BA%A7%E5%8F%AF%E7%94%A8%EF%BC%89.md)
