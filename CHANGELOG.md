# Changelog

本文件采用 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 风格维护，版本号尽量遵循 [Semantic Versioning](https://semver.org/)。

## [Unreleased]

### Added

- 增加开源协作文件：`CONTRIBUTING.md`、`SECURITY.md`、`CODE_OF_CONDUCT.md`。
- 增加 Issue Template 和 Pull Request Template。
- 增加根目录 `.gitignore` 和 `.editorconfig`，减少本地环境文件误提交。
- README 增加开源项目入口、英文摘要、配置表、技术栈、Roadmap、FAQ、贡献和许可证说明。

### Changed

- Compose 镜像引用改为固定明确 tag，不再使用 `@sha256` digest pin。
- 仓库展示信息和文档入口围绕 Docker Hub registry mirror / pull-through cache 做搜索关键词优化。

## [1.2.0] - 2026-07-02

### Added

- 增加生产部署包文档入口和 README 徽章。
- 拆分生产方案文档，覆盖架构、源站部署、CDN、安全、验证和运维。
- 增加 CDN 厂商配置手册，覆盖阿里云、腾讯云、华为云、AWS CloudFront 和 Cloudflare。
- 增加 Docker、Kubernetes Docker CRI、containerd、k3s、RKE2 客户端接入说明。
- 增加使用模拟数据展示的硅谷源站部署案例。

### Changed

- Docker Hub 上游认证改为生产必填，安装脚本会在缺少用户名或 Access Token 时退出。
- 长篇方案文档调整为入口文档，详细步骤拆分到 `docs/`。

## [1.1.0] - 2026-01-17

### Added

- 增加访问控制和限流相关说明。
- 增加 Registry v3 相关部署说明和路径调整。

[Unreleased]: https://github.com/seaworld008/docker-image-proxy/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/seaworld008/docker-image-proxy/releases/tag/v1.2.0
[1.1.0]: https://github.com/seaworld008/docker-image-proxy/releases/tag/v1.1.0
