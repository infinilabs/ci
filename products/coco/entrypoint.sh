#!/bin/bash
set -e

log() {
  echo "$(date -Iseconds) [$(basename "$0")] $@"
}

setup_coco() {
  local WORK_DIR=/app/easysearch/data
  local COCO_DIR=$WORK_DIR/coco

  if [ ! -d "$WORK_DIR" ] ; then
    mkdir -p "$WORK_DIR"
  fi

  if [ ! -d "$COCO_DIR" ]; then
    cp -rf /app/coco $COCO_DIR
  fi

  for dir in data config; do
    if [ ! -d "$COCO_DIR/$dir" ]; then
      mkdir -p "$COCO_DIR/$dir"
    fi
  done

  if [ -z "$($COCO_DIR/coco keystore list | grep -Eo ES_PASSWORD)" ]; then
    cd $COCO_DIR && echo "$EASYSEARCH_INITIAL_ADMIN_PASSWORD" | ./coco keystore add --stdin ES_PASSWORD
    chown -R ezs:ezs $COCO_DIR/data/coco/nodes/*/.keystore
  fi
  
  [ "$(stat -c %U $WORK_DIR)" == "ezs" ] || chown -R ezs:ezs $WORK_DIR
}

# --- Root-only functions ---

setup_supervisor() {
  if [ ! -f /etc/supervisor/conf.d/coco.conf ]; then
    mkdir -p /etc/supervisor/conf.d
    echo_supervisord_conf > /etc/supervisor/supervisord.conf
    sed -i 's|^;\(\[include\]\)|\1|; s|^;files.*|files = /etc/supervisor/conf.d/*.conf|' /etc/supervisor/supervisord.conf
    cat /app/tpl/coco.conf > /etc/supervisor/conf.d/coco.conf
  fi

  if ! supervisorctl status > /dev/null 2>&1; then
    /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
  fi
  return 0
}

# --- Main Script ---

# Trap signals for graceful shutdown
trap "exit 0" SIGINT SIGTERM

if [ "$(id -u)" = '0' ]; then
  if [ -z "${EASYSEARCH_INITIAL_ADMIN_PASSWORD}" ]; then
    log "WARNING: EASYSEARCH_INITIAL_ADMIN_PASSWORD is not set. Using default coco server password."
    export EASYSEARCH_INITIAL_ADMIN_PASSWORD="coco-server"
  fi
  # for ezs init
  gosu ezs bash bin/initialize.sh -s
  # for coco
  export ES_PASSWORD=$EASYSEARCH_INITIAL_ADMIN_PASSWORD
  setup_coco && setup_supervisor
  # start easysearch
  log "Starting Easysearch Process..."
  exec gosu ezs "$0" "$@"
fi

exec "$@"