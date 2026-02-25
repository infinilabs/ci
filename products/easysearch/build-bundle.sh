#!/bin/bash

USER_GRAALVM=true
WORK="$(mktemp -d)"
DEST=$GITHUB_WORKSPACE/dest
BUILD_JDKS=$GITHUB_WORKSPACE/jdks

echo "Prepar build bundle files for $PNAME version $VERSION (build number: $BUILD_NUMBER) using JDK: $(if [[ "$USER_GRAALVM" == "true" ]]; then echo GraalVM; else echo Zulu; fi)"
mkdir -p $DEST

#初始化 JDK
mkdir -p $BUILD_JDKS && echo Build directory $BUILD_JDKS
if [[ "$USER_GRAALVM" == "true" ]]; then
  for x in linux-x64 linux-aarch64 macos-x64 macos-aarch64 windows-x64; do
    
    EXT=tar.gz; [[ $x == windows-* ]] && EXT=zip
    FILE=graalvm-jdk-${JAVA_VERSION_21}_${x}_bin.$EXT
    echo "Download GraalVM JDK with https://download.oracle.com/graalvm/$JAVA_VERSION_21/archive/$FILE"

    if [ ! -e "$BUILD_JDKS/$FILE" ]; then
      wget \
        https://download.oracle.com/graalvm/${JAVA_VERSION_21}/archive/$FILE \
        -P "$BUILD_JDKS"
    fi
  done
else
  for x in linux_x64 linux_aarch64 macosx_x64 macosx_aarch64 win_x64; do
    if [ ! -e $BUILD_JDKS/$ZULU_JAVA_VERSION-$x.tar.gz ]; then
      wget \
        https://cdn.azul.com/zulu/bin/$ZULU_JAVA_VERSION-$x.tar.gz \
        -P $BUILD_JDKS
    fi
  done
fi

echo "JDKs download complete"
ls -lrt $BUILD_JDKS

#初始化操作目录
mkdir -p $WORK && cd $_
cp -rf $DEST/$PNAME-$VERSION-$BUILD_NUMBER-* $WORK

#重新压缩与重命名
for x in linux-amd64 linux-arm64 mac-amd64 mac-arm64 windows-amd64; do
  FNAME=`ls -lrt $WORK |grep $PNAME |head -n 1 |awk '{print $NF}'`
  DNAME=`echo $FNAME |sed 's/.zip/-bundle.zip/;s/.tar.gz/-bundle.tar.gz/'`
  if [[ "$USER_GRAALVM" == "true" ]]; then
    JARK=$(echo "$x" | sed -e 's/-amd64/-x64/;s/-arm64/-aarch64/;s/mac/macos/')
    JNAME=`find $BUILD_JDKS -name "graalvm*_$JARK*" |head -n 1`
  else
    JARK=$(echo "$x" | sed -e 's/-amd64/_x64/;s/-arm64/_aarch64/;s/mac/macosx/;s/windows/win/')
    JNAME=`find $BUILD_JDKS -name "$ZULU_JAVA_VERSION-$JARK*" |head -n 1`
  fi
  URL="$RELEASE_URL/$PNAME/stable/bundle/$DNAME"
  HTTP_STATUS=$(curl -s -I -o /dev/null -w "%{http_code}" "$URL" || true)
  if [[ "$HTTP_STATUS" =~ ^2[0-9]{2}$ ]]; then
    echo "Exists release file $DNAME will overwrite it"
  fi
  echo -e "From: $FNAME \nTo:   $DNAME \nJark: $JARK \nJdk:  $JNAME"
  # 解压并删除原文件
  mkdir -p $WORK/$PNAME && cd $WORK/$PNAME
  echo "Current work directory: $(pwd)"
  if [ "${FNAME##*.}" == "gz" ]; then
    tar -zxf $WORK/$FNAME
  else
    unzip -q $WORK/$FNAME
  fi
 
  # 配置jdk
  if [ "${JNAME##*.}" == "gz" ]; then
    tar -zxf $JNAME
  else
    unzip -q $JNAME
  fi

  #plugin install need before bundle jdk
  if [ -z "$(ls -A $WORK/$PNAME/plugins)" ]; then
    plugins=(sql analysis-ik analysis-icu analysis-stconvert analysis-pinyin analysis-morphology ingest-common ingest-geoip ingest-user-agent mapper-annotated-text mapper-murmur3 mapper-size transport-nio knn ai ui)
    for p in ${plugins[@]}; do
      dist_dir="$DEST/plugins/$p"
      files=( "$dist_dir/$p-$VERSION"*.zip "$dist_dir/$p-"*"-$VERSION"*.zip )
      for zip in "${files[@]}"; do
        echo "Installing plugin $zip ..."

        if [ -f "$zip" ]; then
          if $WORK/$PNAME/bin/$PNAME-plugin install --batch "file:///$zip"; then
              echo "Plugin $p installed successfully."
          else
              echo "Error: Failed to install plugin $p"
              exit 1
          fi
        fi
      done
    done

    # for debug
    echo "Checked the installed plugins for $PNAME-$VERSION." && ls -lrt $WORK/$PNAME/plugins
  fi

  # Copy the JDK to the expected location
  if [[ "$USER_GRAALVM" == "true" ]]; then
    mv graalvm* $WORK/$PNAME/jdk
  else
    mv zulu* $WORK/$PNAME/jdk
  fi

  # for debug
  # echo "Check current files" && ls -lrt  $WORK/$PNAME

  # 重新打包
  if [ "${DNAME##*.}" == "gz" ]; then
    tar -zcf $DNAME *
  else
    zip -r -q $DNAME *
  fi

  if [ -f $WORK/$PNAME/$DNAME ]; then
    echo "Repackaged file at $WORK/$PNAME/$DNAME"
    # Check if only docker image is to be published
    if [[ "$(echo "$ONLY_DOCKER" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then
      echo "Publish Docker <Only> image no need to upload with $DNAME"
    else
      # Upload to OSS if not only docker image and log the upload time with +8 zone
      echo "$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S') INFO Upload $DNAME to OSS"
      if [[ "$(echo "$PRE_RELEASE" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then
        oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $WORK/$PNAME/$DNAME -k $PNAME/snapshot/bundle
      else
        oss upload -c $GITHUB_WORKSPACE/.oss.yml -o -f $WORK/$PNAME/$DNAME -k $PNAME/stable/bundle
      fi
    fi
  fi
  cd $WORK && rm -rf $WORK/$FNAME && rm -rf $WORK/$PNAME
done
