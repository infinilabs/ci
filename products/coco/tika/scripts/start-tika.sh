#!/bin/bash
set -e

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] [tika] $*"
}

die() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] [tika] $*" >&2
  exit 1
}

log "Starting Apache Tika ${TIKA_VERSION:-3.2.3} on port 9998..."

# 直接前台启动 Java, Supervisor 会直接管理这个 Java 进程
exec java -Dtika.log.level=WARN \
          -Dorg.slf4j.simpleLogger.defaultLogLevel=WARN \
          -jar /opt/tika-server.jar \
          --port 9998