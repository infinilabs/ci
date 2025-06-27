#!/bin/bash

set -euo pipefail

BASE_PLUGIN_DOWNLOAD_URL="https://get.infini.cloud" 

# --- Input Validation & Defaulting ---
if [[ -z "$ENGINE_TYPE" || -z "$ENGINE_VERSION" ]]; then
  echo -e "\033[31;1mERROR:\033[0m Required environment variables [ENGINE_TYPE, ENGINE_VERSION] not set."
  exit 1
fi

ENGINE_TYPE=$(echo "$ENGINE_TYPE" | tr '[:upper:]' '[:lower:]')

CONTAINER_NAME=${CONTAINER_NAME:-search-engine-node}
ENGINE_PORT=${ENGINE_PORT:-9200}
JAVA_OPTS=${JAVA_OPTS-"-Xms1g -Xmx1g"} 
WAIT_SECONDS=${WAIT_SECONDS:-60} 
NETWORK_NAME="search-engine-net"

# --- Engine Specific Configuration ---
IMAGE_NAME=""
PLUGIN_INSTALL_CMD=""
CONFIG_DIR_HOST="$PWD/engine_config"
PLUGIN_DIR_HOST="$PWD/engine_plugins"
CONFIG_DIR_CONTAINER=""
PLUGIN_DIR_CONTAINER=""
DEFAULT_USER=""
HEALTH_CHECK_USER=""
HEALTH_CHECK_PASS=""
HEALTH_CHECK_PROTOCOL="http"
DOCKER_ENV_VARS=() 

# Create network if it doesn't exist
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"

# Prepare config/plugin directory on host
mkdir -p "$CONFIG_DIR_HOST"
chown -R 1000:1000 "$CONFIG_DIR_HOST"
mkdir -p "$PLUGIN_DIR_HOST"
chown -R 1000:1000 "$PLUGIN_DIR_HOST"

if [[ "$ENGINE_TYPE" == "elasticsearch" ]]; then
  IMAGE_NAME="docker.elastic.co/elasticsearch/elasticsearch:${ENGINE_VERSION}"
  PLUGIN_INSTALL_CMD_BASE="/usr/share/elasticsearch/bin/elasticsearch-plugin"
  CONFIG_DIR_CONTAINER="/usr/share/elasticsearch/config"
  PLUGIN_DIR_CONTAINER="/usr/share/elasticsearch/plugins"
  DEFAULT_USER="elastic"
  DOCKER_ENV_VARS+=(
    "-e" "discovery.type=single-node"
    "-e" "ES_JAVA_OPTS=${JAVA_OPTS}"
    "-e" "xpack.license.self_generated.type=trial"
    "-e" "action.destructive_requires_name=false"
  )
  # Security plugin configuration
  SECURITY_ENABLED=${SECURITY_ENABLED_INPUT:-true}
  MAJOR_VERSION=$(echo "$ENGINE_VERSION" | cut -d. -f1)
  if [[ "$MAJOR_VERSION" -lt 8 ]]; then
    SECURITY_ENABLED=${SECURITY_ENABLED_INPUT:-false}
    DOCKER_ENV_VARS+=("-e" "xpack.security.enabled=${SECURITY_ENABLED}")
  fi

  if [[ "$SECURITY_ENABLED" == "true" ]]; then
    HEALTH_CHECK_PASS=${ENGINE_PASSWORD:-infinilabs}
    DOCKER_ENV_VARS+=("-e" "ELASTIC_PASSWORD=${HEALTH_CHECK_PASS}")
    HEALTH_CHECK_USER="$DEFAULT_USER"
    HEALTH_CHECK_PROTOCOL="https"
  fi

elif [[ "$ENGINE_TYPE" == "opensearch" ]]; then
  IMAGE_NAME="opensearchproject/opensearch:${ENGINE_VERSION}"
  PLUGIN_INSTALL_CMD_BASE="/usr/share/opensearch/bin/opensearch-plugin"
  CONFIG_DIR_CONTAINER="/usr/share/opensearch/config"
  PLUGIN_DIR_CONTAINER="/usr/share/opensearch/plugins"
  DEFAULT_USER="admin"
  DOCKER_ENV_VARS+=(
    "-e" "discovery.type=single-node"
    "-e" "OPENSEARCH_JAVA_OPTS=${JAVA_OPTS}"
  )
  # Security plugin configuration
  SECURITY_ENABLED=${SECURITY_ENABLED_INPUT:-false} 
  if [[ "$SECURITY_ENABLED" == "true" ]]; then
    DOCKER_ENV_VARS+=("-e" "plugins.security.disabled=false")
    HEALTH_CHECK_PASS=${ENGINE_PASSWORD:-infinilabs}
    DOCKER_ENV_VARS+=("-e" "OPENSEARCH_INITIAL_ADMIN_PASSWORD=${HEALTH_CHECK_PASS}")
    HEALTH_CHECK_USER="$DEFAULT_USER"
    HEALTH_CHECK_PROTOCOL="https"
  else
    DOCKER_ENV_VARS+=("-e" "plugins.security.disabled=true")
    HEALTH_CHECK_USER=""
    HEALTH_CHECK_PASS=""
    HEALTH_CHECK_PROTOCOL="http"
  fi

else
  echo
  echo -e "\033[31;1mERROR:\033[0m Unsupported ENGINE_TYPE: [$ENGINE_TYPE]. Must be 'elasticsearch' or 'opensearch'."
  exit 1
fi

echo "Using image: $IMAGE_NAME"
echo "Container name: $CONTAINER_NAME"
echo "Host config directory: $CONFIG_DIR_HOST"
echo "Container config directory: $CONFIG_DIR_CONTAINER"
echo "Host plugin directory: $PLUGIN_DIR_HOST"
echo "Container plugin directory: $PLUGIN_DIR_CONTAINER"

# --- Prepare Config Directory ---
echo "Attemppting to prepare config directory: $CONFIG_DIR_HOST"
docker run --rm \
    --user="0:0" \
    --entrypoint="/bin/sh" \
    -v "$CONFIG_DIR_HOST:/mnt/host_config:rw" \
    "$IMAGE_NAME" \
    -c "cp -a $CONFIG_DIR_CONTAINER/. /mnt/host_config/ && echo 'Copied default config from $CONFIG_DIR_CONTAINER to host.'"

# --- Plugin Installation ---
# ENGINE_PLUGINS: analysis-ik,analysis-pinyin,analysis-strconvert
if [[ -n "$ENGINE_PLUGINS" ]]; then
  echo "Attempting to install plugins: $ENGINE_PLUGINS"
  IFS=',' read -r -a PLUGIN_NAME_ARRAY <<< "$ENGINE_PLUGINS"
  for PNAME in "${PLUGIN_NAME_ARRAY[@]}"; do
    PNAME=$(echo "$PNAME" | xargs) # Trim whitespace
    if [[ -z "$PNAME" ]]; then continue; fi

    PLUGIN_URL="${BASE_PLUGIN_DOWNLOAD_URL}/${ENGINE_TYPE}/${PNAME}/${ENGINE_VERSION}"
    
    echo "Installing plugin '$PNAME' from URL: $PLUGIN_URL ..."
    # Install plugin using the appropriate command
    docker run --rm \
      --user="0:0" \
      -v "$CONFIG_DIR_HOST:$CONFIG_DIR_CONTAINER:rw" \
      -v "$PLUGIN_DIR_HOST:$PLUGIN_DIR_CONTAINER:rw" \
      "$IMAGE_NAME" \
      sh -c "$PLUGIN_INSTALL_CMD_BASE install \"$PLUGIN_URL\" --batch && echo 'Plugin $PNAME installed successfully.'"
  done
  echo "Plugin installation phase complete."
fi

# --- Start Search Engine Container ---
echo "Starting $ENGINE_TYPE node..."
DOCKER_RUN_CMD=(
  "docker" "run"
  "--rm"
  "--detach"
  "--name" "$CONTAINER_NAME"
  "--network" "$NETWORK_NAME"
  "--publish" "${ENGINE_PORT}:${ENGINE_PORT}"
  "--ulimit" "nofile=65536:65536"
  "--ulimit" "memlock=-1:-1"
  "-v" "$PLUGIN_DIR_HOST:$PLUGIN_DIR_CONTAINER"
  "-v" "$CONFIG_DIR_HOST:$CONFIG_DIR_CONTAINER"
)

# Add environment variables
for env_var_pair in "${DOCKER_ENV_VARS[@]}"; do
  DOCKER_RUN_CMD+=("$env_var_pair")
done

# Add image name
DOCKER_RUN_CMD+=("$IMAGE_NAME")

echo -e "====== Running command ======\n${DOCKER_RUN_CMD[*]}"

# Execute the command
"${DOCKER_RUN_CMD[@]}"

echo "$ENGINE_TYPE container $CONTAINER_NAME started."

# --- Health Check ---
echo "Waiting for $ENGINE_TYPE to become healthy (max ${WAIT_SECONDS}s)..."
PROTOCOL=$HEALTH_CHECK_PROTOCOL
URL="${PROTOCOL}://$CONTAINER_NAME:${ENGINE_PORT}"
HEALTH_CHECK_URL="${URL}/_cluster/health?wait_for_status=yellow&timeout=5s&pretty"

CURL_USER_OPT=""
if [[ -n "$HEALTH_CHECK_USER" && -n "$HEALTH_CHECK_PASS" ]]; then
  CURL_USER_OPT="-u ${HEALTH_CHECK_USER}:${HEALTH_CHECK_PASS}"
fi

CURL_INSECURE_OPT=""
if [[ "$PROTOCOL" == "https" ]]; then
  CURL_INSECURE_OPT="-k"
fi

SECONDS_WAITED=0
until docker run --network "$NETWORK_NAME" --rm appropriate/curl --silent --show-error $CURL_INSECURE_OPT $CURL_USER_OPT "$HEALTH_CHECK_URL"; do
  if [[ $SECONDS_WAITED -ge $WAIT_SECONDS ]]; then
    echo -e "\033[31;1mERROR:\033[0m $ENGINE_TYPE did not become healthy within $WAIT_SECONDS seconds."
    echo "Container logs for $CONTAINER_NAME:"
    docker logs "$CONTAINER_NAME"
    exit 1
  fi
  echo "Still waiting for $ENGINE_TYPE ($SECONDS_WAITED/$WAIT_SECONDS)..."
  sleep 5
  SECONDS_WAITED=$((SECONDS_WAITED + 5))
done

echo
echo -e "\033[32;1m$ENGINE_TYPE is up and running at $URL\033[0m"
docker run --network "$NETWORK_NAME" --rm appropriate/curl --silent $CURL_INSECURE_OPT $CURL_USER_OPT "$URL"