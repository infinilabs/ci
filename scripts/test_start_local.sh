#!/bin/bash

# Strict mode
set -euo pipefail

# --- Script Configuration (passed as environment variables or arguments) ---
SCENARIO_TO_RUN="${SCENARIO_TO_RUN_ARG:-default-run}" # Default to 'default-run' if not set
SCRIPT_URL="${SCRIPT_URL_ARG}"
DEFAULT_PASSWORD="${DEFAULT_PASSWORD_ARG}"
CUSTOM_PASSWORD="${CUSTOM_PASSWORD_ARG}"
NUM_NODES_EXPECTED="${NUM_NODES_EXPECTED_ARG:-1}" # Default to 1 if not set for custom run
CHECK_TIMEOUT="${CHECK_TIMEOUT_ARG:-300}" # Default timeout if not provided

# --- Helper Functions ---
log_info() {
  echo "INFO: [test_runner] $1"
}

log_error() {
  echo "ERROR: [test_runner] $1" >&2
}

cleanup_and_exit_failure() {
  log_error "$1"

  # Attempt to fetch logs for debugging, but don't let this stop the cleanup.
  log_info "Fetching logs for debugging (if possible)..."
  # The 'start-local.sh logs' command might itself depend on a running environment.
  # Use a timeout or run in background if it can hang.
  # For simplicity, just try and continue.
  (curl -fsSL "${SCRIPT_URL}" | bash -s -- logs & PID=$! ; sleep 30 ; kill $PID 2>/dev/null || true) || log_info "Failed to fetch logs or timed out, continuing cleanup."


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
log_info "jq version: $(jq --version || echo 'jq not found, script might fail if scenario needs it')"
log_info "CHECK_TIMEOUT is set to: ${CHECK_TIMEOUT}s"


if [[ "${SCENARIO_TO_RUN}" == "default-run" ]]; then
  log_info "Script URL: ${SCRIPT_URL}"
  log_info "Default Password: ${DEFAULT_PASSWORD}"

  curl -fsSL "${SCRIPT_URL}" | bash -s -- up
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Default UP failed"; fi

  log_info "Waiting for default Easysearch (max ${CHECK_TIMEOUT}s)..."
  timeout_seconds=${CHECK_TIMEOUT}; interval=10; elapsed=0; service_ready=false
  body_file="default_health_body.tmp" # Temporary file for curl response body

  while [ $elapsed -lt $timeout_seconds ]; do
    log_info "Attempting health check for default Easysearch ($((elapsed))s / ${timeout_seconds}s)..."
    
    # Capture HTTP status code and body separately from curl
    # Added -k for insecure HTTPS as in your original script
    # --fail would make curl exit with 22 on HTTP 4xx/5xx, useful for quick http error check
    # Using -w "%{http_code}" to get HTTP status, and -o to save body
    http_code=$(curl --fail --connect-timeout 10 --retry 3 --retry-delay 3 \
                     -s -k -w "%{http_code}" \
                     -u "admin:${DEFAULT_PASSWORD}" \
                     "https://localhost:9200/_cluster/health" \
                     -o "${body_file}")
    curl_exit_code=$?

    # Check if curl command was successful and HTTP status is 200
    if [ $curl_exit_code -eq 0 ] && [[ "$http_code" == "200" ]]; then
      # Curl succeeded and got HTTP 200, now attempt to parse JSON with jq
      # jq -e will set exit code based on query result (true/false/null) or parse error
      if jq -e '.status == "green" or .status == "yellow"' "${body_file}" > /dev/null; then
        log_info "Default Easysearch is healthy."
        service_ready=true
        break # Exit while loop
      else
        # jq parsing failed or health status not as expected from a 200 OK response
        log_info "Default Easysearch responded HTTP 200, but health status not green/yellow or JSON invalid. jq exit: $?. Body:"
        cat "${body_file}" # Log the body for debugging
      fi
    else
      # curl command itself failed (network error, non-200 HTTP status with --fail, etc.)
      log_info "Default Easysearch not reachable or HTTP error. curl exit: $curl_exit_code, HTTP code: $http_code. Body (if any):"
      if [ -f "${body_file}" ]; then # Body file might exist even if HTTP code wasn't 200 (e.g. 401 with body)
        cat "${body_file}"
      else
        echo "(No response body captured or curl command failed before writing)"
      fi
    fi
    
    # Clean up temp file for the next iteration
    rm -f "${body_file}" 

    log_info "Retrying health check in ${interval}s..."
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  
  # Clean up temp file one last time in case loop exited due to timeout
  rm -f "${body_file}" 

  if ! $service_ready; then cleanup_and_exit_failure "Default Easysearch did not become healthy within ${timeout_seconds}s"; fi

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

  log_info "Waiting for custom Easysearch (${NUM_NODES_EXPECTED} nodes, max ${CHECK_TIMEOUT}s)..."
  timeout_seconds=${CHECK_TIMEOUT}; interval=10; elapsed=0; cluster_ready_and_nodes_verified=false
  health_body_file="custom_health_body.tmp"
  nodes_body_file="custom_nodes_body.tmp"

  while [ $elapsed -lt $timeout_seconds ]; do
    log_info "Attempting health check for custom Easysearch ($((elapsed))s / ${timeout_seconds}s)..."
    
    # Check cluster health first
    health_http_code=$(curl --fail --connect-timeout 10 --retry 3 --retry-delay 3 \
                           -s -k -w "%{http_code}" \
                           -u "admin:${CUSTOM_PASSWORD}" \
                           "https://localhost:9200/_cluster/health?format=json" \
                           -o "${health_body_file}")
    health_curl_exit_code=$?

    if [ $health_curl_exit_code -eq 0 ] && [[ "$health_http_code" == "200" ]]; then
      # Expect "green" status for multi-node cluster
      if jq -e '.status == "green"' "${health_body_file}" > /dev/null; then
        log_info "Custom Easysearch health is green. Checking node count..."
        
        # If health is green, check node count
        nodes_http_code=$(curl --fail --connect-timeout 10 --retry 3 --retry-delay 3 \
                               -s -k -w "%{http_code}" \
                               -u "admin:${CUSTOM_PASSWORD}" \
                               "https://localhost:9200/_cat/nodes?format=json" \
                               -o "${nodes_body_file}")
        nodes_curl_exit_code=$?

        if [ $nodes_curl_exit_code -eq 0 ] && [[ "$nodes_http_code" == "200" ]]; then
          # _cat/nodes?format=json returns a JSON array
          actual_nodes_in_cluster=$(jq 'length' "${nodes_body_file}") # jq 'length' for array size
          if [ "$actual_nodes_in_cluster" -eq "${NUM_NODES_EXPECTED}" ]; then
            log_info "Custom Easysearch node count matches: $actual_nodes_in_cluster."
            cluster_ready_and_nodes_verified=true
            break # Exit while loop
          else
            log_info "Custom Easysearch health is green, but node count is $actual_nodes_in_cluster (expected ${NUM_NODES_EXPECTED}). Nodes API output:"
            cat "${nodes_body_file}"
          fi
        else
          log_info "Failed to get _cat/nodes information. curl exit: $nodes_curl_exit_code, HTTP code: $nodes_http_code. Body (if any):"
          if [ -f "${nodes_body_file}" ]; then cat "${nodes_body_file}"; else echo "(No body from _cat/nodes)"; fi
        fi
        rm -f "${nodes_body_file}" # Clean up nodes temp file
      else
        # Health status not green from a 200 OK response
        log_info "Custom Easysearch responded HTTP 200, but status not green. jq exit: $?. Health API output:"
        cat "${health_body_file}"
      fi
    else
      # Health check curl command failed or got non-200 HTTP status
      log_info "Custom Easysearch health check failed. curl exit: $health_curl_exit_code, HTTP code: $health_http_code. Body (if any):"
      if [ -f "${health_body_file}" ]; then cat "${health_body_file}"; else echo "(No body from health check)"; fi
    fi
    
    rm -f "${health_body_file}" # Clean up health temp file

    log_info "Retrying custom Easysearch check in ${interval}s..."
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  # Final cleanup of temp files
  rm -f "${health_body_file}" "${nodes_body_file}"

  if ! $cluster_ready_and_nodes_verified; then cleanup_and_exit_failure "Custom Easysearch did not become healthy with correct node count within ${timeout_seconds}s"; fi

  log_info "Custom run successful. Cleaning up..."
  curl -fsSL "${SCRIPT_URL}" | bash -s -- clean
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Custom CLEAN failed"; fi
  if [ -d "./startlocal" ]; then cleanup_and_exit_failure "Work dir ./startlocal still exists!"; fi
  log_info "Custom run scenario completed successfully."

else
  log_error "Unknown scenario: ${SCENARIO_TO_RUN}"
  exit 1
fi