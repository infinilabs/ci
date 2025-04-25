<p align="center">
<a href="https://infinilabs.com/"><img src="docs/images/infinilabs.svg" alt="banner" width="200px"></a>
</p>

<p align="center">
<b><i>构建、发布和测试</i>自动化管理的 GitHub Actions</b>
</p>

[![Coco App Files Publish](https://github.com/infinilabs/ci/actions/workflows/coco-app.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/coco-app.yml)&nbsp;[![Coco Server Files & Docker Publish](https://github.com/infinilabs/ci/actions/workflows/coco-server.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/coco-server.yml)&nbsp;[![Easysearch Files & Docker Publish](https://github.com/infinilabs/ci/actions/workflows/easysearch-publish.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/easysearch-publish.yml)&nbsp;[![Products Files & Docker Publish](https://github.com/infinilabs/ci/actions/workflows/publish-docker.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/publish-docker.yml)&nbsp;[![Products Integration Test](https://github.com/infinilabs/ci/actions/workflows/integration-test.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/integration-test.yml)&nbsp;[![Products Release Notes and Tag](https://github.com/infinilabs/ci/actions/workflows/release.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/release.yml)

## 这个仓库能做什么

> [English](README.md) | 中文

- `Analysis Plugins Publish` 自动发布 `analysis-ik` `analysis-pinyin` `analysis-stconvert` 插件
- `Coco App Files Publish` 自动发布 `Coco-AI` 快照版本, 手动发布 `Release` 版本
- `Coco Server Files & Docker Publish` 自动发布 `Coco-Server` 快照版本文件及 Docker 镜像, 手动发布 `Release` 版本
- `Easysearch Files & Docker Publish` 自动发布 `Easysearch` 快照版本文件 (含 bundle 包) 及 Docker 镜像, 手动发布 `Release` 版本
- `Products Files & Docker Publish`  自动发布 `Agent/Console/Gateway/Loadgen` 快照版本文件及 Docker 镜像, 手动发布 `Release` 版本
- `Products Files Publish` 手动发布  `Agent/Console/Gateway/Loadgen` 文件
- `Products Integration Test` 自动编译 `Agent/Console/Gateway/Loadgen` 源码测试，手动对下载安装指定版本进行测试
- `Products Release Notes and Tag` 发版本使用，更新 `Release Notes` `Tag` 和 `.latest` 配置