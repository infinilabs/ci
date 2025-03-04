#!/bin/bash
set -e

log() {
  echo "$(date -Iseconds) [$(basename "$0")] $@"
}

start_coco() {
  WORK_DIR=/app/easysearch/data
  COCO_DIR=$WORK_DIR/coco
  mkdir -p $WORK_DIR
  # 检查 coco 目录是否存在, 不存在则copy
  if [ ! -d "$COCO_DIR" ]; then
    cp -rf /app/coco $WORK_DIR
  fi

  # 检查 data 和 config 目录是否存在, 不存在则创建
  for dir in data config; do
    if [ ! -d "$COCO_DIR/$dir" ]; then
      mkdir -p "$COCO_DIR/$dir"
    fi
  done

  cd "$COCO_DIR"

  # 初始化 keystore
  if [ -z "$($COCO_DIR/coco keystore list | grep -Eo ES_PASSWORD)" ]; then
    echo "$EASYSEARCH_INITIAL_ADMIN_PASSWORD" | $COCO_DIR/coco keystore add --stdin ES_PASSWORD
  fi
  
  # 权限检查
  if [ "$(stat -c %U $WORK_DIR)" != "ezs" ]; then
    chown -R ezs:ezs $WORK_DIR
  fi

  # 初始化 supervisor
  if [ ! -f /etc/supervisor/conf.d/coco.conf ]; then
    mkdir -p /etc/supervisor/conf.d
    echo_supervisord_conf > /etc/supervisor/supervisord.conf
    sed -i 's|^;\(\[include\]\)|\1|; s|^;files.*|files = /etc/supervisor/conf.d/*.conf|' /etc/supervisor/supervisord.conf
    cat /app/tpl/coco.conf > /etc/supervisor/conf.d/coco.conf
  fi

  # 启动 supervisord (如果未运行)
  if ! supervisorctl status > /dev/null 2>&1; then
    /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
  fi

  return 0
}

# Trap signals for graceful shutdown
trap "exit 0" SIGINT SIGTERM

if [ "$(id -u)" = '0' ]; then
  if [ -z "${EASYSEARCH_INITIAL_ADMIN_PASSWORD}" ]; then
    log "WARNING: EASYSEARCH_INITIAL_ADMIN_PASSWORD is not set. Using default coco server password."
    export EASYSEARCH_INITIAL_ADMIN_PASSWORD="infini_coco"
  fi
  # init certs/password/plugins
  gosu ezs bash bin/initialize.sh -s
  
  # Conditionally start the coco
  log "Configuring coco for supervisord..."
  start_coco # Now we *only* configure for supervisord
  if [ $? -eq 0 ]; then
    log "Coco configured. Supervisord will start and manage it."
  else
    log "Coco configuration failed. Check logs for errors."
  fi

  log "Startinging main process ..."
  exec gosu ezs "$0" "$@"
fi

exec "$@"
