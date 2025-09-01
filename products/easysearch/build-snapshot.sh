#!/bin/bash
set -eo pipefail

if [[ $VERSION =~ SNAPSHOT ]]; then
  exit 1
fi

WORKDIR="$(mktemp -d)"
SRC=$GITHUB_WORKSPACE/$PNAME
DEST=$GITHUB_WORKSPACE/dest

echo "Prepar build snapshot files"
mkdir -p $DEST

echo "Repack $PNAME from $SRC to $DEST with [ $VERSION-$BUILD_NUMBER ]"

# 查找符合条件的文件
FOUND_FILES=$(find "$SRC/distribution/archives/oss-no-jdk-linux-tar/build/distributions" -name "$PNAME-oss-*.tar.gz" -type f -print -quit)

# 判断是否找到文件
if [ -z "$FOUND_FILES" ]; then
  echo "Error: $PNAME distribution files not found exit now."
  exit 1
fi

#初始化操作目录
mkdir -p $WORKDIR && cd $WORKDIR
cp -rf $SRC/distribution/archives/oss-no-jdk-*/build/distributions/$PNAME-oss* $WORKDIR
ls -lrt $WORKDIR

#重新压缩与命名
for x in linux-amd64 linux-aarch64 mac-amd64 mac-aarch64 windows; do
  FNAME=`ls -lrt |grep $PNAME |head -n 1 |awk '{print $NF}'`
  TNAME=`echo $FNAME |sed "s/$VERSION/$VERSION-$BUILD_NUMBER/"|sed 's/darwin/mac/;s/aarch64/arm64/;s/x86_64/amd64/' |awk -F'-' '{print $1"-"$3"-"$4"-"$(NF-1)"-"$NF}'`
  DNAME=`echo $FNAME |sed "s/$VERSION/$VERSION-$BUILD_NUMBER/"|sed 's/darwin/mac/;s/aarch64/arm64/;s/x86_64/amd64/' |awk -F'-' '{print $1"-"$3"-"$4"-"$5"-"$(NF-1)"-"$NF}'`
  if [ "${FNAME##*.}" == "gz" ]; then
    tar -zxf $FNAME && cd $PNAME-$VERSION-SNAPSHOT
    if [ "$(echo $DNAME |grep -wo mac)" == "mac" ]; then
      DNAME=`echo $DNAME |sed 's/.tar.gz/.zip/'`
      zip -r -q $DNAME *
    else
      tar -zcf $DNAME *
    fi
  else
    unzip -q $FNAME && cd $PNAME-$VERSION-SNAPSHOT && zip -r -q $DNAME *
  fi
  echo -e "Repackaged file at $PWD \nfrom $FNAME \nto $DNAME"

  # 文件上传
  if [[ "$(echo "$PUBLISH_RELEASE" | tr '[:upper:]' '[:lower:]')" != "true" ]]; then
    echo Upload $DNAME to oss
    [ ! -f /tmp/.oss.yml ] && cp -rf $GITHUB_WORKSPACE/.oss.yml /tmp
    oss upload -c /tmp/.oss.yml -o -k $PNAME/snapshot -f $WORKDIR/$PNAME-$VERSION-SNAPSHOT/$DNAME
  fi

  # 本地备份
  mv $WORKDIR/$PNAME-$VERSION-SNAPSHOT/$DNAME $DEST/$DNAME
  cd $WORKDIR && rm -rvf $WORKDIR/$FNAME && rm -rf $WORKDIR/$PNAME-$VERSION-SNAPSHOT
done

#插件
onceclean=true
plugins=(sql jieba analysis-hanlp analysis-icu analysis-ik analysis-pinyin analysis-stconvert index-management ingest-common ingest-geoip ingest-user-agent mapper-annotated-text mapper-murmur3 mapper-size transport-nio knn ai ui)
for p in ${plugins[@]}; do
  f=$DEST/plugins/$p/$p-$VERSION.zip
  if [ ! -d $DEST/plugins/$p ]; then
    mkdir -p $DEST/plugins/$p
  fi

  q=$p
  if [ "$p" == "sql" ]; then
    q=search-sql
  fi
  # 为了让打镜像的时候能够找到插件包，所以这里的插件包名字不带 SNAPSHOT，但是实际上是 SNAPSHOT 版本，所以打镜像时一定要先 build
  cp -rf $SRC/plugins/$q/build/distributions/$p-$VERSION-SNAPSHOT.zip $f
  sha512sum $f |awk -F'/' '{print $1$NF}' > $f.sha512

  if [[ "$(echo "$PUBLISH_RELEASE" | tr '[:upper:]' '[:lower:]')" != "true" ]]; then
    echo && echo Check if plugin $p exists and clean cache
    if [ "$onceclean" == "true" ]; then
      curl -H "X-Token: $TOKEN" "$RELEASE_URL/_flush?versions=$VERSION" > /dev/null
      onceclean=false && echo "Flushed plugin cache $p"
    fi

    if [[ "$(echo "$ONLY_DOCKER" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then
      echo "Publish Docker <Only> image no need to upload with $p"
    else
      echo Upload $p to oss
      sha512sum $SRC/plugins/$q/build/distributions/$p-$VERSION-SNAPSHOT.zip |awk -F'/' '{print $1$NF}' > $p-$VERSION-SNAPSHOT.zip.sha512
      oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $SRC/plugins/$q/build/distributions/$p-$VERSION-SNAPSHOT.zip -k $PNAME/snapshot/plugins/$p
      oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $p-$VERSION-SNAPSHOT.zip.sha512 -k $PNAME/snapshot/plugins/$p
    fi
  fi
  
done

echo
for x in snapshot stable; do
  curl -o /dev/null -w "%{http_code}\t" -H 'x-reset-cache: true' $RELEASE_URL/$PNAME/$x/
done
echo