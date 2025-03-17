#!/bin/bash

# 配置参数
PNAME="coco"  # 定义产品名称
BASE_URL="$RELEASE_URL/$PNAME" # 定义基础 URL
WORK_PATH="/opt/$PNAME/server" # 定义工作路径，即 $PNAME 程序所在目录
UPDATE_DIR="update"            # 定义更新文件存放的临时目录
VERSION="0.0.2_NIGHTLY-$(date +%Y%m%d)"  # 默认版本号，使用日期
REMOTE_UPDATE=false            # 默认本地更新，设置为 false 则进行本地更新
VERSION_PROVIDED=false # 添加一个变量来表示是否提供了版本号
NIGHTLY_VERSION=true # 标记当前版本是否是 NIGHTLY

# 解析命令行参数
while [ "$#" -gt 0 ]; do
    case "$1" in
        --remote|-r)
            REMOTE_UPDATE=true
            shift
            if [[ "$1" == "--version" || "$1" == "-v"  ]] ; then
                 shift
                  if [[ -n "$1"  && "$1" != -*  ]]; then
                    VERSION="$1"
                    VERSION_PROVIDED=true
                    NIGHTLY_VERSION=false # 使用-v 则不是NIGHTLY
                    shift
                  else
                    echo "Error: -v or --version requires a version number after -r"
                    exit 1
                  fi
             elif [[ "$1" != -* && -n "$1" ]] ; then
                    VERSION="${1}_NIGHTLY-$(date +%Y%m%d)"  # 如果是-r version, 则使用 NIGHTLY
                    VERSION_PROVIDED=true
                    shift
             fi
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -r, --remote [VERSION]    Enable remote update with optional version number"
            echo "   [--version|-v] VERSION      Specify the version to use after -r for release version."
            echo "  -h, --help              Show this help message"
             exit 0
            ;;
        *)
            shift
            ;;
    esac
done

if [[ $VERSION_PROVIDED == false && $REMOTE_UPDATE == false ]] ;then
   echo "No version is specified"
fi

# 定义更新函数
update() {
    cd "$WORK_PATH" || { echo "Error: Could not change directory to $WORK_PATH" ; exit 1; }

    # 判断是否是远程更新
    if [ "$REMOTE_UPDATE" = true ]; then
        echo "Downloading remote update package with version: $VERSION..."
        PACKAGE_NAME="$PNAME-$VERSION-linux-amd64.tar.gz"
        
        # 构建下载链接
        if [[ "$VERSION" == *NIGHTLY* ]]; then
           DOWNLOAD_URL="$BASE_URL/snapshot/$PACKAGE_NAME"
        else
            DOWNLOAD_URL="$BASE_URL/stable/$PACKAGE_NAME"
        fi
        # 下载更新包
        wget "$DOWNLOAD_URL" -O "$PACKAGE_NAME" || { echo "Error: Failed to download package"; exit 1; }

        # 解压更新包到临时目录
        mkdir -p "$UPDATE_DIR" || { echo "Error: Failed to create update directory"; exit 1; }
        tar -zxvf "$PACKAGE_NAME" -C "$UPDATE_DIR/"  || { echo "Error: Failed to extract package"; exit 1; }

        # 清理旧的压缩包
        echo "Cleaning old gz file..."
        rm -f "$PACKAGE_NAME"

    fi

    # 停止服务
    echo "Stopping service..."  # 输出提示信息
    ./$PNAME-linux-amd64 -service stop || echo "Warning: Could not stop service" #  不中断脚本，而是给出警告
    sleep 3  # 等待 3 秒

     # 更新版本 (移动 $PNAME 程序), 这里需要检查文件是否存在
    if [[ -f "$WORK_PATH/$UPDATE_DIR/$PNAME-linux-amd64" ]]; then
          echo "Updating version..." # 输出提示信息
          mv "$WORK_PATH/$UPDATE_DIR/$PNAME-linux-amd64" .  || { echo "Error: Failed to move update"; exit 1; } 
    else
      echo "Error: Update file not found $WORK_PATH/$UPDATE_DIR/$PNAME-linux-amd64"
       exit 1;
     fi

    # 启动服务
    echo "Starting service..."  # 输出提示信息
     ./$PNAME-linux-amd64 -service start || echo "Warning: Could not start service"
    sleep 3  # 等待 3 秒

    # 清理临时文件
    echo "Cleaning up..." # 输出提示信息
    rm -rf "$WORK_PATH/$UPDATE_DIR" && mkdir -p "$WORK_PATH/$UPDATE_DIR"

    # 本地更新时不查看日志
    if [[ $REMOTE_UPDATE == true ]]; then
      # 查看日志
      echo "View service log..." # 输出提示信息
      tail -200 log/$PNAME/nodes/*/$PNAME.log  # 实时查看日志
    fi
}

# 执行更新
update