#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

# --- Configuration ---
# Get versions from environment variables, with defaults for local testing.
ES_VERSION_FULL="${EZS_VER:-7.10.2-1}"
AGENT_VERSION_FULL="${AGENT_VERSION:-1.29.8-2197}"
PNAME="${PNAME:-elasticsearch}" # Product name from environment

# The IK plugin URL only needs the base version (e.g., 7.10.2), not the build number.
# This removes the shortest suffix starting with a hyphen (e.g., "-1").
ES_VERSION_BASE=${ES_VERSION_FULL%%-*}

# Download Source URLs
ES_BASE_URL="https://artifacts.elastic.co/downloads/elasticsearch"
# Use RELEASE_URL from GitHub Actions environment, with a fallback.
RELEASE_URL_BASE="${RELEASE_URL:-https://release.infinilabs.com}"
AGENT_BASE_URL="${RELEASE_URL_BASE}/agent"
IK_PLUGIN_URL="${RELEASE_URL_BASE}/analysis-ik/stable/elasticsearch-analysis-ik-${ES_VERSION_BASE}.zip"

# Directories
WORK_DIR="${GITHUB_WORKSPACE:-.}/products/$PNAME"
DOWNLOAD_DIR="${GITHUB_WORKSPACE:-.}/dest"

# --- Script Start ---
echo "======== Preparing Build Environment ========"
echo "Elasticsearch Version: $ES_VERSION_FULL"
echo "Agent Version:         $AGENT_VERSION_FULL"
echo "Base Work Directory:   $WORK_DIR"
echo "Download Cache Dir:    $DOWNLOAD_DIR"
echo "============================================="

# Ensure necessary directories exist
mkdir -p "$WORK_DIR" "$DOWNLOAD_DIR"
cd "$WORK_DIR"

# --- Helper Functions ---

# Downloads a file if it doesn't already exist in the download directory.
# Arguments:
#   $1: URL to download from
#   $2: Destination file path
download_file() {
  local url="$1"
  local dest_file="$2"

  if [ -f "$dest_file" ]; then
    echo "File already exists, skipping download: $(basename "$dest_file")"
  else
    echo "Downloading: $url"
    # -L: Follow redirects
    # -f: Fail silently on server errors (important for 'set -e')
    # -sS: Be silent but show errors
    # -o: Output to file
    if ! curl -LfsS "$url" -o "$dest_file"; then
      echo "ERROR: Download failed for $url" >&2
      # Clean up incomplete file on failure
      rm -f "$dest_file"
      return 1
    fi
  fi
}

# --- Main Logic ---

# 1. Download the IK plugin (shared by all architectures)
IK_PLUGIN_FILENAME="elasticsearch-analysis-ik-${ES_VERSION_BASE}.zip"
IK_PLUGIN_PATH="$DOWNLOAD_DIR/$IK_PLUGIN_FILENAME"
echo "--- Preparing shared plugins ---"
download_file "$IK_PLUGIN_URL" "$IK_PLUGIN_PATH"

# 2. Process each architecture
for arch in amd64 arm64; do
  echo -e "\n--- Processing architecture: $arch ---"

  # Map friendly architecture names to Elasticsearch distribution names
  es_arch=""
  case "$arch" in
    amd64) es_arch="x86_64" ;;
    arm64) es_arch="aarch64" ;;
    *)
      echo "ERROR: Unsupported architecture '$arch'" >&2
      exit 1
      ;;
  esac

  # --- A. Download and Extract Elasticsearch ---
  ES_FILENAME="${PNAME}-oss-${ES_VERSION_BASE}-linux-${es_arch}.tar.gz"
  ES_URL="${ES_BASE_URL}/${ES_FILENAME}"
  ES_FILE_PATH="$DOWNLOAD_DIR/$ES_FILENAME"
  ES_EXTRACT_DIR="$WORK_DIR/${PNAME}-${arch}"

  download_file "$ES_URL" "$ES_FILE_PATH"

  echo "Extracting Elasticsearch for $arch..."
  mkdir -p "$ES_EXTRACT_DIR"
  # --strip-components=1 removes the top-level directory (e.g., elasticsearch-7.10.2/) from the archive
  tar -zxf "$ES_FILE_PATH" -C "$ES_EXTRACT_DIR" --strip-components=1

  # --- B. Download and Extract Agent ---
  AGENT_FILENAME="agent-${AGENT_VERSION_FULL}-linux-${arch}.tar.gz"
  AGENT_FILE_PATH="$DOWNLOAD_DIR/$AGENT_FILENAME"
  AGENT_EXTRACT_DIR="$WORK_DIR/agent-${arch}"
  AGENT_URL_FOUND=false

  # Try to find the agent in 'stable' or 'snapshot' channels
  for channel in stable snapshot; do
      AGENT_URL="${AGENT_BASE_URL}/${channel}/${AGENT_FILENAME}"
      HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$AGENT_URL" || true)
      if [[ "$HTTP_STATUS" == "200" ]]; then
          if download_file "$AGENT_URL" "$AGENT_FILE_PATH"; then
              AGENT_URL_FOUND=true
              break # Exit loop once successfully downloaded
          fi
      fi
  done

  if ! $AGENT_URL_FOUND; then
      echo "ERROR: Agent not found in stable or snapshot channels: $AGENT_FILENAME" >&2
      exit 1
  fi

  echo "Extracting Agent for $arch..."
  mkdir -p "$AGENT_EXTRACT_DIR"
  tar -zxf "$AGENT_FILE_PATH" -C "$AGENT_EXTRACT_DIR"
  
  echo "Checking $WORK_DIR files after extraction:"
  ls -lrt "$WORK_DIR"
  
  # --- C. Configure Elasticsearch ---
  echo "Configuring Elasticsearch for $arch..."
  # Required modification for running in Docker
  sed -i 's/tar/docker/' "$ES_EXTRACT_DIR/bin/${PNAME}-env"

  # Overwrite the default config file with a custom one, if it exists
  CUSTOM_CONFIG_PATH="${GITHUB_WORKSPACE:-.}/products/$PNAME/config/${PNAME}.yml"
  if [ -f "$CUSTOM_CONFIG_PATH" ]; then
      cp "$CUSTOM_CONFIG_PATH" "$ES_EXTRACT_DIR/config/${PNAME}.yml"
      echo "Applied custom configuration."
  else
      echo "WARNING: Custom config file not found at $CUSTOM_CONFIG_PATH. Using default."
  fi

  # --- D. Install Plugins ---
  echo "Installing plugin: analysis-ik"
  # Use --batch for non-interactive installation
  "$ES_EXTRACT_DIR/bin/${PNAME}-plugin" install --batch "file:///$IK_PLUGIN_PATH"

  echo "--- Finished processing architecture: $arch ---"
done

echo -e "\nAll artifacts have been downloaded and prepared for the Docker build."