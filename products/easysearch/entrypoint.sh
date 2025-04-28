#!/bin/bash
set -e

log() {
  echo "$(date -Iseconds) [$(basename "$0")] $@"
}

start_agent() {
  WORK_DIR=/app/easysearch/data
  AGENT_DIR=$WORK_DIR/agent
  mkdir -p $WORK_DIR
  # 检查 agent 目录是否存在, 不存在则copy
  if [ ! -d "$AGENT_DIR" ]; then
    cp -rf /app/agent $WORK_DIR
  fi

  # 检查 data 和 config 目录是否存在, 不存在则创建
  for dir in data config; do
    if [ ! -d "$AGENT_DIR/$dir" ]; then
      mkdir -p "$AGENT_DIR/$dir"
    fi
  done

  cd "$AGENT_DIR"

  # 处理 METRICS_CONFIG_SERVER 变量
  IFS=',' read -r -a servers <<< "$METRICS_CONFIG_SERVER"

  # Initialize servers_yaml and valid_server flag.
  servers_yaml=""
  valid_servers=true

  # Iterate over the servers and validate them.
  IFS=',' read -r -a servers <<< "$METRICS_CONFIG_SERVER"
  for server in "${servers[@]}"; do
    if ! [[ "$server" =~ ^(http|https):// ]]; then
      log "ERROR: Invalid METRICS_CONFIG_SERVER '$server'. Must start with http:// or https://."
      valid_servers=false
      break
    fi

    servers_yaml+="- \"$server\""
    servers_yaml+=$'\n    '  # YAML indent
  done

  # Abort if any server was invalid
  if ! $valid_servers; then
    return 1
  fi

  # 更新 servers 列表
  sed -i "/^configs:/, /soft_delete:/ {
    /^\s*-/d
    /servers:/a\\
    $servers_yaml
  }" $AGENT_DIR/agent.yml

  # 多租户模式
  if [ -n "${TENANT_ID}" ] && [ -n "${CLUSTER_ID}" ]; then
    if [ -z "${EASYSEARCH_INITIAL_AGENT_PASSWORD}" ]; then
      log "WARNING: EASYSEARCH_INITIAL_AGENT_PASSWORD is not set. Using default agent password."
      EASYSEARCH_INITIAL_AGENT_PASSWORD="infini_password"
    fi
    # 在多租户模式下，添加 node 配置
    if ! grep -q "node:" $AGENT_DIR/agent.yml; then
      echo "" >> $AGENT_DIR/agent.yml
      cat <<-EOF >> $AGENT_DIR/agent.yml
  always_register_after_restart: true
  allow_generated_metrics_tasks: true
node:
  major_ip_pattern: ".*"
  labels:
    tenant_id: "$TENANT_ID"
    cluster_id: "$CLUSTER_ID"
EOF
    fi
  
    # 在多租户模式下，初始化 agent keystore 并调整 yml 和 tpl 文件
    if [ -z "$($AGENT_DIR/agent keystore list | grep -Eo user)" ] && [ -n "$EASYSEARCH_INITIAL_AGENT_PASSWORD" ] && [ -n "$EASYSEARCH_INITIAL_SYSTEM_ENDPOINT" ]; then
      echo "infini_agent" | $AGENT_DIR/agent keystore add --stdin agent_user
      echo "$EASYSEARCH_INITIAL_AGENT_PASSWORD" | $AGENT_DIR/agent keystore add --stdin agent_passwd
      cp -rf /app/tpl/{*.yml,*.tpl} $AGENT_DIR/config
      SCHEMA=$(echo "$EASYSEARCH_INITIAL_SYSTEM_ENDPOINT" |awk -F"://" '{print $1}')
      ADDRESS=$(echo "$EASYSEARCH_INITIAL_SYSTEM_ENDPOINT" |awk -F"://" '{print $2}')
      if [ -n "$SCHEMA" ] && [ -n "$ADDRESS" ]; then
        INGEST_CONFIG="$AGENT_DIR/config/system_ingest_config.yml"
        sed -i "s/ingest/infini_ingest/;s/passwd/$EASYSEARCH_INITIAL_INGEST_PASSWORD/"  $INGEST_CONFIG
        sed -i "s/https/$SCHEMA/;s/127.0.0.1:9200/$ADDRESS/" $INGEST_CONFIG
      fi
    fi
  fi

  # 权限检查
  if [ "$(stat -c %U $AGENT_DIR)" != "ezs" ]; then
    chown -R ezs:ezs $AGENT_DIR
  fi

  # 初始化 supervisor
  if [ ! -f /etc/supervisor/conf.d/agent.conf ]; then
    mkdir -p /etc/supervisor/conf.d
    echo_supervisord_conf > /etc/supervisor/supervisord.conf
    sed -i 's|^;\(\[include\]\)|\1|; s|^;files.*|files = /etc/supervisor/conf.d/*.conf|' /etc/supervisor/supervisord.conf
    cat /app/tpl/agent.conf > /etc/supervisor/conf.d/agent.conf
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
  # init certs/password/plugins
  if [ -z "$(ls -A logs)" ]; then
    log "Initializing EasySearch..."
    gosu ezs bash bin/initialize.sh -s
  fi
  
  # Conditionally start the agent
  if [ "${METRICS_WITH_AGENT}" == "true"  ] && [ -n "${METRICS_CONFIG_SERVER}" ]; then
    log "Configuring agent for supervisord..."
    start_agent # Now we *only* configure for supervisord
    if [ $? -eq 0 ]; then
      log "Agent configured. Supervisord will start and manage it."
    else
      log "Agent configuration failed. Check logs for errors."
    fi
  else
    log "METRICS_WITH_AGENT is false or METRICS_CONFIG_SERVER is not set. The agent process will not start as it is unnecessary in agentless mode."
  fi

  log "Startinging main process ..."
  exec gosu ezs "$0" "$@"
fi

exec "$@"
