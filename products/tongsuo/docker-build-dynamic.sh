#!/bin/bash
set -e

# This script runs inside Docker container for dynamic Tongsuo builds
# Environment variables expected:
# - TONGSUO_VERSION: Git tag/branch to build
# - TONGSUO_BASE_CONFIG: Base configuration (e.g., linux-x86_64, linux-aarch64)
# - PUBLISH_VERSION: Maven artifact version
# - PLATFORM_NAME: Platform identifier for output
# - API_VERSION: Optional API version (default: no --api flag)
# - ENABLE_NTLS, ENABLE_SM2, ENABLE_SM3, ENABLE_SM4, ENABLE_DEBUG: Feature flags
# - EXTRA_CONFIG_OPTS: Additional config options

# Set library path for dynamic linking (needed throughout the build)
export LD_LIBRARY_PATH=/root/tongsuo/lib64:/root/tongsuo/lib:$LD_LIBRARY_PATH

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐳 Docker Build Environment (Dynamic)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat /etc/os-release | grep -E "PRETTY_NAME|VERSION_ID"
GLIBC_VERSION=$(ldd --version 2>&1 | awk 'NR==1 {print $NF}')
echo "GLIBC Version: $GLIBC_VERSION"
echo "Architecture: $(uname -m)"
if command -v openssl >/dev/null 2>&1; then
  echo "OpenSSL Version: $(openssl version)"
fi

echo ""
echo "⚠️  Binaries will require GLIBC $GLIBC_VERSION or higher"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y build-essential perl patchelf git wget curl openjdk-11-jdk-headless

# Build Tongsuo (dynamic/shared library)
cd /build
echo "Building Tongsuo ${TONGSUO_VERSION} (dynamic)..."
git clone --depth 1 --branch "${TONGSUO_VERSION}" https://github.com/Tongsuo-Project/Tongsuo.git
cd Tongsuo

# Configure with shared library support
CONFIG_OPTS="--prefix=/root/tongsuo ${TONGSUO_BASE_CONFIG}"

# Add API version parameter if specified
if [[ "${API_VERSION}" != "default" ]]; then
  CONFIG_OPTS="$CONFIG_OPTS --api=${API_VERSION}"
  echo "Using --api=${API_VERSION} for API compatibility"
else
  echo "Using default API (no --api parameter)"
fi

if [[ "${ENABLE_NTLS}" == "true" ]]; then
  CONFIG_OPTS="$CONFIG_OPTS enable-ntls"
else
  CONFIG_OPTS="$CONFIG_OPTS no-ntls"
fi

if [[ "${ENABLE_SM2}" == "true" ]]; then
  CONFIG_OPTS="$CONFIG_OPTS enable-sm2"
fi

if [[ "${ENABLE_SM3}" == "true" ]]; then
  CONFIG_OPTS="$CONFIG_OPTS enable-sm3"
fi

if [[ "${ENABLE_SM4}" == "true" ]]; then
  CONFIG_OPTS="$CONFIG_OPTS enable-sm4"
fi

if [[ "${ENABLE_DEBUG}" == "true" ]]; then
  CONFIG_OPTS="$CONFIG_OPTS --debug"
fi

echo "Configuration: $CONFIG_OPTS"
./config $CONFIG_OPTS shared
make -j$(nproc)
make install_sw

# Create lib symlink if lib64 exists (for Gradle compatibility)
if [ -d /root/tongsuo/lib64 ] && [ ! -e /root/tongsuo/lib ]; then
  ln -s lib64 /root/tongsuo/lib
  echo "Created symlink: /root/tongsuo/lib -> lib64"
fi

# Show Tongsuo version
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Tongsuo build completed (dynamic):"
/root/tongsuo/bin/openssl version
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Build Java SDK (dynamic linking)
cd /build/tongsuo-java-sdk

# Auto-detect JAVA_HOME based on architecture
if [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
elif [ -d "/usr/lib/jvm/java-11-openjdk-arm64" ]; then
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64
elif [ -d "/usr/lib/jvm/java-11-openjdk-aarch64" ]; then
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-aarch64
else
  # Fallback: find any java-11-openjdk directory
  export JAVA_HOME=$(find /usr/lib/jvm -maxdepth 1 -name "java-11-openjdk-*" -type d | head -1)
fi

echo "Using JAVA_HOME: $JAVA_HOME"

# Pass Git information to Gradle for MANIFEST.MF
export GIT_COMMIT="${GIT_COMMIT:-unknown}"
export GIT_BRANCH="${GIT_BRANCH:-unknown}"

# Use Gradle init script to apply our publishing config (NO file modifications!)
./gradlew -I /build/products/tongsuo/init.gradle \
          -Pversion="${PUBLISH_VERSION}" \
          -PtongsuoHome=/root/tongsuo \
          -PtongsuoDynamic=1 \
          -PcheckErrorQueue \
          -PgitCommit="${GIT_COMMIT}" \
          -PgitBranch="${GIT_BRANCH}" \
          :tongsuo-openjdk:publishToMavenLocal

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Build Completed Successfully (Dynamic)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Maven Artifacts:"
find /root/.m2/repository/com/infinilabs/tongsuo-openjdk -type f | head -20
echo ""
echo "📋 Build Information:"
echo "  Platform: ${PLATFORM_NAME}"
echo "  GLIBC Version: $GLIBC_VERSION"
echo "  Tongsuo Version: ${TONGSUO_VERSION}"
echo "  Tongsuo Built:"
/root/tongsuo/bin/openssl version | sed "s/^/    /"
echo "  Publish Version: ${PUBLISH_VERSION}"
echo "  Linking: Dynamic"
echo ""
echo "⚠️  IMPORTANT: This binary requires GLIBC $GLIBC_VERSION or higher"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy artifacts to mounted volume for upload
echo ""
echo "📤 Copying artifacts to host..."
mkdir -p /build/tongsuo-java-sdk/artifacts
cp -r /root/.m2/repository/com/infinilabs/tongsuo-openjdk/"${PUBLISH_VERSION}" /build/tongsuo-java-sdk/artifacts/ || true
