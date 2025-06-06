<p align="center">
<a href="https://infinilabs.com/"><img src="docs/images/infinilabs.svg" alt="banner" width="200px"></a>
</p>

<p align="center">
<b>The Github Actions for <i>Build, Publish and Testing</i> management</b>
</p>

[![Coco App Files Publish](https://github.com/infinilabs/ci/actions/workflows/coco-app.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/coco-app.yml)&nbsp;[![Coco Server Files & Docker Publish](https://github.com/infinilabs/ci/actions/workflows/coco-server.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/coco-server.yml)&nbsp;[![Easysearch Files & Docker Publish](https://github.com/infinilabs/ci/actions/workflows/easysearch-publish.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/easysearch-publish.yml)&nbsp;[![Products Files & Docker Publish](https://github.com/infinilabs/ci/actions/workflows/publish-docker.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/publish-docker.yml)&nbsp;
[![Test Products Integration](https://github.com/infinilabs/ci/actions/workflows/test-integration-products.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/test-integration-products.yml)&nbsp;[![Products Release Notes and Tag](https://github.com/infinilabs/ci/actions/workflows/release.yml/badge.svg)](https://github.com/infinilabs/ci/actions/workflows/release.yml)

## What is Repo do

> English | [中文](README_zh.md)


*   **`Analysis Plugins Publish`**: Automatically publishes the `analysis-ik`, `analysis-pinyin`, and `analysis-stconvert` plugins.
*   **`Coco App Files Publish`**: Automatically publishes `Coco-AI` snapshot versions; used for manual publishing of release versions.
*   **`Coco Server Files & Docker Publish`**: Automatically publishes `Coco-Server` snapshot version files and Docker images; used for manual publishing of release versions.
*   **`Easysearch Files & Docker Publish`**: Automatically publishes `Easysearch` snapshot version files (including bundle package) and Docker images; used for manual publishing of release versions.
*   **`Products Files & Docker Publish`**: Automatically publishes snapshot version files and Docker images for `Agent`, `Console`, `Gateway`, and `Loadgen`; used for manual publishing of release versions.
*   **`Products Files Publish`**: Manually publishes files for `Agent`, `Console`, `Gateway`, and `Loadgen`.
*   **`Products Integration Test`**: Automatically compiles and tests source code for `Agent`, `Console`, `Gateway`, and `Loadgen`; allows manual triggering of tests against specific downloaded/installed versions.
*   **`Products Release Notes and Tag`**: Used for releases; updates Release Notes, creates Git tags, and updates the `.latest` configuration.