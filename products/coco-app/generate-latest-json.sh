#!/bin/bash
set -e

# Process PURE_VERSION
base_version="${PURE_VERSION%%-*}"
build_number="${PURE_VERSION##*-}"
PURE_VERSION="${base_version}-${build_number}"

# Check variables
echo "PRE_UPGRADE_PATH: $PRE_UPGRADE_PATH"
echo "UPGRADE_PATH: $UPGRADE_PATH"
echo "VERSION: $VERSION"
echo "PURE_VERSION: $PURE_VERSION"

# Function to fetch signatures with error handling
get_signature() {
  file="$1"
  oss download -c $GITHUB_WORKSPACE/.oss.yml -k $PRE_UPGRADE_PATH -f $file > /dev/null 2>&1
  signature=$(sed -n '/dW50cnVz/,$p' $file)
  echo "$signature"
}

# Get the signature for each platform
signature_darwin_aarch64=$(get_signature "Coco-AI_${VERSION}_arm64.app.tar.gz.sig")
echo "signature_darwin_aarch64: $signature_darwin_aarch64"
signature_darwin_x86_64=$(get_signature "Coco-AI_${VERSION}_amd64.app.tar.gz.sig")
echo "signature_darwin_x86_64: $signature_darwin_x86_64"
signature_linux_x86_64=$(get_signature "Coco-AI_${VERSION}_amd64.AppImage.sig")
echo "signature_linux_x86_64: $signature_linux_x86_64"
signature_linux_aarch64=$(get_signature "Coco-AI_${VERSION}_aarch64.AppImage.sig")
echo "signature_linux_aarch64: $signature_linux_aarch64"
signature_windows_x86_64=$(get_signature "Coco-AI_${VERSION}_x64-setup.exe.sig")
echo "signature_windows_x86_64: $signature_windows_x86_64"
signature_windows_arm64=$(get_signature "Coco-AI_${VERSION}_arm64-setup.exe.sig")
echo "signature_windows_arm64: $signature_windows_arm64"
signature_windows_i686=$(get_signature "Coco-AI_${VERSION}_x86-setup.exe.sig")
echo "signature_windows_i686: $signature_windows_i686"

if [[ -z "$signature_darwin_aarch64" || -z "$signature_darwin_x86_64" || -z "$signature_linux_x86_64" || -z "$signature_linux_aarch64" || -z "$signature_windows_x86_64" || -z "$signature_windows_arm64" || -z "$signature_windows_i686" ]]; then
  echo "Error: One or more signatures are empty. Exiting."
  exit 1
fi

# Create the base JSON structure
cat > .latest.json <<EOF
{
  "version": "${PURE_VERSION}",
  "notes": "",
  "pub_date": "$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')",
  "platforms": {
    "darwin-aarch64": {
      "signature": "${signature_darwin_aarch64}",
      "url": "${RELEASE_URL}/${UPGRADE_PATH}/Coco-AI_${VERSION}_arm64.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "${signature_darwin_x86_64}",
      "url": "${RELEASE_URL}/${UPGRADE_PATH}/Coco-AI_${VERSION}_amd64.app.tar.gz"
    },
    "linux-x86_64": {
      "signature": "${signature_linux_x86_64}",
      "url": "${RELEASE_URL}/${UPGRADE_PATH}/Coco-AI_${VERSION}_amd64.AppImage"
    },
    "linux-aarch64": {
      "signature": "${signature_linux_aarch64}",
      "url": "${RELEASE_URL}/${UPGRADE_PATH}/Coco-AI_${VERSION}_aarch64.AppImage"
    },
    "windows-x86_64": {
      "signature": "${signature_windows_x86_64}",
      "url": "${RELEASE_URL}/${UPGRADE_PATH}/Coco-AI_${VERSION}_x64-setup.exe"
    },
    "windows-aarch64": {
      "signature": "${signature_windows_arm64}",
      "url": "${RELEASE_URL}/${UPGRADE_PATH}/Coco-AI_${VERSION}_arm64-setup.exe"
    },
    "windows-i686": {
      "signature": "${signature_windows_i686}",
      "url": "${RELEASE_URL}/${UPGRADE_PATH}/Coco-AI_${VERSION}_x86-setup.exe"
    }
  }
}
EOF

if [[ "$PRE_UPGRADE_PATH" == *"SNAPSHOT"* ]]; then
  PRE_UPGRADE_PATH="${PRE_UPGRADE_PATH%/*}"
else
  # Release also upload snapshot .latest.json
  SNAPSHOT_UPGRADE_PATH="${PRE_UPGRADE_PATH%/*}"
  (
    TMP_DIR=$(mktemp -d)
    cp .latest.json "$TMP_DIR/.latest.json"
    cd "$TMP_DIR" && sed -i "s/stable/snapshot/g" .latest.json
    echo "Uploading .latest.json to OSS $SNAPSHOT_UPGRADE_PATH"
    oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -k "$SNAPSHOT_UPGRADE_PATH" -f .latest.json
  )
fi
# Upload the JSON file to OSS
echo "Uploading .latest.json to OSS $PRE_UPGRADE_PATH"
oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -k "$PRE_UPGRADE_PATH" -f .latest.json

