#!/bin/bash
set -e

# Check variables
echo "PRE_UPGRADE_PATH: $PRE_UPGRADE_PATH"
echo "RELEASE_UPGRADE_PATH: $RELEASE_UPGRADE_PATH"
echo "VERSION: $VERSION"
echo "PURE_VERSION: $PURE_VERSION"

# Function to fetch signatures with error handling
get_signature() {
  url="$1"
  echo "Fetching signature from: $url"
  signature=$(curl -s "$url")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to download signature from $url"
    return 1
  fi
  echo "Successfully fetched signature from $url"
  echo "$signature"
}

# Construct jq commands for each platform
declare -A platform_signatures
platform_signatures[darwin-aarch64]="$(get_signature "${RELEASE_URL}/coco/app/snapshot/$UPGRADE/Coco-AI_${VERSION}_arm64.app.tar.gz.sig")"
platform_signatures[darwin-x86_64]="$(get_signature "${RELEASE_URL}/coco/app/snapshot/$UPGRADE/Coco-AI_${VERSION}_amd64.app.tar.gz.sig")"
platform_signatures[linux-x86_64]="$(get_signature "${RELEASE_URL}/coco/app/snapshot/$UPGRADE/Coco-AI_${VERSION}_amd64.AppImage.sig")"
platform_signatures[linux-aarch64]="$(get_signature "${RELEASE_URL}/coco/app/snapshot/$UPGRADE/Coco-AI_${VERSION}_arm64.AppImage.sig")"
platform_signatures[windows-x86_64]="$(get_signature "${RELEASE_URL}/coco/app/snapshot/$UPGRADE/Coco-AI_${VERSION}_x64-setup.exe.sig")"
platform_signatures[windows-aarch64]="$(get_signature "${RELEASE_URL}/coco/app/snapshot/$UPGRADE/Coco-AI_${VERSION}_arm64-setup.exe.sig")"
platform_signatures[windows-i686]="$(get_signature "${RELEASE_URL}/coco/app/snapshot/$UPGRADE/Coco-AI_${VERSION}_x86-setup.exe.sig")"

# Create the base JSON structure and insert all at once to avoid multiple writes to file
update_json=$(cat <<EOF
{
  "version": "${PURE_VERSION}",
  "notes": "",
  "pub_date": "$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')",
  "platforms": {
    "darwin-aarch64": {
      "signature": "${platform_signatures[darwin-aarch64]}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_arm64.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "${platform_signatures[darwin-x86_64]}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_amd64.app.tar.gz"
    },
    "linux-x86_64": {
      "signature": "${platform_signatures[linux-x86_64]}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_amd64.AppImage"
    },
    "linux-aarch64": {
      "signature": "${platform_signatures[linux-aarch64]}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_arm64.AppImage"
    },
    "windows-x86_64": {
      "signature": "${platform_signatures[windows-x86_64]}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_x64-setup.exe"
    },
    "windows-aarch64": {
      "signature": "${platform_signatures[windows-aarch64]}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_arm64-setup.exe"
    },
    "windows-i686": {
      "signature": "${platform_signatures[windows-i686]}",
      "url": "${RELEASE_URL}/${RELEASE_UPGRADE_PATH}/Coco-AI_${VERSION}_x86-setup.exe"
    }
  }
}
EOF"

# Output the resulting JSON for debugging
echo "Final update.json:"
echo "$update_json"

# save it to file
echo "$update_json" > .latest.json

# Upload the JSON file to OSS
echo "Uploading .latest.json to OSS"
oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -k "$PRE_UPGRADE_PATH" -f .latest.json