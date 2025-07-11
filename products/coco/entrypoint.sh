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
    cp -af /app/coco $COCO_DIR
    log "Copied coco to $COCO_DIR"
  fi

  for dir in data config; do
    if [ ! -d "$COCO_DIR/$dir" ]; then
      mkdir -p "$COCO_DIR/$dir"
      if [ "$(stat -c %U $COCO_DIR/$dir)" != "ezs" ] ; then
        chown -R ezs:ezs "$COCO_DIR/$dir"
      fi
      log "Created $COCO_DIR/$dir"
    fi
  done

  cd $COCO_DIR
  if [ ! -f ./start-coco.sh ]; then
    cp -rf /app/tpl/*.sh /app/easysearch/data/coco
  fi
  
  if [ -z "$(./coco keystore list | grep -Eo ES_PASSWORD)" ]; then
    echo "$EASYSEARCH_INITIAL_ADMIN_PASSWORD" | ./coco keystore add --stdin ES_PASSWORD >/dev/null
    chown -R ezs:ezs $WORK_DIR
    log "Added ES_PASSWORD to keystore and changed ownership."
  else
    log "Keystore is already for coco."
  fi
  
  if [ "$(stat -c %U $COCO_DIR)" != "ezs" ] ; then
    chown -R ezs:ezs $COCO_DIR
  else
    log "$COCO_DIR is already owned by ezs."
  fi

  return 0
}

# --- Root-only functions ---

setup_supervisor() {
  if [ ! -f $COCO_DIR/supervisor/conf.d/coco.conf ]; then
    mkdir -p $COCO_DIR/supervisor/conf.d
    echo_supervisord_conf > $COCO_DIR/supervisor/supervisord.conf
    # Set the user and enable includes
    sed -i "/\[supervisord\]/a user = root" $COCO_DIR/supervisor/supervisord.conf
    sed -i 's|^;\(\[include\]\)|\1|; s|^;files.*|files = conf.d/*.conf|' $COCO_DIR/supervisor/supervisord.conf
    cat /app/tpl/coco.conf > $COCO_DIR/supervisor/conf.d/coco.conf
    log "Created Supervisor configuration for Coco at $COCO_DIR/supervisor/conf.d/coco.conf"
  fi

  if ! supervisorctl status > /dev/null 2>&1; then
    log "Starting Supervisor..."
    /usr/bin/supervisord -c $COCO_DIR/supervisor/supervisord.conf
    log "Supervisor started successfully."
  fi

  return 0
}

# --- Main Script ---

# Trap signals for graceful shutdown
trap "exit 0" SIGINT SIGTERM

if [ "$(id -u)" = '0' ]; then
  if [ -z "${EASYSEARCH_INITIAL_ADMIN_PASSWORD}" ]; then
    log "WARNING: EASYSEARCH_INITIAL_ADMIN_PASSWORD is not set. Generating a random 16-character password..."
    RANDOM_PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
    
    if [ -n "$RANDOM_PASSWORD" ]; then
      export EASYSEARCH_INITIAL_ADMIN_PASSWORD="coco-server-$RANDOM_PASSWORD"
      log "Generated password: $EASYSEARCH_INITIAL_ADMIN_PASSWORD"
    else
      log "Error generating random password. Using default 'coco-server'."
      export EASYSEARCH_INITIAL_ADMIN_PASSWORD="coco-server"
    fi
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