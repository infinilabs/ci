#!/bin/bash
set -e

# --- Global Variables and Helper Functions ---

# Function to log messages with timestamp and context, without container-specific terms
log() {
  local timestamp
  timestamp=$(date +"%Y-%m-%dT%H:%M:%S,%3N")
  echo "[$timestamp][INFO ][$(basename "$0")] $*"
}
# Define data directory
APP_DIR="/app/easysearch"
DATA_DIR="$APP_DIR/data"
LOGS_DIR="$APP_DIR/logs"
CFG_DIR="$APP_DIR/config"
AGENT_DIR="$DATA_DIR/agent"
AGENT_START_SCRIPT="$AGENT_DIR/start-agent.sh"
INGEST_CONFIG="$CFG_DIR/system_ingest_config.yml"
AGENT_SUPERVISOR_CONFIG="/etc/supervisor/conf.d/agent.conf"
# Define marker file path
INITIALIZED_MARKER="$DATA_DIR/.initialized"
AGENT_KEYSTORE_MARKER="$AGENT_DIR/.agent_keystore_initialized"
AGENT_SUPERVISOR_MARKER="$AGENT_DIR/.agent_supervisor_configured"

# Ensure data directory exists, even if mount is empty
log "Ensuring data directory exists: $DATA_DIR"
mkdir -p "$DATA_DIR"
if [ $? -ne 0 ]; then log "ERROR: Failed to create data directory."; exit 1; fi

# --- Function to perform the core initialization script execution ---
# This is the part that runs bin/initialize.sh -s
execute_core_initial_script() {
    log "Executing core initialization script: bin/initialize.sh -s"
    # Note: bin/initialize.sh must be designed to be idempotent or run only once for actual initialization logic
    gosu ezs bash bin/initialize.sh -s
    return $? # Return the exit status of the gosu command
}


# --- Function to perform initial setup (runs only once based on marker file) ---
# This function now incorporates the check for /app/easysearch/data being empty.
# This function is called only when the *primary* initialization marker is not found.
perform_initial_setup() {
  log "Initialization marker not found. Determining setup action..."

  # --- Check if the data directory is empty or not ---
  if [ -z "$(ls -A "$DATA_DIR")" ]; then # Use $DATA_DIR and quotes for safety
    log "$DATA_DIR directory is empty. Proceeding with core initialization script."
    execute_core_initial_script # Call the function to execute the script
    if [ $? -eq 0 ]; then
      log "Core initialization script completed successfully."
      # --- Create the initialization marker file after successful execution ---
      touch "$INITIALIZED_MARKER"
      log "Initialization marker created."
      return 0
    else
      # If core script fails when /data is empty
      log "ERROR: Core initialization script failed when $DATA_DIR was empty!"
      return 1
    fi
  else
    # The case where $DATA_DIR is not empty but the marker file is not found
    log "$DATA_DIR directory is NOT empty, but initialization marker was NOT found."
    log "WARNING: $DATA_DIR directory appears to contain data. Assuming initialization was performed previously and creating marker."
    touch "$INITIALIZED_MARKER"
    if [ $? -eq 0 ]; then
      log "Initialization marker created."
      return 0 # Indicate setup assumed complete, continue with the rest of the script
      # No need to exit 1 here, as we are assuming it's a valid state.
    else
       # If creating marker fails when /data is not empty
       log "ERROR: Failed to create initialization marker when $DATA_DIR was not empty! Entrypoint will exit."
       return 1
    fi
  fi
}

# --- Function to set up the agent (runs conditionally on each process start) ---
# This function is called when Agent is configured via environment variables.
setup_agent() {
  log "Agent setup process requested."

  # Ensure agent directory exists and has correct permissions (Consider if this should also be part of initial setup)
  # If agent files are part of the initial artifact, this check might be less critical on every start.
  # But checking ensures robustness if $DATA_DIR is cleared or agent files are missing.
  log "Checking agent directory: $AGENT_DIR"
  if [ ! -d "$AGENT_DIR" ]; then
    log "Agent directory not found. Copying agent files from /app/agent to $DATA_DIR."
    cp -rf /app/agent "$DATA_DIR"
    if [ $? -ne 0 ]; then log "ERROR: Failed to copy agent files."; return 1; fi
    log "Setting ownership of agent directory $AGENT_DIR to ezs:ezs."
    chown -R ezs:ezs "$AGENT_DIR"
     if [ $? -ne 0 ]; then log "ERROR: Failed to set ownership for agent directory."; return 1; fi
  fi

  # Check and create agent's data and config directories (agent's internal directories)
  log "Checking agent subdirectories data/config under $AGENT_DIR..."
  for dir in data config; do
    AGENT_SUBDIR="$AGENT_DIR/$dir"
    if [ ! -d "$AGENT_SUBDIR" ]; then
      log "Creating agent subdirectory: $AGENT_SUBDIR"
      mkdir -p "$AGENT_SUBDIR"
      if [ $? -ne 0 ]; then log "ERROR: Failed to create agent subdirectory '$AGENT_SUBDIR'."; return 1; fi
      log "Setting ownership of agent subdirectory $AGENT_SUBDIR to ezs:ezs."
      chown ezs:ezs "$AGENT_SUBDIR"
       if [ $? -ne 0 ]; then log "ERROR: Failed to set ownership for agent subdirectory '$AGENT_SUBDIR'."; return 1; fi
    fi
  done

  # Change to agent directory for subsequent commands that rely on relative paths
  log "Changing current directory to $AGENT_DIR."
  cd "$AGENT_DIR"
  if [ $? -ne 0 ]; then log "ERROR: Failed to change directory to $AGENT_DIR."; return 1; fi

  # Process METRICS_CONFIG_SERVER variable and update agent.yml
  log "Configuring agent based on METRICS_CONFIG_SERVER variable..."
  IFS=',' read -r -a servers <<< "$METRICS_CONFIG_SERVER"
  servers_yaml=""
  valid_servers=true
  for server in "${servers[@]}"; do
    if ! [[ "$server" =~ ^(http|https):// ]]; then
      log "ERROR: Invalid METRICS_CONFIG_SERVER '$server'. Must start with http:// or https://."
      valid_servers=false
      break
    fi
    servers_yaml+="- \"$server\""
    servers_yaml+=$'\n    '
  done

  if ! $valid_servers; then
    log "Agent configuration aborted due to invalid servers."
    return 1
  fi

  # Update servers list in agent.yml (relative to current directory $AGENT_DIR)
  log "Updating agent.yml servers list..."
  # Use sed carefully, consider quoting variables if they might contain special characters
  sed -i "/^configs:/, /soft_delete:/ {
    /^\s*-/d
    /servers:/a\\
    $servers_yaml
  }" agent.yml # agent.yml is relative to $AGENT_DIR
  if [ $? -ne 0 ]; then log "ERROR: Failed to update agent.yml servers list."; return 1; fi

  # --- Multi-tenant mode configuration ---
  if [ -n "${TENANT_ID}" ] && [ -n "${CLUSTER_ID}" ]; then
    
    log "Tenant ID and Cluster ID set. Applying multi-tenant agent configuration."
    if [ -z "${EASYSEARCH_INITIAL_AGENT_PASSWORD}" ]; then
      log "WARNING: EASYSEARCH_INITIAL_AGENT_PASSWORD is not set. Using default agent password 'infini_password'."
      EASYSEARCH_INITIAL_AGENT_PASSWORD="infini_password"
    fi

    log "Copying agent config templates."
    # Ensure /app/tpl exists and contains necessary files
    # Use absolute paths or ensure correct relative path from current directory ($AGENT_DIR)
    cp -rf /app/tpl/{*.yml,*.tpl} "$CFG_DIR" # Use quotes for safety
    if [ $? -ne 0 ]; then log "ERROR: Failed to copy agent config templates."; return 1; fi

    # Add node configuration if not present (agent.yml relative)
    log "Checking for existing node config in agent.yml."
    if ! grep -q "node:" agent.yml; then # agent.yml relative to $AGENT_DIR
      if [ -n "$ALLOW_GENERATED_METRICS_TASKS" ]; then
        GENERATED_METRICS_TASKS=true
        sed -i "s/managed:.*/managed: false/g" agent.yml
        log "Adding node configuration and disable remote config manage with agent.yml."
      else
        GENERATED_METRICS_TASKS=false
        sed -i "s/managed:.*/managed: true/g" agent.yml
        [ -e $INGEST_CONFIG ] && rm -rf $INGEST_CONFIG
        log "Adding node configuration and enable remote config manage with agent.yml."
      fi
      # Use <<-EOF for multi-line append to avoid issues with quotes/variables
      cat <<-EOF >> agent.yml
  always_register_after_restart: true
  allow_generated_metrics_tasks: $GENERATED_METRICS_TASKS
node:
  major_ip_pattern: ".*"
  labels:
    tenant_id: "$TENANT_ID"
    cluster_id: "$CLUSTER_ID"
EOF
      if [ $? -ne 0 ]; then log "ERROR: Failed to add node config to agent.yml."; return 1; fi
    fi
  
    # Initialize agent keystore and adjust yml/tpl files (runs only once based on marker)
    log "Checking agent keystore initialization marker."
    if [ ! -f "$AGENT_KEYSTORE_MARKER" ]; then
      log "Agent keystore initialization marker not found. Starting keystore setup."
      if [ -n "$EASYSEARCH_INITIAL_AGENT_PASSWORD" ] && [ -n "$EASYSEARCH_INITIAL_SYSTEM_ENDPOINT" ]; then
        # Execute agent commands relative to current directory ($AGENT_DIR)
        if [ -z "$(./agent keystore list | grep -Eo agent_user)" ]; then
          log "Adding agent_user to keystore."
          echo "infini_agent" | ./agent keystore add --stdin agent_user
          if [ $? -ne 0 ]; then log "ERROR: Failed to add agent_user to keystore."; return 1; fi
          log "Adding agent_passwd to keystore."
          echo "$EASYSEARCH_INITIAL_AGENT_PASSWORD" | ./agent keystore add --stdin agent_passwd > /dev/null
          if [ $? -ne 0 ]; then log "ERROR: Failed to add agent_passwd to keystore."; return 1; fi
        fi
        
        SCHEMA=$(echo "$EASYSEARCH_INITIAL_SYSTEM_ENDPOINT" |awk -F"://" '{print $1}')
        ADDRESS=$(echo "$EASYSEARCH_INITIAL_SYSTEM_ENDPOINT" |awk -F"://" '{print $2}')
        if [ -n "$SCHEMA" ] && [ -n "$ADDRESS" ] && [ -n "$ALLOW_GENERATED_METRICS_TASKS" ]; then
          log "Updating system ingest config based on endpoint."
          # Use sed carefully, ensure patterns match and replacements are correct
          # Using regex anchors ^ and $ to match the whole line for replacement is safer
          sed -i "s/^  schema: https$/  schema: $SCHEMA/;s/^  address: 127.0.0.1:9200$/  address: $ADDRESS/" "$INGEST_CONFIG"
          if [ $? -ne 0 ]; then log "ERROR: Failed to update ingest config schema/address."; return 1; fi

          sed -i "s/ingest/infini_ingest/;s/passwd/$EASYSEARCH_INITIAL_INGEST_PASSWORD/" "$INGEST_CONFIG"
          if [ $? -ne 0 ]; then log "ERROR: Failed to update ingest user/password."; return 1; fi

          sed -i -E 's/([-:]) metrics/\1 tenant-metrics/g' "$INGEST_CONFIG"
          if [ $? -ne 0 ]; then log "ERROR: Failed to update metrics queue in ingest config."; return 1; fi
        else
          [ -n "$ALLOW_GENERATED_METRICS_TASKS" ] && log "WARNING: EASYSEARCH_INITIAL_SYSTEM_ENDPOINT not in expected format 'schema://address'. Skipping ingest config update."
        fi
        
        # Create keystore initialized marker
        touch "$AGENT_KEYSTORE_MARKER"
        log "Agent keystore initialization complete."
      else
         log "WARNING: Required variables for agent keystore initialization (EASYSEARCH_INITIAL_AGENT_PASSWORD and EASYSEARCH_INITIAL_SYSTEM_ENDPOINT) are not fully set. Skipping keystore keystore setup."
      fi
    else
      log "Agent keystore initialization marker found. Skipping keystore setup."
    fi
  fi

  if [ ! -f "$AGENT_START_SCRIPT" ]; then
    log "Copying agent start script from /app/tpl/*.sh to $AGENT_DIR."
    cp -rf /app/tpl/*.sh "$AGENT_DIR"
  fi

  # Ensure agent directory is owned by ezs after all root operations
  log "Ensuring final agent directory ownership is ezs:ezs."
  # Use absolute path for robustness.
  chown -R ezs:ezs "$AGENT_DIR"
  if [ $? -ne 0 ]; then log "ERROR: Failed to set final ownership for agent directory."; return 1; fi

  # --- Supervisor configuration for the agent ---
  # This configures supervisor to manage the agent process.
  # This should also ideally happen only once or when the agent is intended to be managed.
  # Place it after all agent file/keystore setup.
  # Add a marker here if you want to control when this step runs (e.g., only if agent is enabled and setup succeeds)

  log "Checking agent supervisor config marker '$AGENT_SUPERVISOR_MARKER'."
  if [ ! -f "$AGENT_SUPERVISOR_MARKER" ]; then
     log "Agent supervisor config marker not found. Starting supervisor configuration."

     log "Setting up supervisor config for agent at $AGENT_SUPERVISOR_CONFIG."
     # Ensure supervisor directory exists
     mkdir -p /etc/supervisor/conf.d
     if [ $? -ne 0 ]; then log "ERROR: Failed to create supervisor config directory."; return 1; fi

     # Generate default supervisord config if it doesn't exist (only needed once globally for supervisor)
     if [ ! -f /etc/supervisor/supervisord.conf ]; then
       log "Supervisord main config /etc/supervisor/supervisord.conf not found. Generating default."
       echo_supervisord_conf > /etc/supervisor/supervisord.conf
       if [ $? -ne 0 ]; then log "ERROR: Failed to generate supervisord.conf."; return 1; fi
       # Enable includes in supervisord.conf
       sed -i 's|^;\(\[include\]\)|\1|; s|^;files.*|files = /etc/supervisor/conf.d/*.conf|' /etc/supervisor/supervisord.conf
       if [ $? -ne 0 ]; then log "ERROR: Failed to set up supervisord.conf includes."; return 1; fi
       log "Supervisord main config setup complete."
     fi
     
     # Copy agent supervisor config and start shell
     log "Copying agent supervisor config template to $AGENT_SUPERVISOR_CONFIG."
     cat /app/tpl/agent.conf > "$AGENT_SUPERVISOR_CONFIG"
     
     if [ $? -ne 0 ]; then log "ERROR: Failed to copy agent supervisor config."; return 1; fi
     log "Agent supervisor config created at $AGENT_SUPERVISOR_CONFIG."

     # Create the supervisor config marker
     touch "$AGENT_SUPERVISOR_MARKER"
     log "Agent supervisor configuration marked complete."
  else
    log "Agent supervisor config marker '$AGENT_SUPERVISOR_MARKER' found. Skipping supervisor configuration."
  fi

  log "Agent setup function complete."
  return 0 # Indicate agent setup function completed (not necessarily that agent process is running yet)
}


# --- Function to conditionally start Supervisor ---
# This function is called in the ezs user block if Agent was configured.
# It starts supervisord as the current user (ezs).
start_supervisor_if_agent_enabled() {
  log "Checking if Supervisor should be started based on Agent configuration."

  # Supervisor should be started if the agent supervisor config file exists (meaning agent setup ran successfully)
  if [ -f "$AGENT_SUPERVISOR_CONFIG" ]; then
      log "Agent supervisor config '$AGENT_SUPERVISOR_CONFIG' found. Supervisor is enabled to manage the agent."
      # Check if supervisord is already running as the current user (ezs)
      if ! supervisorctl status > /dev/null 2>&1; then
        log "Supervisord process not running. Starting supervisord..."
        # Need to start supervisord as ezs user. Its config /etc/supervisor/supervisord.conf must be readable by ezs.
        # The agent.conf should be readable by ezs.
        # The logs dir for supervisord should be writable by ezs.
        # Assuming necessary permissions are set by the Dockerfile or the root setup_agent phase.
        /usr/bin/supervisord -c /etc/supervisor/supervisord.conf &
        # Wait a moment for supervisord to start and read configs
        # log "Waiting 1 second for supervisord to start..." # Uncomment if needed
        sleep 1
        log "Supervisord process started (managing agent)."
      else
        log "Supervisord process appears to be running."
      fi
  else
    # Supervisor not enabled because agent setup did not complete successfully (config file not found)
    # Log the reason based on environment variables that control agent setup
    log "Agent supervisor config '$AGENT_SUPERVISOR_CONFIG' not found."
    # The specific reason (env var not set or setup failed) was logged in setup_agent or the root block.
    log "Supervisor startup skipped as Agent configuration was not completed."
  fi
}


# --- Trap signals for graceful shutdown ---
# This should be at the top level of the script.
trap "exit 0" SIGINT SIGTERM

# --- Main execution flow ---

# --- Initial Setup (runs only once based on marker file and data empty check) ---
# This block combines the marker check and the data empty check.
log "Checking for initial setup marker."
if [ ! -f "$INITIALIZED_MARKER" ]; then
  # If marker not found, determine if it's a clean start or non-clean start
  log "Initialization marker not found."
  
  if [ -z "$(ls -A "$DATA_DIR")" ]; then
    log "$DATA_DIR directory is empty. Proceeding with initial setup process."
    perform_initial_setup # Call the initial setup function which executes core script and creates marker
    if [ $? -ne 0 ]; then
      log "Initial setup function failed. Entrypoint will exit."
      exit 1
    fi
  else
    log "$DATA_DIR directory is NOT empty, but initialization marker was NOT found."
    # In this non-clean start scenario, assume initialization was done previously and create the marker.
    # This prevents re-running the core script if data already exists.
    log "WARNING: $DATA_DIR directory appears to contain data. Assuming initialization was performed previously and creating marker."
    touch "$INITIALIZED_MARKER"
    if [ $? -eq 0 ]; then
      log "Initialization marker created."
      # Continue with the rest of the script, assuming setup is complete.
    else
       log "ERROR: Failed to create initialization marker when $DATA_DIR was not empty! Entrypoint will exit."
       exit 1
    fi
  fi
else
  # If marker is found, skip the entire initial setup process.
  log "Initialization marker found. Skipping initial setup."
fi


# --- Switch to non-root user if running as root ---
# This block remains as is, it ensures the rest of the script runs as 'ezs' user
if [ "$(id -u)" = '0' ]; then
  # Ensure the data directory has the correct ownership before switching user
  log "Running as root. Checking $DATA_DIR directory ownership."
  # Check if ownership needs changing before attempting
  if [ "$(stat -c %U "$DATA_DIR")" != "ezs" ] || [ "$(stat -c %G "$DATA_DIR")" != "ezs" ]; then # Check both user and group
    log "Changing ownership of $DATA_DIR to ezs:ezs."
    chown -R ezs:ezs "$DATA_DIR" "$LOGS_DIR" "$CFG_DIR"
    if [ $? -ne 0 ]; then log "ERROR: Failed to change ownership of $DATA_DIR."; exit 1; fi
  fi
  
  # Conditionally setup the agent *before* switching user (as it needs root for supervisor config)
  if [ "${METRICS_WITH_AGENT}" == "true"  ] && [ -n "${METRICS_CONFIG_SERVER}" ]; then
    log "Agent setup requested based on environment variables."
    setup_agent
    if [ $? -eq 0 ]; then
      log "Agent setup function completed successfully."
    else
      log "Agent setup function failed. Entrypoint will exit."
      exit 1
    fi
  else
    log "METRICS_WITH_AGENT is 'false' or METRICS_CONFIG_SERVER is empty. Agent setup skipped."
  fi

  # After initial setup and agent setup, we can start the supervisor if needed
  # This is done after the agent setup to ensure the config files are in place
  # and the agent process can be managed by supervisord.
  # This should be called after the agent setup and before switching to the 'ezs' user.
  # Supervisor startup requires root permissions.
  start_supervisor_if_agent_enabled

  log "Switching user to 'ezs' and executing the rest of the entrypoint..."
  # Re-execute the entrypoint script as the 'ezs' user
  exec gosu ezs "$0" "$@"
fi

# --- Code below this line runs as the 'ezs' user ---

# This is the main process flow for the 'ezs' user.

# --- Execute the main command passed to the process ---
# This is typically the command to start the main EasySearch process.
log "Executing main process command: $@"
exec "$@"