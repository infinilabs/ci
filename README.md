<p align="center">
<a href="https://infinilabs.com/"><img src="docs/images/infinilabs.svg" alt="banner" width="200px"></a>
</p>

<p align="center">
<b>The Github Actions for <i>Build, Publish and Testing</i> management</b>
</p>

## What is Repo do

> English | [中文](README_zh.md)


- `Analysis Plugins Publish`: Automatically publishes the `analysis-ik`, `analysis-pinyin`, and `analysis-stconvert` plugins.
- `Coco App Release Repackage` Manually triggered repackage of `Release` files
- `Coco Server Files & Docker Publish`: Automatically publishes `Coco-Server` snapshot builds and Docker images.  Can be manually triggered to publish `Release` versions.
- `Easysearch Files & Docker Publish`: Automatically publishes `Easysearch` snapshot builds (including bundle packages) and Docker images. Can be manually triggered to publish `Release` versions.
- `Products Files & Docker Publish`: Automatically publishes `Agent/Console/Gateway/Loadgen` snapshot builds and Docker images. Can be manually triggered to publish `Release` versions.
- `Products Files Publish`: Manually triggered publication of `Agent/Console/Gateway/Loadgen` files.
- `Products Integration Test`: Automatically compiles and tests the source code for `Agent/Console/Gateway/Loadgen`. Can be manually triggered to download and install a specific version for testing.
- `Products Release Notes and Tag`: Used for releasing versions, updating `Release Notes`, `Tag`, and `.latest` configuration.