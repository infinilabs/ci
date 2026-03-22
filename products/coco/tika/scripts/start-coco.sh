#!/bin/bash
#
# This script waits for the Easysearch service to become available,
# then acquires a process lock and starts the application.
# It is designed to be robust, configurable, and easy to read.
#

# --- Configuration ---
readonly EASYSEARCH_HOST="127.0.0.1"
readonly EASYSEARCH_PORT="9200"
readonly EASYSEARCH_PROTOCOL="https"
readonly EASYSEARCH_CACERT="/app/easysearch/config/ca.crt"
readonly EASYSEARCH_ADMIN_CERT="/app/easysearch/config/admin.crt"
readonly EASYSEARCH_ADMIN_KEY="/app/easysearch/config/admin.key"

readonly TIMEOUT_SECONDS=300
readonly CHECK_INTERVAL_SECONDS=15
readonly POST_READY_WAIT_SECONDS=30

readonly TIKA_HOST="127.0.0.1"
readonly TIKA_PORT="9998"
readonly TIKA_TIMEOUT_SECONDS=120
readonly TIKA_CHECK_INTERVAL_SECONDS=5

readonly TARGET_NAME="coco"
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

# 1. Wait for Easysearch to be available and healthy using a secure curl command.
log "Checking for required TLS certificates..."
for f in "${EASYSEARCH_CACERT}" "${EASYSEARCH_ADMIN_CERT}" "${EASYSEARCH_ADMIN_KEY}"; do
  if [ ! -f "$f" ]; then
    die "Required certificate file not found: $f"
  fi
done
log "TLS certificates found."

log "Waiting for Easysearch to become available at ${EASYSEARCH_PROTOCOL}://${EASYSEARCH_HOST}:${EASYSEARCH_PORT} (timeout: ${TIMEOUT_SECONDS}s)..."
elapsed_time=0

while ! curl -sfk --cacert "${EASYSEARCH_CACERT}" --cert "${EASYSEARCH_ADMIN_CERT}" --key "${EASYSEARCH_ADMIN_KEY}" "${EASYSEARCH_PROTOCOL}://${EASYSEARCH_HOST}:${EASYSEARCH_PORT}/_cluster/health?local=true" > /dev/null; do
  if [ "${elapsed_time}" -ge "${TIMEOUT_SECONDS}" ]; then
    die "Timeout reached. Easysearch not available or not healthy after ${TIMEOUT_SECONDS} seconds."
  fi

  log "Easysearch not ready, sleeping for ${CHECK_INTERVAL_SECONDS}s..."
  sleep "${CHECK_INTERVAL_SECONDS}"
  elapsed_time=$((elapsed_time + CHECK_INTERVAL_SECONDS))
done
log "Easysearch is available and reports a healthy status."

# 2. Wait an additional period for the service to stabilize.
log "Waiting an additional ${POST_READY_WAIT_SECONDS}s for Easysearch to fully initialize..."
sleep "${POST_READY_WAIT_SECONDS}"

# 3. Wait for Tika to be available.
log "Waiting for Tika to become available at http://${TIKA_HOST}:${TIKA_PORT} (timeout: ${TIKA_TIMEOUT_SECONDS}s)..."
tika_elapsed=0

while ! curl -sf "http://${TIKA_HOST}:${TIKA_PORT}/tika" > /dev/null; do
  if [ "${tika_elapsed}" -ge "${TIKA_TIMEOUT_SECONDS}" ]; then
    die "Timeout reached. Tika not available after ${TIKA_TIMEOUT_SECONDS} seconds."
  fi

  log "Tika not ready, sleeping for ${TIKA_CHECK_INTERVAL_SECONDS}s..."
  sleep "${TIKA_CHECK_INTERVAL_SECONDS}"
  tika_elapsed=$((tika_elapsed + TIKA_CHECK_INTERVAL_SECONDS))
done
log "Tika is available."

# 4. Check for and handle existing lock file in the dynamic node path.
log "Searching for lock file in ${NODES_DIR}..."

lock_file=$(find "${NODES_DIR}" -mindepth 2 -maxdepth 2 -type f -name ".lock" | head -n 1)

if [ -n "${lock_file}" ]; then
  log "Found lock file: ${lock_file}"
  pid=$(cat "${lock_file}")

  if [ -n "$pid" ] && [ "$pid" -eq "$pid" ] 2>/dev/null && ps -p "$pid" > /dev/null 2>&1; then
    die "A process (PID ${pid}) associated with the lock file is already running. Exiting."
  else
    log "Found stale or invalid lock file (PID ${pid}). Removing it."
    rm -f "${lock_file}"
  fi
else
  log "No existing lock file found. Proceeding with startup."
fi

# 5. Check permissions and ownership
KS="$(find "$NODES_DIR" -type f -name ks -not -user "easysearch" -print -quit 2>/dev/null)"
if [ "$(stat -c %U $WORKING_DIR)" != "easysearch" ] || [ -n "$KS" ]; then
  log "Fixing permissions for ks file(s) and working directory..."
  chown -RLf 602:602 "$WORKING_DIR" || die "Failed to change ownership for working directory."
fi

# 6. Change to the working directory.
log "Changing directory to ${WORKING_DIR}."
cd "${WORKING_DIR}" || die "Failed to change directory to ${WORKING_DIR}."

# 7. Start the process.
log "Starting ${TARGET_NAME} process..."

exec gosu easysearch "./${TARGET_NAME}"