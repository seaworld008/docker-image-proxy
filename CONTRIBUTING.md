# 贡献指南

感谢你愿意改进 Docker Image Proxy。这个仓库主要维护 Docker Hub pull-through cache 的部署包和生产文档，欢迎补充真实验证经验、CDN 配置、Kubernetes 运行时接入、排错案例和文档修正。

## 适合贡献的内容

- 修正文档错误、链接错误、命令错误或脱敏遗漏。
- 补充 Docker、containerd、k3s、RKE2 或其他 Kubernetes 发行版的配置经验。
- 补充 CDN 厂商配置、WAF 放行、源站保护和回源鉴权经验。
- 改进 `deploy/` 目录下的 Compose、Nginx、Registry 配置和脚本。
- 增加验证步骤、运维 runbook 或真实案例，但必须使用模拟数据。

## 不适合直接提交的内容

- 真实公网 IP、SSH 端口、私钥路径、token、证书私钥、`.env` 文件或云厂商密钥。
- 未验证的性能数据、用户规模、兼容性承诺或 Roadmap 承诺。
- 与 Docker Hub mirror 无关的大规模重构。
- 无法运行或依赖未知 secret 的 GitHub Actions。
- 未经维护者确认的 `LICENSE` 文件。

## 本地准备

```bash
git clone https://github.com/seaworld008/docker-image-proxy.git
cd docker-image-proxy
git switch -c docs/your-change
```

本仓库没有应用源码构建流程。常用检查命令：

```bash
git diff --check
bash -n deploy/scripts/install-or-update.sh deploy/scripts/validate.sh
```

如果本机有 Docker，也建议执行：

```bash
cd deploy
docker compose config
```

真实部署验证请在测试服务器执行，并确保 `.env` 不提交到仓库。

## 分支命名建议

- `docs/...`：文档改进。
- `deploy/...`：部署配置或脚本改进。
- `security/...`：安全配置或敏感信息处理。
- `release/...`：发布说明或版本文档。

## Commit message 建议

建议使用简洁、可搜索的提交信息：

```text
docs: improve containerd mirror guide
deploy: harden nginx registry proxy defaults
security: clarify origin access restrictions
chore: update repository templates
```

## Pull Request 要求

提交 PR 前请确认：

- 变更范围清晰，避免把不相关修改放在同一个 PR。
- README、`docs/README.md`、`deploy/README.md`、`AGENTS.md` 的入口链接保持同步。
- 涉及部署配置时，已更新对应验证命令和回滚说明。
- 文档中的公网 IP、域名、SSH、token 都使用模拟值。
- 已说明执行过的检查命令，以及无法执行的检查原因。

## 文档风格

- 中文文档优先使用清晰、可执行的步骤。
- README 保持总入口定位，长步骤放到 `docs/`。
- 不写无法验证的“高性能”“无限制”“企业级”等承诺。
- 对需要维护者确认的信息明确标注“需项目维护者确认”。

## 安全反馈

安全问题不要直接公开贴出敏感细节。请按 [SECURITY.md](SECURITY.md) 的方式报告。
