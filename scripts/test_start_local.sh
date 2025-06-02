#!/bin/bash

# Strict mode
set -euo pipefail # -e: exit on error, -u: treat unset variables as error, -o pipefail: exit if any command in a pipe fails

# --- Script Configuration (expected as environment variables from GitHub Actions) ---
SCENARIO_TO_RUN="${SCENARIO_TO_RUN_ARG:-default-run}"
SCRIPT_URL="${SCRIPT_URL_ARG}"
DEFAULT_PASSWORD="${DEFAULT_PASSWORD_ARG}"
CUSTOM_PASSWORD="${CUSTOM_PASSWORD_ARG}"
NUM_NODES_EXPECTED="${NUM_NODES_EXPECTED_ARG:-1}" # Default to 1 for custom run if not specified
CHECK_TIMEOUT="${CHECK_TIMEOUT_ARG:-300}"       # Default timeout for health checks
PORT_TO_CHECK="9200"                            # Port that Easysearch HTTP service should be on
HOST_TO_CHECK="localhost"                       # Host for health checks

# --- Helper Functions ---
log_info() {
  echo "INFO: [test_runner] $1"
}

log_error() {
  echo "ERROR: [test_runner] $1" >&2
}

# Function to attempt fetching logs from start-local.sh script.
# Runs in background with a timeout to prevent blocking cleanup indefinitely.
try_fetch_app_logs() {
  log_info "Attempting to fetch application logs via 'start-local.sh logs' (max 30s)..."
  # Run in a subshell to manage timeout independently
  (
    # Ensure SCRIPT_URL is available in the subshell if not exported globally
    # For simplicity, assuming it's inherited or re-exported if needed.
    # The 'curl | bash' part might need careful handling of variables if SCRIPT_URL is not directly accessible.
    # If SCRIPT_URL is an env var, it should be fine.
    curl -fsSL "${SCRIPT_URL}" | bash -s -- logs &
    LOGS_PID=$!
    # Wait for a bit, then kill if still running
    # This is a very basic timeout mechanism for the logs command
    for _ in $(seq 1 6); do # Check every 5 seconds for 30 seconds
        if ! kill -0 $LOGS_PID 2>/dev/null; then # Process finished
            wait $LOGS_PID # Capture exit code
            log_info "Logs command finished."
            return
        fi
        sleep 5
    done
    log_info "Logs command still running after 30s, attempting to kill."
    kill $LOGS_PID 2>/dev/null || true # Kill the process
    wait $LOGS_PID 2>/dev/null || true # Reap the process
    log_info "Logs command killed or finished."
  ) || log_info "There was an issue trying to fetch or timeout the logs command."
}


cleanup_and_exit_failure() {
  log_error "$1"
  try_fetch_app_logs # Attempt to get application logs for debugging

  log_info "Attempting cleanup using 'start-local.sh clean' after failure..."
  if [ -d "./startlocal" ]; then # Check if the work directory exists
    curl -fsSL "${SCRIPT_URL}" | bash -s -- clean || log_info "Cleanup command ('start-local.sh clean') also had issues."
  else
    log_info "No ./startlocal directory found (relative to current dir: $(pwd)). Skipping 'start-local.sh clean'."
  fi
  exit 1
}

# Function to check if a TCP port is open
# Arguments: $1 host, $2 port, $3 timeout_for_single_check (optional, defaults to 3s)
is_port_open() {
  local host="$1"
  local port="$2"
  local check_timeout_seconds="${3:-3}"

  # Try bash /dev/tcp first (works on most Linux/macOS if 'timeout' command is available)
  if command -v timeout &> /dev/null; then
    if timeout "${check_timeout_seconds}" bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
      return 0 # Port is open
    else
      return 1 # Port is closed, unreachable, or timed out
    fi
  # Fallback to nc (netcat) if 'timeout' is not available
  elif command -v nc &> /dev/null; then
    # nc -z -w <timeout_seconds> host port
    if nc -z -w "${check_timeout_seconds}" "${host}" "${port}" >/dev/null 2>&1; then
      return 0 # Port is open
    else
      return 1 # Port is closed or timed out
    fi
  else
    log_info "Warning: Neither 'timeout' (for /dev/tcp check) nor 'nc' command found. Skipping direct port check for ${host}:${port}."
    # Cannot reliably check port without these tools. Assume we should proceed to curl.
    # Curl itself will fail if the port is closed.
    return 0 # Returning 0 means the calling loop won't break due to lack of port check tool,
             # allowing curl to be the ultimate decider.
  fi
}

# --- Main Test Logic ---
log_info "Starting test scenario: ${SCENARIO_TO_RUN}"
log_info "Target SCRIPT_URL: ${SCRIPT_URL}"
log_info "Working directory: $(pwd)"
log_info "Verifying jq: $(jq --version || echo 'jq not found or not in PATH. Script might fail.')"
log_info "Health CHECK_TIMEOUT is set to: ${CHECK_TIMEOUT}s"
log_info "Easysearch HOST_TO_CHECK: ${HOST_TO_CHECK}"
log_info "Easysearch PORT_TO_CHECK: ${PORT_TO_CHECK}"


if [[ "${SCENARIO_TO_RUN}" == "default-run" ]]; then
  log_info "Running: Default Scenario"
  log_info "Default Password: (hidden for security, using variable)"

  # Execute the 'up' command using start-local.sh
  curl -fsSL "${SCRIPT_URL}" | bash -s -- up
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Default 'start-local.sh up' command failed"; fi

  log_info "Waiting for default Easysearch (port ${PORT_TO_CHECK} and health, max ${CHECK_TIMEOUT}s)..."
  timeout_seconds=${CHECK_TIMEOUT}; interval=10; elapsed=0; service_ready=false
  body_file="default_health_body.tmp" # Temporary file for curl response body

  while [ $elapsed -lt $timeout_seconds ]; do
    log_info "Attempting check for default Easysearch (${elapsed}s / ${timeout_seconds}s)..."
    
    if is_port_open "${HOST_TO_CHECK}" "${PORT_TO_CHECK}"; then
      log_info "Port ${PORT_TO_CHECK} on ${HOST_TO_CHECK} is open. Checking service health..."
      
      # If port is open, then attempt curl for health check
      # Using http, assuming start-local.sh defaults to HTTP unless explicitly configured for HTTPS
      http_code=$(curl --fail --connect-timeout 10 --retry 2 --retry-delay 3 \
                       -s -w "%{http_code}" \
                       -u "admin:${DEFAULT_PASSWORD}" \
                       "http://${HOST_TO_CHECK}:${PORT_TO_CHECK}/_cluster/health" \
                       -o "${body_file}")
      curl_exit_code=$?

      if [ $curl_exit_code -eq 0 ] && [[ "$http_code" == "200" ]]; then
        if jq -e '.status == "green" or .status == "yellow"' "${body_file}" > /dev/null; then
          log_info "Default Easysearch is healthy (status green or yellow)."
          service_ready=true
          break
        else
          log_info "Port open, HTTP 200, but health status not green/yellow or JSON invalid. jq exit: $?. Body:"
          cat "${body_file}" || log_info "Could not cat body file."
        fi
      else
        log_info "Port open, but health check failed. curl exit: $curl_exit_code, HTTP code: $http_code. Body (if any):"
        if [ -f "${body_file}" ]; then cat "${body_file}" || log_info "Could not cat body file."; else echo "(No response body)"; fi
      fi
    else
      log_info "Port ${PORT_TO_CHECK} on ${HOST_TO_CHECK} is not open yet."
    fi
    
    rm -f "${body_file}" # Clean up temp file for this iteration

    log_info "Retrying health check in ${interval}s..."
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  
  rm -f "${body_file}" # Final cleanup of temp file
  if ! $service_ready; then cleanup_and_exit_failure "Default Easysearch did not become healthy within ${timeout_seconds}s"; fi

  log_info "Default run successful. Cleaning up..."
  curl -fsSL "${SCRIPT_URL}" | bash -s -- clean
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Default 'start-local.sh clean' command failed"; fi
  if [ -d "./startlocal" ]; then cleanup_and_exit_failure "Work dir ./startlocal still exists after clean!"; fi
  log_info "Default run scenario completed successfully."

elif [[ "${SCENARIO_TO_RUN}" == "custom-run" ]]; then
  log_info "Running: Custom Scenario"
  log_info "Custom Password: (hidden for security, using variable)"
  log_info "Expected Nodes: ${NUM_NODES_EXPECTED}"

  curl -fsSL "${SCRIPT_URL}" | bash -s -- up --nodes "${NUM_NODES_EXPECTED}" --password "${CUSTOM_PASSWORD}"
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Custom 'start-local.sh up' command failed"; fi

  log_info "Waiting for custom Easysearch (port ${PORT_TO_CHECK}, ${NUM_NODES_EXPECTED} nodes, max ${CHECK_TIMEOUT}s)..."
  timeout_seconds=${CHECK_TIMEOUT}; interval=10; elapsed=0; cluster_ready_and_nodes_verified=false
  health_body_file="custom_health_body.tmp"
  nodes_body_file="custom_nodes_body.tmp"

  while [ $elapsed -lt $timeout_seconds ]; do
    log_info "Attempting check for custom Easysearch (${elapsed}s / ${timeout_seconds}s)..."

    if is_port_open "${HOST_TO_CHECK}" "${PORT_TO_CHECK}"; then
      log_info "Port ${PORT_TO_CHECK} on ${HOST_TO_CHECK} is open. Checking service health for custom Easysearch..."
      
      health_http_code=$(curl --fail --connect-timeout 10 --retry 2 --retry-delay 3 \
                             -s -w "%{http_code}" \
                             -u "admin:${CUSTOM_PASSWORD}" \
                             "http://${HOST_TO_CHECK}:${PORT_TO_CHECK}/_cluster/health?format=json" \
                             -o "${health_body_file}")
      health_curl_exit_code=$?

      if [ $health_curl_exit_code -eq 0 ] && [[ "$health_http_code" == "200" ]]; then
        # For multi-node, we expect "green" status
        if jq -e '.status == "green"' "${health_body_file}" > /dev/null; then
          log_info "Custom Easysearch health is green. Checking node count..."
          
          nodes_http_code=$(curl --fail --connect-timeout 10 --retry 2 --retry-delay 3 \
                                 -s -w "%{http_code}" \
                                 -u "admin:${CUSTOM_PASSWORD}" \
                                 "http://${HOST_TO_CHECK}:${PORT_TO_CHECK}/_cat/nodes?format=json" \
                                 -o "${nodes_body_file}")
          nodes_curl_exit_code=$?

          if [ $nodes_curl_exit_code -eq 0 ] && [[ "$nodes_http_code" == "200" ]];
          then
            # _cat/nodes?format=json returns a JSON array
            actual_nodes_in_cluster=$(jq 'length' "${nodes_body_file}")
            if [ "$actual_nodes_in_cluster" -eq "${NUM_NODES_EXPECTED}" ]; then
              log_info "Custom Easysearch node count matches: $actual_nodes_in_cluster."
              cluster_ready_and_nodes_verified=true
              break # Exit while loop
            else
              log_info "Custom Easysearch health green, but node count $actual_nodes_in_cluster (expected ${NUM_NODES_EXPECTED}). Nodes API output:"
              cat "${nodes_body_file}" || log_info "Could not cat nodes body file."
            fi
          else
            log_info "Port open, health green, but failed to get _cat/nodes. curl exit: $nodes_curl_exit_code, HTTP code: $nodes_http_code. Body (if any):"
            if [ -f "${nodes_body_file}" ]; then cat "${nodes_body_file}" || log_info "Could not cat nodes body file."; else echo "(No body from _cat/nodes)"; fi
          fi
          rm -f "${nodes_body_file}" # Clean up nodes temp file for this iteration
        else
          log_info "Port open, HTTP 200 for health, but status not green. jq exit: $?. Health API output:"
          cat "${health_body_file}" || log_info "Could not cat health body file."
        fi
      else
        log_info "Port open, but health check failed for custom Easysearch. curl exit: $health_curl_exit_code, HTTP code: $health_http_code. Body (if any):"
        if [ -f "${health_body_file}" ]; then cat "${health_body_file}" || log_info "Could not cat health body file."; else echo "(No body from health check)"; fi
      fi
    else
      log_info "Port ${PORT_TO_CHECK} on ${HOST_TO_CHECK} is not open yet for custom Easysearch."
    fi
    
    rm -f "${health_body_file}" # Clean up health temp file for this iteration

    log_info "Retrying custom Easysearch check in ${interval}s..."
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  # Final cleanup of temp files
  rm -f "${health_body_file}" "${nodes_body_file}"

  if ! $cluster_ready_and_nodes_verified; then cleanup_and_exit_failure "Custom Easysearch did not become healthy with correct node count within ${timeout_seconds}s"; fi
  
  log_info "Custom run successful. Cleaning up..."
  curl -fsSL "${SCRIPT_URL}" | bash -s -- clean
  if [ $? -ne 0 ]; then cleanup_and_exit_failure "Custom 'start-local.sh clean' command failed"; fi
  if [ -d "./startlocal" ]; then cleanup_and_exit_failure "Work dir ./startlocal still exists after clean!"; fi
  log_info "Custom run scenario completed successfully."

else
  log_error "Unknown scenario: ${SCENARIO_TO_RUN}"
  exit 1
fi