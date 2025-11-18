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
  DOWNLOAD_SUCCESS=false
  AGENT_FILENAME="agent-$AGENT_VERSION-linux-$t.tar.gz"
  AGENT_FILE_PATH="$WORK/$AGENT_FILENAME"

  for f in stable snapshot; do
    URL="$RELEASE_URL/agent/$f/$AGENT_FILENAME"
    HTTP_STATUS=$(curl -s -I -o /dev/null -w "%{http_code}" "$URL" || true)

    if [[ "$HTTP_STATUS" =~ ^2[0-9]{2}$ ]]; then
      echo "Found $AGENT_FILENAME at $URL. Starting download..."
      # Attempt to download with retries 3 times
      for attempt in {1..3}; do
        echo "Attempt $attempt to download $AGENT_FILENAME from $URL"
        if wget "$URL" -O "$AGENT_FILE_PATH" --tries=1 --timeout=30; then
          echo "Download of $AGENT_FILENAME successful."
          DOWNLOAD_SUCCESS=true
          break
        else
          echo "Attempt $attempt failed. Retrying in 5 seconds..."
          sleep 5
        fi
      done

      if [[ "$DOWNLOAD_SUCCESS" == true ]]; then
        break
      fi
    fi
  done

  # Check if download was successful before extraction
  if [[ "$DOWNLOAD_SUCCESS" == true ]] && [[ -f "$AGENT_FILE_PATH" ]]; then
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

  #plugin install
  if [ -z "$(ls -A $WORK/$PNAME-$t/plugins)" ]; then
    plugins=(sql analysis-ik analysis-icu analysis-stconvert analysis-pinyin ingest-common ingest-geoip ingest-user-agent mapper-annotated-text mapper-murmur3 mapper-size transport-nio knn ai ui)
    for p in ${plugins[@]}; do
      echo "Installing plugin $p-$VERSION ..."
      $WORK/$PNAME-$t/bin/$PNAME-plugin install --batch file:///$DEST/plugins/$p/$p-$VERSION.zip >/dev/null 2>&1 && echo
    done
  fi
done