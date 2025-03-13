#!/bin/bash

WORK=$GITHUB_WORKSPACE/products/$PNAME
DEST=$GITHUB_WORKSPACE/dest

echo "Prepar build docker files"
mkdir -p $DEST

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

  #下载对应架构的 agent 并解压
  AGENT_FILENAME=agent-$AGENT_VERSION-linux-$t.tar.gz
  for f in stable snapshot; do
    if curl -I -m 10 -o /dev/null -s -w %{http_code} $RELEASE_URL/agent/$f/$AGENT_FILENAME | grep -q 200; then
      wget -q -nc --show-progress --progress=bar:force:noscroll $RELEASE_URL/agent/$f/$AGENT_FILENAME
    fi
  done

  if [ -f $AGENT_FILENAME ]; then
    echo -e "Extract file \nfrom $WORK/$AGENT_FILENAME \nto $WORK/agent-$t"
    tar -zxf $WORK/$AGENT_FILENAME -C $WORK/agent-$t
    rm -rf $WORK/$AGENT_FILENAME
  else
    echo "Error: $AGENT_FILENAME not found exit now."
    exit 1
  fi

  # ES_DISTRIBUTION_TYPE need change to docker
  sed -i 's/tar/docker/' $WORK/$PNAME-$t/bin/$PNAME-env
  cat $GITHUB_WORKSPACE/products/$PNAME/config/$PNAME.yml > $WORK/$PNAME-$t/config/$PNAME.yml

  #plugin install
  if [ -z "$(ls -A $WORK/$PNAME-$t/plugins)" ]; then
    plugins=(sql analysis-ik analysis-icu analysis-stconvert analysis-pinyin index-management ingest-common ingest-geoip ingest-user-agent mapper-annotated-text mapper-murmur3 mapper-size transport-nio cross-cluster-replication knn)
    for p in ${plugins[@]}; do
      echo "Installing plugin $p-$VERSION ..."
      echo y | $WORK/$PNAME-$t/bin/$PNAME-plugin install file:///$DEST/plugins/$p/$p-$VERSION.zip > /dev/null 2>&1
    done
  fi
done