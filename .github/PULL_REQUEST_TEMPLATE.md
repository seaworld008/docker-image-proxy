## 变更说明

请简要说明本 PR 改了什么，以及为什么需要改。

## 变更类型

- [ ] 文档更新
- [ ] 部署配置更新
- [ ] 脚本更新
- [ ] 安全加固
- [ ] 运维或验证流程
- [ ] 仓库工程化

## 测试和验证

请列出已执行的命令。无法执行的检查请说明原因。

```bash
git diff --check
bash -n deploy/scripts/install-or-update.sh deploy/scripts/validate.sh
```

## Checklist

- [ ] 没有提交 `.env`、token、私钥、真实公网 IP、SSH 端口或云厂商密钥。
- [ ] 文档中的示例值使用 `203.0.113.10`、`mirror.example.com` 或 `replace-with-*`。
- [ ] 涉及部署配置时，已同步更新验证和回滚说明。
- [ ] 涉及入口文档时，已同步更新 README 或 `docs/README.md`。
- [ ] 涉及 AI agent 上下文时，已同步更新 `AGENTS.md`。

## 关联 Issue

Closes #
