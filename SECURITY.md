# 安全政策

## 支持范围

当前维护重点：

- `main` 分支。
- 最新 GitHub Release。
- `deploy/` 下的 Docker Compose、Registry、Nginx 和脚本配置。
- `docs/` 下与部署、CDN、安全、客户端接入和验证相关的文档。

第三方平台本身的安全问题，例如 Docker Hub、CDN 厂商、云厂商或 Kubernetes 发行版漏洞，不属于本仓库可直接修复的范围，但欢迎补充与本项目使用方式相关的缓解建议。

## 如何报告安全问题

请不要在公开 Issue 中披露敏感漏洞细节、真实 token、服务器 IP、私钥路径或可复现攻击载荷。

推荐方式：

- 通过 GitHub Security Advisories 报告。
- 或联系项目维护者，并提供已脱敏的复现步骤。

如果暂时无法使用私密渠道，请先创建一个不包含敏感细节的 Issue，说明“需要私密安全沟通”，等待维护者回应。

## 报告内容建议

请尽量提供：

- 受影响的文件、配置或文档章节。
- 影响范围，例如源站暴露、认证绕过、token 泄露、WAF 误拦截或客户端配置风险。
- 已脱敏的复现步骤。
- 期望的安全行为。
- 可行的修复建议。

## 敏感信息规则

公开仓库中只能使用模拟值：

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

不要提交：

- `.env` 文件。
- Docker Hub 用户名和 Access Token。
- `REGISTRY_HTTP_SECRET`。
- 真实公网 IP、SSH 端口、私钥路径。
- 云厂商 Access Key、Secret Key 或 CDN 回源密钥。
- TLS 私钥或证书私钥。

## 响应说明

维护者会尽力确认问题、评估影响并给出修复路径。由于当前仓库尚未声明正式安全 SLA，响应时间需项目维护者确认。
