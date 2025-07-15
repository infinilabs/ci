#!/bin/bash

DEST=$GITHUB_WORKSPACE/dest
PLUGINS=$GITHUB_WORKSPACE/plugins
WORK=$GITHUB_WORKSPACE/products/$PNAME

echo "Prepar for build $PNAME docker files"
mkdir -p $DEST

cd $WORK

for t in amd64 arm64; do
  mkdir -p $WORK/{$PNAME-$t,$DNAME-$t}
  EZS_FILE=$DNAME-$EZS_VER-linux-$t.tar.gz
  for f in stable snapshot; do
    DOWNLOAD_URL=$RELEASE_URL/$DNAME/$f/$EZS_FILE
    if curl -o /dev/null -s -w %{http_code} $DOWNLOAD_URL | grep -q 200; then
      echo "Download $EZS_FILE from $DOWNLOAD_URL"
      wget $DOWNLOAD_URL -O $DEST/$EZS_FILE
    fi
  done
  # Check if the file exists and is not empty
  if [[ -e $DEST/$EZS_FILE ]]; then
    file_size=$(stat -c%s "$DEST/$EZS_FILE")
    if [[ "$file_size" -gt 0 ]]; then
      echo -e "Extract file \nfrom $DEST/$EZS_FILE \nto $WORK/$DNAME-$t"
      tar -zxf $DEST/$EZS_FILE -C $WORK/$DNAME-$t
    else
      echo "Download failed or file is empty!"
      exit 1
    fi
  else
    echo "Error: $DEST/$EZS_FILE not found exit now."
    exit 1
  fi

  # Copy coco
  cp -rf $GITHUB_WORKSPACE/$PNAME/bin/$PNAME-linux-$t $WORK/$PNAME-$t
  cp -rf $GITHUB_WORKSPACE/$PNAME/bin/config $WORK/$PNAME-$t
  cp -rf $GITHUB_WORKSPACE/$PNAME/bin/{LICENSE,NOTICE,$PNAME.yml} $WORK/$PNAME-$t
  
  # update config
  echo "" >> $WORK/$PNAME-$t/$PNAME.yml
  echo "path.data: /app/easysearch/data/coco/data" >> $WORK/$PNAME-$t/$PNAME.yml
  echo "path.logs: /app/easysearch/data/coco/logs" >> $WORK/$PNAME-$t/$PNAME.yml
  sed -i "s/localhost/127.0.0.1/g" $WORK/$PNAME-$t/$PNAME.yml

  # ES_DISTRIBUTION_TYPE need change to docker
  sed -i 's/tar/docker/' $WORK/$DNAME-$t/bin/$DNAME-env
  cat $GITHUB_WORKSPACE/products/$PNAME/config/$DNAME.yml > $WORK/$DNAME-$t/config/$DNAME.yml

  #plugin install
  if [ -z "$(ls -A $WORK/$DNAME-$t/plugins)" ]; then
    plugins=(sql analysis-ik analysis-icu analysis-stconvert analysis-pinyin index-management ingest-common ingest-geoip ingest-user-agent mapper-annotated-text mapper-murmur3 mapper-size transport-nio knn)
    for p in ${plugins[@]}; do
      echo "Installing plugin $p ..."
      # easyearch version is x.y.z-build_number but plugin version only need x.y.z
      if [[ "$EZS_VER" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-([1-9][0-9]*))?$ ]]; then
          PLUGIN_VER="${BASH_REMATCH[1]}"
          PLUGIN_FILE="$p-$PLUGIN_VER.zip"
      fi
      DOWNLOAD_URL=$RELEASE_URL/$DNAME/stable/plugins/$p/$PLUGIN_FILE
      if curl -o /dev/null -s -w %{http_code} $DOWNLOAD_URL | grep -q 200; then
        echo "Download $PLUGIN_FILE from $DOWNLOAD_URL"
        mkdir -p $PLUGINS/plugins-$t/$p
        wget $DOWNLOAD_URL -O $PLUGINS/plugins-$t/$p/$PLUGIN_FILE
      fi
      echo y | $WORK/$DNAME-$t/bin/$DNAME-plugin install file://$PLUGINS/plugins-$t/$p/$p-$VERSION.zip > /dev/null 2>&1
    done
  fi
done