#!/bin/bash

WORK=$GITHUB_WORKSPACE/products/$PNAME
DEST=$GITHUB_WORKSPACE/dest

echo "Prepar build docker files"
if [[ -d $DEST ]]; then
  ls -lrt $DEST/*.tar.gz
  ls -lrt $DEST/plugins
else
  mkdir -p $DEST
fi

cd $WORK

#docker image tag
DOCKER_TAG="${EZS_TAG:-${EZS_VER:-$(cat "$GITHUB_WORKSPACE/.latest" | grep "$PNAME" | awk -F'"' '{print $(NF-1)}')}}"
echo "Publish setting $PNAME with docker tag $DOCKER_TAG"

for t in amd64 arm64; do
  mkdir -p $WORK/{$PNAME-$t,agent-$t}
  EZS_FILE=$DEST/$PNAME-$VERSION-$BUILD_NUMBER-linux-$t.tar.gz
  if [ -f $EZS_FILE ]; then
    echo -e "Extract file \nfrom $EZS_FILE \nto $WORK/$PNAME-$t"
    tar -zxf $EZS_FILE -C $WORK/$PNAME-$t
  else
    echo "Error: $EZS_FILE not found exit now."
    exit 1
  fi

  # Download Agent from stable or snapshot channel
  AGENT_FILENAME="agent-$AGENT_VERSION-linux-$t.tar.gz"
  AGENT_FILE_PATH="$WORK/$AGENT_FILENAME"

  for f in stable snapshot; do
    URL="$RELEASE_URL/agent/$f/$AGENT_FILENAME"
    HTTP_STATUS=$(curl -s -I -o /dev/null -w "%{http_code}" "$URL" || true)

    if [[ "$HTTP_STATUS" =~ ^2[0-9]{2}$ ]]; then
      echo "Found $AGENT_FILENAME at $URL. Starting download with retries..."
      if wget --tries=3 --wait=5 --timeout=30 "$URL" -O "$AGENT_FILE_PATH"; then
          echo "Download of $AGENT_FILENAME successful."
          break
      else
          echo "Failed to download $AGENT_FILENAME from $URL after 3 attempts."
      fi
    else
      echo "$AGENT_FILENAME not found at $URL with $f channel, status code: $HTTP_STATUS"
    fi
  done

  # Check if the agent file was downloaded successfully
  if [[ -f "$AGENT_FILE_PATH" ]]; then
    echo -e "Extracting file \nfrom $AGENT_FILE_PATH \nto $WORK/agent-$t"
    tar -zxf "$AGENT_FILE_PATH" -C "$WORK/agent-$t"
    rm -rf "$AGENT_FILE_PATH"
    echo "Agent extracted successfully."
  else
    echo "Error: $AGENT_FILENAME not found or failed to download after 3 attempts for both stable and snapshot channels. Exiting now."
    exit 1
  fi

  # ES_DISTRIBUTION_TYPE need change to docker
  sed -i 's/tar/docker/' $WORK/$PNAME-$t/bin/$PNAME-env
  cat $GITHUB_WORKSPACE/products/$PNAME/config/$PNAME.yml > $WORK/$PNAME-$t/config/$PNAME.yml

  #plugin install for docker
  if [ -z "$(ls -A $WORK/$PNAME-$t/plugins)" ]; then
    # ── Plugin dependency map ──────────────────────────────
    declare -A PLUGIN_DEPS
    PLUGIN_DEPS["ai"]="knn"
    PLUGIN_DEPS["analysis-ik"]="ingest-common"

    # ── Topological sort (ensures deps install first) ──────
    _topo_visit() {
      local node="$1"
      [[ "${_vis[$node]:-}" == "done" ]]     && return
      [[ "${_vis[$node]:-}" == "visiting" ]] && { echo "Error: circular dependency on '$node'" >&2; exit 1; }
      _vis[$node]="visiting"
      for dep in ${PLUGIN_DEPS[$node]:-}; do
        for p in "${raw_plugins[@]}"; do
          [[ "$p" == "$dep" ]] && { _topo_visit "$dep"; break; }
        done
      done
      _vis[$node]="done"
      _srt+=("$node")
    }

    # exclude some plugins for docker image: analysis-hanlp jieba fast-terms filter-distinct
    raw_plugins=($(find $DEST/plugins -mindepth 1 -maxdepth 1 -type d \
      ! -name "analysis-hanlp" \
      ! -name "jieba" \
      ! -name "rules" \
      -exec basename {} \;))

    declare -A _vis=(); declare -a _srt=()
    for p in "${raw_plugins[@]}"; do
      _topo_visit "$p" _vis _srt raw_plugins
    done
    echo "Plugin install order: ${_srt[*]}"

    for p in "${_srt[@]}"; do
      dist_dir="$DEST/plugins/$p"
      files=( "$dist_dir/$p-$VERSION"*.zip "$dist_dir/$p-"*"-$VERSION"*.zip )
      for zip in "${files[@]}"; do
        [ -f "$zip" ] || continue
        echo "Installing plugin $zip ..."
        if $WORK/$PNAME-$t/bin/$PNAME-plugin install --batch "file:///$zip"; then
          echo "Plugin $p installed successfully."
        else
          echo "Error: Failed to install plugin $p" >&2
          exit 1
        fi
      done
    done

    # for debug
    # echo "Checked the installed plugins for $PNAME-$VERSION." && ls -lrt $WORK/$PNAME-$t/plugins
  fi
done