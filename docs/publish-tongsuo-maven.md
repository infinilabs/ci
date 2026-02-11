# Tongsuo Java SDK Maven Central Publishing

本文档说明如何通过 infinilabs/ci 仓库发布 Tongsuo Java SDK 到 Maven Central。

## 发布配置

### Group ID 和 Artifact ID

- **Group ID**: `com.infinilabs`
- **Artifact ID**: `tongsuo-openjdk`
- **Classifiers**: 
  - `linux-x86_64`
  - `linux-aarch_64`
  - `osx-x86_64`
  - `osx-aarch_64`
  - `windows-x86_64`
  - `static-uber` (自包含，约 15-20 MB)
  - `dynamic-uber` (需要系统安装 Tongsuo，约 1-2 MB)

### 构建流程

```
┌─────────────────────────────────────────┐
│ 1. Build All Platforms (5 jobs)        │
│    - Linux x86_64                       │
│    - Linux aarch64 (cross-compile)      │
│    - macOS x86_64                       │
│    - macOS aarch64                      │
│    - Windows x86_64                     │
│    每个平台生成:                         │
│    - main JAR                           │
│    - sources JAR                        │
│    - javadoc JAR                        │
└─────────────┬───────────────────────────┘
              │
              v
┌─────────────────────────────────────────┐
│ 2. Build Uber JARs                      │
│    - Static uber (所有平台 native libs)  │
│    - Dynamic uber (只有 Java 类)        │
└─────────────┬───────────────────────────┘
              │
              v
┌─────────────────────────────────────────┐
│ 3. Publish to Maven Central             │
│    - 合并所有 artifacts                  │
│    - GPG 签名                            │
│    - 生成 Maven metadata                 │
│    - 打包成 ZIP bundle                   │
│    - 上传到 Maven Central Portal        │
└─────────────────────────────────────────┘
```

## 使用方法

### 步骤 1: 触发发布

1. 进入 infinilabs/ci 仓库的 GitHub Actions 页面
2. 选择 "Publish Tongsuo Java SDK to Maven Central" workflow
3. 点击 "Run workflow"
4. 填写参数：
   - **PUBLISH_VERSION**: 版本号（如 `1.1.0`）
   - **BRANCH**: 要构建的分支（如 `master` 或 `multiplatform`）

### 步骤 2: 等待构建

整个流程大约需要 **1-1.5 小时**：

- 平台构建: ~10-15 分钟/平台（并行）
- Uber JAR 构建: ~5 分钟
- 发布和签名: ~5-10 分钟

### 步骤 3: 验证发布

发布成功后：

1. 检查 [Maven Central Portal](https://central.sonatype.com/)
2. 搜索 `com.infinilabs:tongsuo-openjdk`
3. 验证所有 artifacts 都已上传

### 步骤 4: 下载 Bundle（可选）

Workflow 会将 bundle ZIP 作为 artifact 上传，保留 30 天。如果需要手动检查或重新上传：

1. 进入 workflow run 页面
2. 下载 `maven-bundle` artifact
3. 解压查看内容

## Maven Central Bundle 结构

```
tongsuo-openjdk-1.1.0.zip
└── com/
    └── infinilabs/
        └── tongsuo-openjdk/
            ├── maven-metadata.xml
            ├── maven-metadata.xml.md5
            ├── maven-metadata.xml.sha1
            └── 1.1.0/
                ├── tongsuo-openjdk-1.1.0.pom
                ├── tongsuo-openjdk-1.1.0.pom.asc
                ├── tongsuo-openjdk-1.1.0.pom.md5
                ├── tongsuo-openjdk-1.1.0.pom.sha1
                │
                ├── tongsuo-openjdk-1.1.0-linux-x86_64.jar
                ├── tongsuo-openjdk-1.1.0-linux-x86_64.jar.asc
                ├── tongsuo-openjdk-1.1.0-linux-x86_64-sources.jar
                ├── tongsuo-openjdk-1.1.0-linux-x86_64-sources.jar.asc
                ├── tongsuo-openjdk-1.1.0-linux-x86_64-javadoc.jar
                ├── tongsuo-openjdk-1.1.0-linux-x86_64-javadoc.jar.asc
                │
                ├── ... (其他平台类似)
                │
                ├── tongsuo-openjdk-1.1.0-static-uber.jar
                ├── tongsuo-openjdk-1.1.0-static-uber.jar.asc
                ├── tongsuo-openjdk-1.1.0-dynamic-uber.jar
                └── tongsuo-openjdk-1.1.0-dynamic-uber.jar.asc
```

## 使用已发布的 Artifact

### Gradle

```gradle
dependencies {
    // 平台特定 JAR
    implementation 'com.infinilabs:tongsuo-openjdk:1.1.0:linux-x86_64'
    
    // 或使用 static uber JAR (推荐)
    implementation 'com.infinilabs:tongsuo-openjdk:1.1.0:static-uber'
    
    // 或使用 dynamic uber JAR (需要系统安装 Tongsuo)
    implementation 'com.infinilabs:tongsuo-openjdk:1.1.0:dynamic-uber'
}
```

### Maven

```xml
<dependency>
  <groupId>com.infinilabs</groupId>
  <artifactId>tongsuo-openjdk</artifactId>
  <version>1.1.0</version>
  <classifier>static-uber</classifier>
</dependency>
```

## 技术细节

### SSH Clone

Workflow 使用 SSH 方式 clone tongsuo-java-sdk 仓库：
- 使用 `SSH_GIT_REPO` secret
- 使用 `SSH_PRIVATE_KEY` 和 `SSH_CONFIG` secrets

### GPG 签名

所有 artifacts 都会被 GPG 签名：
- 使用 `GPG_PRIVATE_KEY` secret
- 使用 `GPG_PASSPHRASE` secret

### Maven Central 凭证

发布使用 Maven Central Portal API：
- 使用 `OSSRH_USERNAME` secret
- 使用 `OSSRH_PASSWORD` secret

### Bootstrap 和 Connect

Workflow 使用 infinilabs/ci 的 bootstrap 容器和 connect 工具来处理网络连接。

### 平台构建特点

- **Linux aarch64**: 使用交叉编译（gcc-aarch64-linux-gnu）+ QEMU
- **macOS**: 在对应架构的 runner 上原生构建
- **Windows**: 使用 Visual Studio + MSVC

### 自定义 Group ID

通过 `products/tongsuo/build.gradle` 配置文件覆盖原始仓库的 group ID：
```gradle
allprojects {
    group = 'com.infinilabs'
}
```

## 故障排除

### 平台构建失败

检查：
1. Tongsuo 构建是否成功
2. 交叉编译工具是否正确安装（Linux ARM64）
3. 环境变量 `TONGSUO_HOME` 是否正确设置

### GPG 签名失败

确保：
1. `GPG_PRIVATE_KEY` 包含完整密钥
2. `GPG_PASSPHRASE` 正确
3. 密钥未过期

### 上传失败

检查：
1. Maven Central 凭证是否正确
2. Bundle ZIP 格式是否正确
3. 是否所有必需文件都已签名

### SSH Clone 失败

确保：
1. `SSH_PRIVATE_KEY` 有权限访问 tongsuo-java-sdk 仓库
2. `SSH_CONFIG` 配置正确

## 与官方版本的关系

| 项目 | 官方版本 | infinilabs 版本 |
|------|---------|----------------|
| Group ID | `net.tongsuo` | `com.infinilabs` |
| 仓库 | Tongsuo-Project/tongsuo-java-sdk | infinilabs/tongsuo-java-sdk |
| 发布渠道 | 官方 CI/CD | infinilabs/ci |
| 功能 | 相同 | 相同 |

**注意**: 两个版本的代码和功能完全相同，只是 Maven 坐标不同。infinilabs 版本从官方 fork，主要用于 infinilabs 自己的项目依赖。

## 参考资料

- [tongsuo-java-sdk 仓库](https://github.com/Tongsuo-Project/tongsuo-java-sdk)
- [Maven Central Portal](https://central.sonatype.com/)
- [Maven Central Publishing Guide](https://central.sonatype.org/publish/publish-guide/)
