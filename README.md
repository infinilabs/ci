# Testing

产品发布前自动化测试

## 各工作流说明

- `Analysis Plubins Publish` 自动发布 `analysis-ik` `analysis-pinyin` `analysis-stconvert` 插件
- `Easysearch Files & Docker Publish` 自动发布 `Easysearch` 快照版本文件 (含 bundle 包) 及 Docker 镜像, 可手工触发发布 `Release` 版本
- `Products Files & Docker Publish`  自动发布 `Agent/Console/Gateway/Loadgen` 快照版本文件及 Docker 镜像, 可手工触发发布 `Release` 版本
- `Products Files Publish` 手工触发发布  `Agent/Console/Gateway/Loadgen` 文件
- `Products Integration Test` 自动编译 `Agent/Console/Gateway/Loadgen` 源码测试，可手工触发下载安装指定版本进行测试
- `Products Release Notes and Tag` 发版本使用，更新 `Release Notes` `Tag` 和 `.latest` 配置