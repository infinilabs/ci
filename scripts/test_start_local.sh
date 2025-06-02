#!/bin/bash

# Strict mode
set -euo pipefail

# --- Script Configuration (passed as environment variables or arguments) ---
SCENARIO_TO_RUN="${SCENARIO_TO_RUN_ARG:-default-run}"
SCRIPT_URL="${SCRIPT_URL_ARG}"
DEFAULT_PASSWORD="${DEFAULT_PASSWORD_ARG}"
CUSTOM_PASSWORD="${CUSTOM_PASSWORD_ARG}"
NUM_NODES_EXPECTED="${NUM_NODES_EXPECTED_ARG:-1}"
CHECK_TIMEOUT=300

# --- Helper Functions (optional, can be part of this script) ---
log_info() {
  echo "INFO: [test_runner] $1"
}

log_error() {
  echo "ERROR: [test_runner] $1" >&2
}

cleanup_and_exit_failure() {
  log_error "$1"

  # check the logs
  log_info "Fetching logs for debugging..."
  curl -fsSL "${SCRIPT_URL}" | bash -s -- logs || log_info "Failed to fetch logs, continuing cleanup."

  log_info "Attempting cleanup after failure..."
  # Assuming startlocal directory is in current working directory
  if [ -d "./startlocal" ]; then
    # Use the SCRIPT_URL for cleanup
    curl -fsSL "${SCRIPT_URL}" | bash -s -- clean || log_info "Cleanup command also had issues."
  else
    log_info "No ./startlocal directory found to clean."
  fi
  exit 1
}

# --- Main Test Logic ---
log_info "Starting test scenario: ${SCENARIO_TO_RUN}"
log_info "Working directory: $(pwd)"
log_info "jq version: $(jq --version || echo 'jq not found, script might fail')"

if [[ "${SCENARIO_TO_RUN}" == "default-run" ]]; then
  log_info "Script URL: ${SCRIPT_URL}"
  log_info "Default Password: ${DEFAULT_PASSWORD}"

  curl -fsSL "${SCRIPT_URL}" | bash -s -- up
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Default UP failed"; fi

  log_info "Waiting for default Easysearch (max ${CHECK_TIMEOUT}s)..."
  timeout_seconds=${CHECK_TIMEOUT}; interval=10; elapsed=0; service_ready=false
  while [ $elapsed -lt $timeout_seconds ]; do
    if curl --retry 3 --retry-delay 3 -s -ku admin:"${DEFAULT_PASSWORD}" "https://localhost:9200/_cluster/health" | jq -e '.status == "green" or .status == "yellow"' > /dev/null; then
      log_info "Default Easysearch is healthy."
      service_ready=true; break
    fi
    log_info "Default Easysearch not healthy yet ($((elapsed+interval))s)..."
    sleep $interval; elapsed=$((elapsed + interval))
  done
  if ! $service_ready; then cleanup_and_exit_failure "Default Easysearch did not become healthy"; fi

  log_info "Default run successful. Cleaning up..."
  curl -fsSL "${SCRIPT_URL}" | bash -s -- clean
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Default CLEAN failed"; fi
  if [ -d "./startlocal" ]; then cleanup_and_exit_failure "Work dir ./startlocal still exists!"; fi
  log_info "Default run scenario completed successfully."

elif [[ "${SCENARIO_TO_RUN}" == "custom-run" ]]; then
  log_info "Script URL: ${SCRIPT_URL}"
  log_info "Custom Password: ${CUSTOM_PASSWORD}"
  log_info "Expected Nodes: ${NUM_NODES_EXPECTED}"

  curl -fsSL "${SCRIPT_URL}" | bash -s -- up --nodes "${NUM_NODES_EXPECTED}" --password "${CUSTOM_PASSWORD}"
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Custom UP failed"; fi

  log_info "Waiting for custom Easysearch (${NUM_NODES_EXPECTED} nodes, max ${NUM_NODES_EXPECTED}s)..."
  timeout_seconds=${NUM_NODES_EXPECTED}; interval=10; elapsed=0; cluster_ready_and_nodes_verified=false
  while [ $elapsed -lt $timeout_seconds ]; do
    health_json=$(curl --retry 3 --retry-delay 3 -s -ku admin:"${CUSTOM_PASSWORD}" "https://localhost:9200/_cluster/health?format=json")
    if echo "${health_json}" | jq -e '.status == "green"' > /dev/null; then
      nodes_json=$(curl --retry 3 --retry-delay 3 -s -ku admin:"${CUSTOM_PASSWORD}" "https://localhost:9200/_cat/nodes?format=json")
      actual_nodes_in_cluster=$(echo "${nodes_json}" | jq 'length')
      if [ "${actual_nodes_in_cluster}" -eq "${NUM_NODES_EXPECTED}" ]; then
        log_info "Custom Easysearch is healthy with ${actual_nodes_in_cluster} nodes."
        cluster_ready_and_nodes_verified=true; break
      else
        log_info "Custom Easysearch healthy, but node count is ${actual_nodes_in_cluster} (expected ${NUM_NODES_EXPECTED}). Waiting..."
      fi
    else
      log_info "Custom Easysearch not green yet ($((elapsed+interval))s). Status: $(echo ${health_json} | jq -r .status)"
    fi
    sleep $interval; elapsed=$((elapsed + interval))
  done
  if ! $cluster_ready_and_nodes_verified; then cleanup_and_exit_failure "Custom Easysearch did not become healthy with correct node count"; fi

  log_info "Custom run successful. Cleaning up..."
  curl -fsSL "${SCRIPT_URL}" | bash -s -- clean
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Custom CLEAN failed"; fi
  if [ -d "./startlocal" ]; then cleanup_and_exit_failure "Work dir ./startlocal still exists!"; fi
  log_info "Custom run scenario completed successfully."

else
  log_error "Unknown scenario: ${SCENARIO_TO_RUN}"
  exit 1
fi