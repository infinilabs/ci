#!/bin/bash
set -e

# Check variables
echo "PRE_UPGRADE_PATH: $PRE_UPGRADE_PATH"
echo "RELEASE_UPGRADE_PATH: $RELEASE_UPGRADE_PATH"
echo "VERSION: $VERSION"
echo "PURE_VERSION: $PURE_VERSION"

# Function to fetch signatures with error handling
# Function to fetch signatures with error handling
get_signature() {
  url="$1"
  signature=$(curl -s "$url")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to download signature from $url"
    return 1
  fi
  echo "$signature"
}

# Get the signature for each platform
signature_darwin_aarch64=$(get_signature "${RELEASE_URL}/$PRE_UPGRADE_PATH/Coco-AI_${VERSION}_arm64.app.tar.gz.sig")
signature_darwin_x86_64=$(get_signature "${RELEASE_URL}/$PRE_UPGRADE_PATH/Coco-AI_${VERSION}_amd64.app.tar.gz.sig")
signature_linux_x86_64=$(get_signature "${RELEASE_URL}/$PRE_UPGRADE_PATH/Coco-AI_${VERSION}_amd64.AppImage.sig")
signature_linux_aarch64=$(get_signature "${RELEASE_URL}/$PRE_UPGRADE_PATH/Coco-AI_${VERSION}_amd64.AppImage.sig")
signature_windows_x86_64=$(get_signature "${RELEASE_URL}/$PRE_UPGRADE_PATH/Coco-AI_${VERSION}_x64-setup.exe.sig")
signature_windows_arm64=$(get_signature "${RELEASE_URL}/$PRE_UPGRADE_PATH/Coco-AI_${VERSION}_arm64-setup.exe.sig")
signature_windows_i686=$(get_signature "${RELEASE_URL}/$PRE_UPGRADE_PATH/Coco-AI_${VERSION}_x86-setup.exe.sig")

# Create the base JSON structure
cat > .latest.json <<EOF
{
  "version": "${PURE_VERSION}",
  "notes": "",
  "pub_date": "$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')",
  "platforms": {
    "darwin-aarch64": {
      "signature": "${signature_darwin_aarch64}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_arm64.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "${signature_darwin_x86_64}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_amd64.app.tar.gz"
    },
    "linux-x86_64": {
      "signature": "${signature_linux_x86_64}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_amd64.AppImage"
    },
    "linux-aarch64": {
      "signature": "${signature_linux_aarch64}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_arm64.AppImage"
    },
    "windows-x86_64": {
      "signature": "${signature_windows_x64}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_x64-setup.exe"
    },
    "windows-aarch64": {
      "signature": "${signature_windows_arm64}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_arm64-setup.exe"
    },
    "windows-i686": {
      "signature": "${signature_windows_i686}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_x86-setup.exe"
    }
  }
}
EOF

# Upload the JSON file to OSS
echo "Uploading .latest.json to OSS"
oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -k "$PRE_UPGRADE_PATH" -f .latest.json