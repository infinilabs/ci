# Tongsuo Java SDK Maven Central Publishing

本文档说明如何通过 infinilabs/ci 仓库发布 Tongsuo Java SDK 到 Maven Central。

## 发布配置

### Group ID 和 Artifact ID

- **Group ID**: `com.infinilabs`
- **Artifact ID**: `tongsuo-openjdk`
- **平台分类器**: 
  - `linux-x86_64` - Linux x86-64 with static linking
  - `linux-aarch_64` - Linux ARM64 with static linking
  - `osx-x86_64` - macOS Intel
  - `osx-aarch_64` - macOS Apple Silicon
  - `windows-x86_64` - Windows x64

每个平台会发布三个 artifact：
- `tongsuo-openjdk-{version}-{platform}.jar` - 主 JAR（包含 native 库）
- `tongsuo-openjdk-{version}-{platform}-sources.jar` - 源代码
- `tongsuo-openjdk-{version}-{platform}-javadoc.jar` - JavaDoc

### 构建流程

```
┌─────────────────────────────────────────┐
│ 1. Build All Platforms (5 jobs)        │
│    - Linux x86_64                       │
│    - Linux aarch64 (cross-compile)      │
│    - macOS x86_64 (cross-compile)       │
│    - macOS aarch64 (native)             │
│    - Windows x86_64 (MSVC)              │
│                                         │
│    每个平台生成完整的 Maven 仓库:        │
│    - JAR with platform classifier       │
│    - sources JAR                        │
│    - javadoc JAR                        │
│    - POM file                           │
│    - GPG signatures (.asc)              │
└─────────────┬───────────────────────────┘
              │
              v
┌─────────────────────────────────────────┐
│ 2. Merge & Publish to Maven Central    │
│    - 合并所有平台的 Maven 仓库           │
│    - 验证必需文件（POM, JAR, 签名）      │
│    - 打包成符合 Maven Central 的 ZIP    │
│    - 上传到 Maven Central Portal        │
└─────────────────────────────────────────┘
```

## 前置要求

### 必需的 GitHub Secrets

在使用此 workflow 之前，需要在 infinilabs/ci 仓库配置以下 secrets：

#### 1. 仓库访问
- `SSH_PRIVATE_KEY` - 用于 checkout infinilabs/tongsuo-java-sdk 的 SSH 私钥

#### 2. GPG 签名
- `GPG_PRIVATE_KEY` - GPG 私钥（ASCII armored 格式）
- `GPG_PASSPHRASE` - GPG 私钥密码

#### 3. Maven Central 凭证
- `OSSRH_USERNAME` - Maven Central (Sonatype) 用户名
- `OSSRH_PASSWORD` - Maven Central (Sonatype) 密码

## 使用方法

### 步骤 1: 触发发布

1. 进入 infinilabs/ci 仓库的 GitHub Actions 页面
2. 选择 "Publish Tongsuo Java SDK to Maven Central" workflow
3. 点击 "Run workflow"
4. 配置参数（通过直观的界面）：

#### 基础参数

- **PUBLISH_VERSION**: 版本号（如 `1.1.0`）
- **BRANCH**: tongsuo-java-sdk 分支（如 `master` 或 `multiplatform`）
- **TONGSUO_VERSION**: Tongsuo 版本（如 `master`, `8.4-stable`, `8.3.3`）

#### API 版本选择（下拉选择）

- **API_VERSION**: 
  - `default` - Tongsuo 默认 API（推荐，不添加 --api 参数）
  - `1.1.1` - OpenSSL 1.1.1 兼容 ⭐
  - `1.0.2` - OpenSSL 1.0.2 兼容

#### 功能开关（Checkbox 复选框）

- ☑ **ENABLE_NTLS**: 启用国密 TLS 协议（默认开启）
- ☐ **ENABLE_SM2**: 启用 SM2 算法
- ☐ **ENABLE_SM3**: 启用 SM3 哈希算法
- ☐ **ENABLE_SM4**: 启用 SM4 对称加密
- ☐ **ENABLE_DEBUG**: 启用调试符号（用于 gdb/lldb）

#### 高级选项（可选）

- **EXTRA_CONFIG_OPTS**: 其他编译选项（如 `--symbol-prefix=tongsuo_`）

#### 构建环境选择 ⭐ 新功能

- **USE_DOCKER_BUILD**: 使用 Docker 构建 Linux 平台（推荐）
  - ✅ `true` - Docker 构建（推荐，精确控制 GLIBC）⭐
  - ❌ `false` - 原生构建（使用 GitHub Actions runner）

- **LINUX_DOCKER_IMAGE**: Docker 镜像（当 USE_DOCKER_BUILD=true 时）
  - `ubuntu:18.04` - **GLIBC 2.27** （推荐，最大兼容性）⭐⭐⭐
  - `ubuntu:20.04` - GLIBC 2.31
  - `ubuntu:22.04` - GLIBC 2.35
  - `ubuntu:24.04` - GLIBC 2.39

**为什么使用 Docker 构建？**

| 构建方式 | 优势 | 劣势 | 推荐 |
|---------|------|------|------|
| Docker 构建 | ✅ 可使用 Ubuntu 18.04（GLIBC 2.27）<br>✅ 精确控制构建环境<br>✅ 支持老系统（CentOS 7.6+） | ⚠️ 构建时间稍长 | ⭐⭐⭐ 生产环境 |
| 原生构建 | ✅ 构建速度快 | ❌ 受限于 GitHub Actions runner<br>❌ 最低 ubuntu-20.04（GLIBC 2.31） | 测试环境 |

**Docker 镜像 GLIBC 版本对照**

| Docker 镜像 | GLIBC 版本 | 兼容的最老系统 |
|------------|-----------|--------------|
| ubuntu:18.04 | **2.27** | **CentOS 7.6+, RHEL 7.6+, Debian 10+** ⭐ |
| ubuntu:20.04 | 2.31 | CentOS 8+, RHEL 8+, Debian 11+ |
| ubuntu:22.04 | 2.35 | Ubuntu 22.04+, Debian 12+ |
| ubuntu:24.04 | 2.39 | Ubuntu 24.04+ |

### 常见配置场景

#### 场景 1: 最大兼容性（生产推荐）✓✓✓
```
API_VERSION: default
USE_DOCKER_BUILD: true
LINUX_DOCKER_IMAGE: ubuntu:18.04
☑ ENABLE_NTLS
适用于: 生产环境，需要在老系统运行（CentOS 7.6+, RHEL 7.6+）
GLIBC 要求: 2.27+
```

#### 场景 2: 标准国密构建
```
API_VERSION: default
USE_DOCKER_BUILD: true
LINUX_DOCKER_IMAGE: ubuntu:20.04
☑ ENABLE_NTLS
适用于: 标准国密应用（CentOS 8+, RHEL 8+）
GLIBC 要求: 2.31+
```

#### 场景 3: OpenSSL 1.1.1 兼容 + 国密
```
API_VERSION: 1.1.1
USE_DOCKER_BUILD: true
LINUX_DOCKER_IMAGE: ubuntu:18.04
☑ ENABLE_NTLS
适用于: 需要兼容 OpenSSL 1.1.1 API 的老系统
GLIBC 要求: 2.27+
```

#### 场景 4: 完整国密算法支持
```
API_VERSION: default
USE_DOCKER_BUILD: true
LINUX_DOCKER_IMAGE: ubuntu:18.04
☑ ENABLE_NTLS
☑ ENABLE_SM2
☑ ENABLE_SM3
☑ ENABLE_SM4
适用于: 需要完整国密算法栈
GLIBC 要求: 2.27+
```

#### 场景 5: 快速测试（原生构建）
```
API_VERSION: default
USE_DOCKER_BUILD: false
☑ ENABLE_NTLS
适用于: 快速测试，不关心老系统兼容性
GLIBC 要求: 2.31+（GitHub Actions runner）
```

#### 场景 4: 纯 OpenSSL 兼容（无国密）
```
API_VERSION: default
☐ ENABLE_NTLS (取消勾选)
适用于: 不需要国密功能
```

#### 场景 5: 调试构建
```
API_VERSION: default
☑ ENABLE_NTLS
☑ ENABLE_DEBUG
适用于: Native 代码调试
```

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
                ├── tongsuo-openjdk-1.1.0-linux-x86_64.jar
                ├── tongsuo-openjdk-1.1.0-linux-x86_64.jar.asc
                ├── tongsuo-openjdk-1.1.0-linux-x86_64-sources.jar
                ├── tongsuo-openjdk-1.1.0-linux-x86_64-sources.jar.asc
                ├── tongsuo-openjdk-1.1.0-linux-x86_64-javadoc.jar
                ├── tongsuo-openjdk-1.1.0-linux-x86_64-javadoc.jar.asc
                ├── tongsuo-openjdk-1.1.0-osx-aarch_64.jar
                ├── ... (其他平台类似)
                └── tongsuo-openjdk-1.1.0.pom
```

## 使用已发布的 Artifact

### Gradle

```gradle
dependencies {
    // 使用平台特定 JAR（推荐）
    implementation 'com.infinilabs:tongsuo-openjdk:1.1.0:linux-x86_64'
    
    // 或根据运行平台自动选择
    implementation('com.infinilabs:tongsuo-openjdk:1.1.0') {
        // 需要配置 Maven classifier resolution
    }
}
```

### Maven

```xml
<dependency>
  <groupId>com.infinilabs</groupId>
  <artifactId>tongsuo-openjdk</artifactId>
  <version>1.1.0</version>
  <classifier>linux-x86_64</classifier>
</dependency>
```

**注意**: 当前版本发布的是平台特定的 JAR。每个 JAR 都包含对应平台的 native 库。用户需要根据目标平台选择合适的 classifier。

## 技术细节

### Repository Checkout

Workflow 使用标准的 `actions/checkout@v6` 方式 checkout tongsuo-java-sdk 仓库：
- 使用 `SSH_PRIVATE_KEY` secret 进行 SSH 认证
- 支持指定分支通过 workflow 输入参数

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

### GLIBC 兼容性

**重要**: Linux 平台的二进制文件依赖编译环境的 GLIBC 版本。

#### GLIBC 版本对应关系

| Ubuntu 版本 | GLIBC 版本 | 发布日期 | 推荐使用场景 |
|------------|-----------|---------|------------|
| ubuntu-20.04 | 2.31 | 2020-04 | **推荐** - 兼容大多数生产环境 |
| ubuntu-22.04 | 2.35 | 2022-04 | 较新环境 |
| ubuntu-24.04 | 2.39 | 2024-04 | 最新环境 |

#### 兼容性规则

- ✅ 在**较老** GLIBC 上编译的程序可以在**较新** GLIBC 上运行
- ❌ 在**较新** GLIBC 上编译的程序**不能**在**较老** GLIBC 上运行

#### 常见 Linux 发行版的 GLIBC 版本

| 发行版 | GLIBC 版本 | 需要的最低编译环境 |
|--------|-----------|------------------|
| CentOS 7 / RHEL 7 | 2.17 | 不支持（太老）|
| CentOS 8 / RHEL 8 | 2.28 | ubuntu-20.04 |
| Rocky Linux 9 | 2.34 | ubuntu-20.04 或 ubuntu-22.04 |
| Debian 11 (Bullseye) | 2.31 | ubuntu-20.04 |
| Debian 12 (Bookworm) | 2.36 | ubuntu-22.04 |
| Ubuntu 20.04 | 2.31 | ubuntu-20.04 |
| Ubuntu 22.04 | 2.35 | ubuntu-22.04 |
| Ubuntu 24.04 | 2.39 | ubuntu-24.04 |

#### 如何检查系统的 GLIBC 版本

```bash
ldd --version
# 或
/lib/x86_64-linux-gnu/libc.so.6
```

#### 建议

- 🎯 **生产环境发布**: 使用 `ubuntu-20.04`（GLIBC 2.31）获得最大兼容性
- 🔬 **测试环境**: 可以使用 `ubuntu-22.04` 或 `ubuntu-24.04`
- ⚠️ **注意**: 如果目标用户包含 CentOS 8 / RHEL 8，必须使用 `ubuntu-20.04`

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
