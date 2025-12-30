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
if [[ -z "$signature_darwin_aarch64" ]]; then
  echo "Warning: signature_darwin_aarch64 is empty. The file may not exist."
  exit 1
fi
signature_darwin_x86_64=$(get_signature "Coco-AI_${VERSION}_amd64.app.tar.gz.sig")
if [[ -z "$signature_darwin_x86_64" ]]; then
  echo "Warning: signature_darwin_x86_64 is empty. The file may not exist."
  exit 1
fi
signature_linux_x86_64=$(get_signature "Coco-AI_${VERSION}_amd64.AppImage.sig")
if [[ -z "$signature_linux_x86_64" ]]; then
  echo "Warning: signature_linux_x86_64 is empty. The file may not exist."
  exit 1
fi
signature_linux_aarch64=$(get_signature "Coco-AI_${VERSION}_aarch64.AppImage.sig")
if [[ -z "$signature_linux_aarch64" ]]; then
  echo "Warning: signature_linux_aarch64 is empty. The file may not exist."
  exit 1
fi
signature_windows_x86_64=$(get_signature "Coco-AI_${VERSION}_x64-setup.exe.sig")
if [[ -z "$signature_windows_x86_64" ]]; then
  echo "Warning: signature_windows_x86_64 is empty. The file may not exist."
  exit 1
fi
signature_windows_arm64=$(get_signature "Coco-AI_${VERSION}_arm64-setup.exe.sig")
if [[ -z "$signature_windows_arm64" ]]; then
  echo "Warning: signature_windows_arm64 is empty. The file may not exist."
  exit 1
fi
signature_windows_i686=$(get_signature "Coco-AI_${VERSION}_x86-setup.exe.sig")
if [[ -z "$signature_windows_i686" ]]; then
  echo "Warning: signature_windows_i686 is empty. The file may not exist."
  exit 1
fi


# Create the base JSON structure
cat > .latest.json <<EOF
{
  "version": "${VERSION}",
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

