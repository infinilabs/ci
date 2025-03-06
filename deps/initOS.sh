#!/bin/bash
set -euo pipefail

# --- Configuration ---
FROM=${FROM:-almalinux}
TO="infinios"
YEAR=$(date +%Y)
VENDOR="INFINI"
OU="Labs"

# --- File Paths ---
SYSTEM_RELEASE_CPE="system-release-cpe"
FROM_RELEASE_FILE="${FROM}-release"
TO_RELEASE_FILE="${TO}-release"
SYSTEM_RELEASE_LINK="system-release"
REDHAT_RELEASE_LINK="redhat-release"
OS_RELEASE_FILE="os-release"
BUILDTIME_FILE="BUILDTIME"

# --- Parse command-line arguments (optional) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      FROM="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--from <from_distro>]"
      echo "  --from <from_distro>  Original distribution name (default: ${FROM:-almalinux})"
      exit 0
      ;;
    *)
      echo "Invalid option: $1" >&2
      exit 1
      ;;
  esac
done

# --- Input Validation ---
if [[ -z "$FROM" ]]; then
  echo "ERROR: FROM variable cannot be empty." >&2
  exit 1
fi

# --- Script Logic ---

date "+%Y%m%d_%H%M" > "/etc/$BUILDTIME_FILE"

# Modify system-release-cpe
if [ -f "/etc/$SYSTEM_RELEASE_CPE" ]; then
  sed -i "s/${FROM}/${TO}/g" "/etc/$SYSTEM_RELEASE_CPE"
fi

# Remove old release file
if [ -f "/etc/$FROM_RELEASE_FILE" ]; then
  rm -f "/etc/$FROM_RELEASE_FILE"
fi

# Create new release file
echo "$VENDOR OS release $YEAR ($VENDOR $OU)" > "/etc/$TO_RELEASE_FILE"

# Update symlinks
if [ -L "/etc/$SYSTEM_RELEASE_LINK" ]; then
  cd /etc && unlink "$SYSTEM_RELEASE_LINK" && ln -s "$TO_RELEASE_FILE" "$SYSTEM_RELEASE_LINK"
fi

if [ -L "/etc/$REDHAT_RELEASE_LINK" ]; then
  cd /etc && unlink "$REDHAT_RELEASE_LINK" && ln -s "$TO_RELEASE_FILE" "$REDHAT_RELEASE_LINK"
fi

# Create /etc/os-release
cat <<EOF > "/etc/$OS_RELEASE_FILE"
NAME="$VENDOR OS"
VERSION="$YEAR"
ID="$TO"
VERSION_ID="$YEAR"
PLATFORM_ID="platform:$TO"
PRETTY_NAME="$VENDOR OS release $YEAR ($VENDOR $OU)"
ANSI_COLOR="0;34"
EOF

echo "Successfully changed OS identification from $FROM to $TO."
exit 0