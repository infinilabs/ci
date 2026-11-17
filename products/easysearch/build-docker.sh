#!/usr/bin/env bash
#
# Prepare the docker build context for $PNAME:
#   1. extract the product tarball for each arch
#   2. download + extract the matching agent (stable -> snapshot fallback)
#   3. switch distribution type to docker, install plugins
#
# Required env: GITHUB_WORKSPACE PNAME VERSION BUILD_NUMBER AGENT_VERSION RELEASE_URL
# Optional env: EZS_TAG EZS_VER PROBE_MAX (default 5) DOWNLOAD_MAX (default 3)

set -euo pipefail

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
: "${PNAME:?PNAME is required}"
: "${VERSION:?VERSION is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
: "${AGENT_VERSION:?AGENT_VERSION is required}"
: "${RELEASE_URL:?RELEASE_URL is required}"

WORK="$GITHUB_WORKSPACE/products/$PNAME"
DEST="$GITHUB_WORKSPACE/dest"
ARCHS=(amd64 arm64)
MAJOR="${VERSION%%.*}"
PROBE_MAX="${PROBE_MAX:-5}"
DOWNLOAD_MAX="${DOWNLOAD_MAX:-3}"

# plugin -> space separated list of plugins that must be installed first
declare -A PLUGIN_DEPS=(
  [ai]="knn"
  [analysis-ik]="ingest-common"
)
# not shipped in the docker image
EXCLUDED_PLUGINS=(analysis-hanlp jieba)

# ── helpers ────────────────────────────────────────────────
warn() { echo "::warning::$*" >&2; }
die()  { echo "::error::$*" >&2; exit 1; }

# Probe a URL with HEAD. Retries on network errors (http 000), 408, 429 and 5xx;
# gives up immediately on other 4xx (e.g. 404).
# Sets PROBE_STATUS / PROBE_RC / PROBE_ERR for the caller. Returns 0 only on 2xx.
probe_url() {
  local url="$1" attempt rc errfile
  errfile="$(mktemp)"
  PROBE_STATUS="000"; PROBE_RC=0; PROBE_ERR=""

  for ((attempt = 1; attempt <= PROBE_MAX; attempt++)); do
    PROBE_STATUS="$(curl -sS -I -o /dev/null -w '%{http_code}' \
      --connect-timeout 10 --max-time 30 "$url" 2>"$errfile")" && rc=0 || rc=$?
    PROBE_RC=$rc
    PROBE_ERR="$(<"$errfile")"

    if [[ "$PROBE_STATUS" =~ ^2[0-9]{2}$ ]]; then
      rm -f "$errfile"
      return 0
    fi

    if [[ "$PROBE_STATUS" =~ ^4[0-9]{2}$ && "$PROBE_STATUS" != "408" && "$PROBE_STATUS" != "429" ]]; then
      echo "  [probe] $url -> HTTP $PROBE_STATUS (not retrying)" >&2
      rm -f "$errfile"
      return 1
    fi

    echo "  [probe] attempt $attempt/$PROBE_MAX failed: http=$PROBE_STATUS curl_rc=$rc err=${PROBE_ERR:-<none>}" >&2
    if ((attempt < PROBE_MAX)); then
      sleep $((attempt * 3))
    fi
  done

  rm -f "$errfile"
  return 1
}

# Download to <dest>.part, verify it is a valid gzip, then move into place so a
# partial/corrupt file is never mistaken for a finished download.
download_file() {
  local url="$1" dest="$2" part="$2.part" attempt rc

  for ((attempt = 1; attempt <= DOWNLOAD_MAX; attempt++)); do
    rm -f "$part"
    if wget --tries=1 --timeout=30 --progress=dot:giga -O "$part" "$url"; then
      if gzip -t "$part" 2>/dev/null; then
        mv -f "$part" "$dest"
        return 0
      fi
      echo "  [download] attempt $attempt/$DOWNLOAD_MAX: $url is not a valid gzip file" >&2
    else
      rc=$?
      echo "  [download] attempt $attempt/$DOWNLOAD_MAX failed: wget_rc=$rc url=$url" >&2
    fi
    if ((attempt < DOWNLOAD_MAX)); then
      sleep 5
    fi
  done

  rm -f "$part"
  return 1
}

# Fetch the agent for <arch> from stable, falling back to snapshot.
# Sets AGENT_FILE_PATH on success; exits with a detailed error otherwise.
fetch_agent() {
  local arch="$1" channel url last_error=""
  local filename="agent-$AGENT_VERSION-linux-$arch.tar.gz"
  AGENT_FILE_PATH="$WORK/$filename"
  rm -f "$AGENT_FILE_PATH"

  for channel in stable snapshot; do
    url="$RELEASE_URL/agent/$channel/$filename"
    echo "Checking [$channel] $url"

    if probe_url "$url"; then
      echo "Found $filename at $url. Starting download with retries..."
      if download_file "$url" "$AGENT_FILE_PATH"; then
        echo "Download of $filename successful from $channel channel."
        return 0
      fi
      last_error="[$channel] download failed after $DOWNLOAD_MAX attempts: $url"
    else
      last_error="[$channel] probe failed: http=$PROBE_STATUS curl_rc=$PROBE_RC err=${PROBE_ERR:-<none>} url=$url"
    fi
    echo "$last_error" >&2
  done

  die "$filename not found or failed to download from both stable and snapshot channels. Last error: $last_error"
}

extract_product() {
  local arch="$1"
  local src="$DEST/$PNAME-$VERSION-$BUILD_NUMBER-linux-$arch.tar.gz"
  local out="$WORK/$PNAME-$arch"

  [[ -f "$src" ]] || die "$src not found, exit now."

  echo -e "Extract file \nfrom $src \nto $out"
  if [[ "$MAJOR" =~ ^[0-9]+$ && "$MAJOR" -ge 3 ]]; then
    tar -zxf "$src" -C "$out" --strip-components=1
  else
    tar -zxf "$src" -C "$out"
  fi
}

extract_agent() {
  local arch="$1"
  fetch_agent "$arch"
  echo -e "Extracting file \n\tfrom $AGENT_FILE_PATH \n\tto $WORK/agent-$arch"
  tar -zxf "$AGENT_FILE_PATH" -C "$WORK/agent-$arch"
  rm -f "$AGENT_FILE_PATH"
  echo "Agent extracted successfully."
}

# ── plugin ordering (topological sort, dependencies first) ──
# Uses globals: _present (set of available plugins), _vis (visit state), _srt (result order)
topo_visit() {
  local node="$1" dep
  case "${_vis[$node]:-}" in
    done)     return 0 ;;
    visiting) die "circular plugin dependency on '$node'" ;;
  esac

  _vis[$node]="visiting"
  for dep in ${PLUGIN_DEPS[$node]:-}; do
    if [[ -n "${_present[$dep]:-}" ]]; then
      topo_visit "$dep"
    else
      warn "plugin '$node' depends on '$dep', which is not available in $DEST/plugins"
    fi
  done
  _vis[$node]="done"
  _srt+=("$node")
}

# Fills the global array raw_plugins with plugin dir names, minus EXCLUDED_PLUGINS.
collect_plugins() {
  local name
  raw_plugins=()

  if [[ ! -d "$DEST/plugins" ]]; then
    warn "$DEST/plugins does not exist, no plugins to install"
    return 0
  fi

  while IFS= read -r name; do
    if [[ " ${EXCLUDED_PLUGINS[*]} " == *" $name "* ]]; then
      continue
    fi
    raw_plugins+=("$name")
  done < <(find "$DEST/plugins" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
}

install_plugins() {
  local arch="$1" p plat zip dist_dir found
  local bin="$WORK/$PNAME-$arch/bin/$PNAME-plugin"
  local -a files
  local -a raw_plugins

  collect_plugins

  declare -gA _present=() _vis=()
  declare -ga _srt=()
  for p in "${raw_plugins[@]}"; do _present[$p]=1; done
  for p in "${raw_plugins[@]}"; do topo_visit "$p"; done
  echo "Plugin install order: ${_srt[*]:-<none>}"

  shopt -s nullglob
  for p in "${_srt[@]}"; do
    dist_dir="$DEST/plugins/$p"

    if [[ "$p" == "rules" ]]; then
      case "$arch" in
        amd64) plat="linux-x64" ;;
        arm64) plat="linux-aarch64" ;;
        *)     plat="linux-$arch" ;;
      esac
      files=( "$dist_dir/$p-$plat-$VERSION"*.zip "$dist_dir/$p-$VERSION-$plat"*.zip )
    else
      files=( "$dist_dir/$p-$VERSION"*.zip "$dist_dir/$p-"*"-$VERSION"*.zip )
    fi

    found=0
    for zip in "${files[@]}"; do
      [[ -f "$zip" ]] || continue
      found=1
      echo "Installing plugin $zip ..."
      if "$bin" install --batch "file:///$zip"; then
        echo "Plugin $p installed successfully."
      else
        die "Failed to install plugin $p ($zip)"
      fi
    done
    if ((found == 0)); then
      warn "no matching zip found for plugin '$p' (version $VERSION, arch $arch) in $dist_dir"
    fi
  done
  shopt -u nullglob
}

# ── main ───────────────────────────────────────────────────
echo "Prepare build docker files"
if [[ -d "$DEST" ]]; then
  ls -lrt "$DEST"/*.tar.gz || true
  ls -lrt "$DEST/plugins" || true
else
  mkdir -p "$DEST"
fi

cd "$WORK"

# docker image tag
DOCKER_TAG="${EZS_TAG:-${EZS_VER:-$(grep "$PNAME" "$GITHUB_WORKSPACE/.latest" | awk -F'"' '{print $(NF-1)}' || true)}}"
[[ -n "$DOCKER_TAG" ]] || warn "docker tag for $PNAME is empty"
echo "Publish $PNAME with docker tag $DOCKER_TAG"

for t in "${ARCHS[@]}"; do
  echo "===== $t ====="
  mkdir -p "$WORK/$PNAME-$t" "$WORK/agent-$t"

  extract_product "$t"
  extract_agent "$t"

  # ES_DISTRIBUTION_TYPE needs to change to docker
  sed -i 's/tar/docker/' "$WORK/$PNAME-$t/bin/$PNAME-env"
  cat "$WORK/config/$PNAME.yml" > "$WORK/$PNAME-$t/config/$PNAME.yml"

  # plugin install for docker (only when the tarball shipped no plugins)
  if [[ -z "$(ls -A "$WORK/$PNAME-$t/plugins" 2>/dev/null)" ]]; then
    install_plugins "$t"
    # for debug
    # echo "Checked the installed plugins for $PNAME-$VERSION." && ls -lrt "$WORK/$PNAME-$t/plugins"
  fi
done