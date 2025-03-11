#!/bin/bash
set -e

log() {
  if [[ -n "$LOG" ]]; then
    echo "$(date -Iseconds) [$(basename "$0")] $@"
  fi
}

setup_coco() {
  local WORK_DIR=/app/easysearch/data
  local COCO_DIR=$WORK_DIR/coco

  if [ ! -d "$WORK_DIR" ] ; then
    mkdir -p "$WORK_DIR"
  fi

  if [ ! -d "$COCO_DIR" ]; then
    cp -rf /app/coco $COCO_DIR
    log "Copied coco to $COCO_DIR"
  fi

  for dir in data config; do
    if [ ! -d "$COCO_DIR/$dir" ]; then
      mkdir -p "$COCO_DIR/$dir"
      log "Created $COCO_DIR/$dir"
    fi
  done

  cd $COCO_DIR
  if [ -z "$(./coco keystore list | grep -Eo ES_PASSWORD)" ]; then
    echo "$EASYSEARCH_INITIAL_ADMIN_PASSWORD" | ./coco keystore add --stdin ES_PASSWORD
    log "Added ES_PASSWORD to keystore."
    chown -R ezs:ezs $COCO_DIR/data/coco/nodes/*/.keystore
    log "Changed ownership of keystore files."
  else
    log "Keystore is already for Coco."
  fi
  
  if [ "$(stat -c %U $WORK_DIR)" != "ezs" ] ; then
    chown -R ezs:ezs $WORK_DIR
  else
    log "$WORK_DIR is already owned by ezs."
  fi
  if [ "$(stat -c %U $WORK_DIR/data/coco/nodes/*/.keystore/ks)" != "ezs" ] ; then
    chown -R ezs:ezs $WORK_DIR/data/coco/nodes/*/.keystore
  else
    log "Coco's .keystore is already owned by ezs."
  fi
  return 0
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
  if [[ $(compgen -G "config/*.{crt,key}" 2>/dev/null) ]]; then
    log "Certificates already exist. Skipping initialization."
  else
    gosu ezs bash bin/initialize.sh -s
  fi
  # for coco
  export ES_PASSWORD=$EASYSEARCH_INITIAL_ADMIN_PASSWORD
  log "Setting up Coco..."
  setup_coco
  # start supervisor
  log "Starting Supervisor Process..."
  setup_supervisor
  
  # start easysearch
  log "Starting Easysearch Process..."
  exec gosu ezs "$0" "$@"
fi

exec "$@"