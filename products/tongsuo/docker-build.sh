#!/bin/bash
set -e

# This script runs inside Docker container for static Tongsuo builds
# Environment variables expected:
# - TONGSUO_VERSION: Git tag/branch to build
# - TONGSUO_BASE_CONFIG: Base configuration (e.g., linux-x86_64, linux-aarch64)
# - PUBLISH_VERSION: Maven artifact version
# - PLATFORM_NAME: Platform identifier for output
# - API_VERSION: Optional API version (default: no --api flag)
# - ENABLE_NTLS, ENABLE_SM2, ENABLE_SM3, ENABLE_SM4, ENABLE_DEBUG: Feature flags
# - EXTRA_CONFIG_OPTS: Additional config options

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐳 Docker Build Environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat /etc/os-release | grep PRETTY_NAME

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

# Build Tongsuo
cd /build
echo "Building Tongsuo ${TONGSUO_VERSION}..."
git clone --depth 1 --branch "${TONGSUO_VERSION}" https://github.com/Tongsuo-Project/Tongsuo.git
cd Tongsuo

# Configure with --prefix and base config options
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

if [[ -n "${EXTRA_CONFIG_OPTS}" ]]; then
  CONFIG_OPTS="$CONFIG_OPTS ${EXTRA_CONFIG_OPTS}"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Tongsuo Configuration:"
echo "  ./config $CONFIG_OPTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

./config $CONFIG_OPTS
make -j$(nproc)
make install_sw

# Create symlink if lib64 exists but lib doesn't
if [ -d /root/tongsuo/lib64 ] && [ ! -d /root/tongsuo/lib ]; then
  echo "Creating symlink: lib -> lib64"
  ln -s lib64 /root/tongsuo/lib
fi

echo ""
echo "✅ Tongsuo built successfully"
echo ""
echo "🔐 Tongsuo Version:"
/root/tongsuo/bin/openssl version
echo ""
echo "Installation directory contents:"
ls -lh /root/tongsuo/
if [ -d /root/tongsuo/lib ]; then
  echo "Libraries:"
  ls -lh /root/tongsuo/lib/
elif [ -d /root/tongsuo/lib64 ]; then
  echo "Libraries (lib64):"
  ls -lh /root/tongsuo/lib64/
else
  echo "⚠️  Warning: lib directory not found, checking installation:"
  find /root/tongsuo -name "*.a" -o -name "*.so*"
fi

# Build Java SDK
cd /build/tongsuo-java-sdk

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# Pass Git information to Gradle for MANIFEST.MF
export GIT_COMMIT="${GIT_COMMIT:-unknown}"
export GIT_BRANCH="${GIT_BRANCH:-unknown}"

# Use Gradle init script to apply our publishing config (NO file modifications!)
./gradlew -I /build/products/tongsuo/init.gradle \
          -Pversion="${PUBLISH_VERSION}" \
          -PtongsuoHome=/root/tongsuo \
          -PcheckErrorQueue \
          -PgitCommit="${GIT_COMMIT}" \
          -PgitBranch="${GIT_BRANCH}" \
          :tongsuo-openjdk:publishToMavenLocal

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Build Completed Successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Maven Artifacts:"
find /root/.m2/repository/com/infinilabs/tongsuo-openjdk -type f | head -20
echo ""
echo "📋 Build Information:"
echo "  Platform: ${PLATFORM_NAME}"
echo "  GLIBC Version: $GLIBC_VERSION"
echo "  Tongsuo Version: ${TONGSUO_VERSION}"
echo "  Tongsuo Built:"
/root/tongsuo/bin/openssl version | sed 's/^/    /'
echo "  Publish Version: ${PUBLISH_VERSION}"
echo ""
echo "⚠️  IMPORTANT: This binary requires GLIBC $GLIBC_VERSION or higher"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
