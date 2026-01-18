#!/bin/bash
#
# This script waits for the Elasticsearch service to become available,
# then acquires a process lock and starts the application.
# It is designed to be robust, configurable, and easy to read.
#

# --- Configuration ---
readonly ELASTICSEARCH_HOST="127.0.0.1"
readonly ELASTICSEARCH_PORT="9200"
readonly TIMEOUT_SECONDS=300
readonly CHECK_INTERVAL_SECONDS=15
readonly POST_READY_WAIT_SECONDS=30

readonly TARGET_NAME="agent"
readonly WORKING_DIR="/app/easysearch/data/${TARGET_NAME}"
# Define the parent directory where the dynamic node lock files are located.
readonly NODES_DIR="${WORKING_DIR}/data/${TARGET_NAME}/nodes"

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Helper Functions ---

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] [start-${TARGET_NAME}] $*"
}

die() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] [start-${TARGET_NAME}] $*" >&2
  exit 1
}

# --- Main Logic ---

# 1. Wait for Elasticsearch to be available.
log "Waiting for Elasticsearch to become available at ${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT} (timeout: ${TIMEOUT_SECONDS}s)..."
elapsed_time=0
while ! nc -z "${ELASTICSEARCH_HOST}" "${ELASTICSEARCH_PORT}" 2>/dev/null; do
  if [ "${elapsed_time}" -ge "${TIMEOUT_SECONDS}" ]; then
    die "Timeout reached. Elasticsearch not available after ${TIMEOUT_SECONDS} seconds."
  fi
  
  log "Elasticsearch not ready, sleeping for ${CHECK_INTERVAL_SECONDS}s..."
  sleep "${CHECK_INTERVAL_SECONDS}"
  elapsed_time=$((elapsed_time + CHECK_INTERVAL_SECONDS))
done
log "Elasticsearch is available."

# 2. Wait an additional period for the service to stabilize.
log "Waiting an additional ${POST_READY_WAIT_SECONDS}s for Elasticsearch to fully initialize..."
sleep "${POST_READY_WAIT_SECONDS}"

# 3. Check for and handle existing lock file in the dynamic node path.
log "Searching for lock file in ${NODES_DIR}..."

# Use 'find' to locate the .lock file. This is safer than using a raw glob (*).
# We search for a file, not a directory, and only one level deep.
lock_file=$(find "${NODES_DIR}" -mindepth 2 -maxdepth 2 -type f -name ".lock" | head -n 1)

if [ -n "${lock_file}" ]; then
  log "Found lock file: ${lock_file}"
  pid=$(cat "${lock_file}")
  
  # Check if the PID is a valid number and if the process exists.
  # Note: In this context, we might not know the exact process name,
  # so a simple PID check is what the original script did.
  if [ -n "$pid" ] && [ "$pid" -eq "$pid" ] 2>/dev/null && ps -p "$pid" > /dev/null 2>&1; then
    die "A process (PID ${pid}) associated with the lock file is already running. Exiting."
  else
    log "Found stale or invalid lock file (PID ${pid}). Removing it."
    rm -f "${lock_file}"
  fi
else
  log "No existing lock file found. Proceeding with startup."
fi


# 4. Check permissions and ownership
KS="$(find "$NODES_DIR" -type f -name ks -not -user "easysearch" -print -quit 2>/dev/null)"
if [ "$(stat -c %U $WORKING_DIR)" != "easysearch" ] || [ -n "$KS" ]; then
  log "Fixing permissions for ks file(s) and working directory..."
  chown -RLf 602:602 "$WORKING_DIR" || die "Failed to change ownership for working directory."
fi

# 5. Change to the working directory.
log "Changing directory to ${WORKING_DIR}."
cd "${WORKING_DIR}" || die "Failed to change directory to ${WORKING_DIR}."

# 6. Start the process.
log "Starting ${TARGET_NAME} process..."

# We don't create a lock file here because the process itself is expected
# to create its own .lock file inside the nodes/*/ directory upon startup.
# The 'exec' command replaces the current shell, which is crucial for supervisord.
exec gosu easysearch "./${TARGET_NAME}"