# 文档导航

这里是 Docker Image Proxy 的生产文档入口。建议按照“先部署源站、再发布入口、最后配置客户端”的顺序阅读。

## 快速路径

### 我要先把源站跑起来

1. 阅读 [架构设计说明](architecture.md)，确认本服务只代理 Docker Hub。
2. 按 [源站部署手册](source-deployment.md) 把 `deploy/` 同步到服务器 `/data/docker-image-proxy/`。
3. 填写 Docker Hub 用户名和 Access Token 后执行 `./scripts/install-or-update.sh`。
4. 用 [验证手册](validation.md) 做源站本机验证。

### 我要让国内 Docker 服务器使用

1. 阅读 [CDN 和安全入口](cdn-and-security.md)，确定入口模式。
2. 按 [CDN 加速配置手册](cdn-acceleration.md) 和 [安全加固手册](security-hardening.md) 配置入口。
3. 得到 `https://mirror.example.com` 这类 HTTPS mirror endpoint。
4. 按 [客户端接入手册](client-usage.md) 配置 `/etc/docker/daemon.json`。

### 我要让 Kubernetes 节点使用

1. 用 `kubectl get nodes -o custom-columns=NAME:.metadata.name,RUNTIME:.status.nodeInfo.containerRuntimeVersion` 判断节点运行时。
2. Docker CRI 节点按 [客户端接入手册 - Kubernetes 使用 Docker 作为 CRI](client-usage.md#二kubernetes-使用-docker-作为-cri) 配置。
3. containerd 节点按 [客户端接入手册 - Kubernetes 使用 containerd 作为 CRI](client-usage.md#三kubernetes-使用-containerd-作为-cri) 配置。
4. k3s/RKE2 按对应章节配置 `registries.yaml`。

### 我要走 CDN 和安全收口

1. 选择 [CDN 和安全入口](cdn-and-security.md) 中的入口模式。
2. 按 [CDN 加速配置手册](cdn-acceleration.md) 配置缓存、Range、Header。
3. 按 [CDN 厂商配置手册](cdn-provider-setup.md) 配置具体云厂商。
4. 如需自定义 Header 回源鉴权，按 [部署包说明](../deploy/README.md) 启用 `nginx/conf.d/cdn-origin-auth.conf`。
5. 按 [安全加固手册](security-hardening.md) 做源站保护、WAF 放行和回源鉴权。
6. 用 [验证手册](validation.md) 做真实拉取测试。

## 文档清单

| 文档 | 内容 |
| --- | --- |
| [方案入口](../Docker%20Registry%20Mirror%20%E8%87%AA%E5%BB%BA%E6%96%B9%E6%A1%88%EF%BC%88%E7%94%9F%E4%BA%A7%E5%8F%AF%E7%94%A8%EF%BC%89.md) | 推荐方案和阅读路径 |
| [架构设计说明](architecture.md) | 为什么这样设计、适用边界、架构和版本选择 |
| [源站部署手册](source-deployment.md) | `/data/docker-image-proxy/` 源站部署、开放入口 |
| [部署包说明](../deploy/README.md) | `deploy/` 目录如何复制、启动和验证 |
| [客户端接入手册](client-usage.md) | Docker、Kubernetes Docker CRI、containerd、k3s、RKE2 配置 |
| [CDN 和安全入口](cdn-and-security.md) | CDN/安全入口模式选择和跳转 |
| [CDN 加速配置手册](cdn-acceleration.md) | CDN 选型、缓存、回源、Range、Header |
| [CDN 厂商配置手册](cdn-provider-setup.md) | 阿里云、腾讯云、华为云、AWS CloudFront、Cloudflare 逐步配置 |
| [安全加固手册](security-hardening.md) | 源站保护、WAF、回源鉴权、限流、密钥管理 |
| [验证手册](validation.md) | 源站、CDN、Docker、Kubernetes 端到端验证 |
| [日常运维手册](operations.md) | 安装、升级、回滚、日志、GC、备份、排错 |
| [硅谷源站案例](production-case-silicon-valley.md) | 真实部署经验，用模拟数据展示可替换字段 |
| [AI agent 说明](../AGENTS.md) | 给自动化 agent 的仓库结构、约束和验证路径 |

## 开源协作入口

| 文档 | 内容 |
| --- | --- |
| [贡献指南](../CONTRIBUTING.md) | Issue、PR、本地检查、文档风格和安全脱敏要求 |
| [安全政策](../SECURITY.md) | 安全问题反馈方式、支持范围和敏感信息规则 |
| [社区行为准则](../CODE_OF_CONDUCT.md) | 参与讨论、Issue 和 PR 的基本协作准则 |
| [变更日志](../CHANGELOG.md) | 已发布版本和未发布变更记录 |

## 示例值约定

文档中的公网 IP、域名、SSH 端口、密钥路径和 token 都使用模拟数据：

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

这些值只用于说明配置位置。上线前必须替换成自己的真实值，真实敏感信息不要提交到仓库。

## 维护原则

- `README.md` 是仓库总入口。
- `docs/README.md` 是文档导航入口。
- `deploy/README.md` 只描述部署包本身。
- 长步骤按主题写到 `docs/`，README 和旧方案文档只保留入口路径。
- 新增生产决策时，优先更新方案入口、架构设计说明和 `AGENTS.md`，让后续维护者和 AI agent 都能快速理解背景。
