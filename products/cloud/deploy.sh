#!/bin/bash

# Script to update an application.
# Supports remote download or local file update.
# Manages backups of the previous executable.
# Optionally controls a service (stop/start).

# Strict mode helps catch common errors
set -uo pipefail # -u: treat unset variables as error, -o pipefail: pipe fails if any cmd fails
# set -e # Exit immediately if a command exits with a non-zero status.
         # Consider enabling 'set -e' after thorough testing if strict exit-on-error is desired.
         # For now, error handling is done with explicit checks.

# --- Script Configuration ---
PNAME="${PNAME:-cloud}"                                # Product name (can be overridden by env var)
APP_EXECUTABLE_NAME="${PNAME}-linux-amd64"             # Name of the application executable

# Default paths and URLs (can be overridden by env vars or logic below)
DEFAULT_WORK_PATH="/nvme/dev/$PNAME"                   # Default base for WORK_PATH
DEFAULT_RELEASE_URL=""                                 # Default base URL for releases

# These are relative to WORK_PATH or absolute if overridden
UPDATE_DIR_NAME="update"                               # Subdirectory for download/extraction within WORK_PATH
DEFAULT_APP_VERSION="0.3.1-2028"                       # Default application version for local reference
MAX_BACKUPS=3                                          # Number of recent backups to keep
DEFAULT_SERVICE_NAME="infini-cloud-server"               # Default: no specific service name to control

# --- Initialize variables from environment or use defaults ---
WORK_PATH="${WORK_PATH:-$DEFAULT_WORK_PATH}"
RELEASE_URL="${RELEASE_URL:-$DEFAULT_RELEASE_URL}"
BASE_URL="$RELEASE_URL/$PNAME"
SERVICE_NAME_TO_CONTROL="${SERVICE_NAME_TO_CONTROL:-$DEFAULT_SERVICE_NAME}"

# --- Flags and Variables from CLI parsing ---
TARGET_VERSION=""                       # Final version to be used/downloaded
REMOTE_UPDATE_FLAG=false                # Flag for remote update
VERSION_EXPLICITLY_PROVIDED=false       # Track if -v or a version with -r was given
IS_NIGHTLY_BUILD=false                  # Track if the target version is a nightly build

# --- Logging Functions ---
SCRIPT_BASENAME=$(basename "$0")
log_info() { echo "[INFO] [$SCRIPT_BASENAME] $(date +'%Y-%m-%d %H:%M:%S %Z') - $1"; }
log_warn() { echo "[WARN] [$SCRIPT_BASENAME] $(date +'%Y-%m-%d %H:%M:%S %Z') - $1" >&2; }
log_error() { echo "[ERROR] [$SCRIPT_BASENAME] $(date +'%Y-%m-%d %H:%M:%S %Z') - $1" >&2; }
# --- End Logging Functions ---

# --- Helper: Print Usage ---
print_usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "Updates the $PNAME application."
    echo ""
    echo "Options:"
    echo "  -r, --remote [NIGHTLY_TAG]    Enable remote update."
    echo "                                If NIGHTLY_TAG is provided (e.g., \"dev\"), version becomes <TAG>_NIGHTLY-YYYYMMDD."
    echo "                                If no tag, version becomes NIGHTLY-YYYYMMDD."
    echo "                                This is overridden by -v/--version if both are used."
    echo ""
    echo "  -v, --version <VERSION>     Specify a specific release version to download and install (if -r)"
    echo "                                or use as reference for local update."
    echo ""
    echo "  -s, --service-name <NAME>   Specify the service name to stop/start (optional)."
    echo "                                If not provided, stop/start commands run without SERVICE_NAME env var."
    echo ""
    echo "  -h, --help                  Show this help message and exit."
    echo ""
    echo "Environment Variables for Configuration (can override script defaults):"
    echo "  PNAME                     (Default: $PNAME)"
    echo "  WORK_PATH                 (Default: $WORK_PATH)"
    echo "  RELEASE_URL               (Default: $RELEASE_URL)"
    echo "  SERVICE_NAME_TO_CONTROL   (Default: \"$DEFAULT_SERVICE_NAME\" meaning generic stop/start)"
    exit 0
}
# --- End Helper: Print Usage ---

# --- Parse Command-line Arguments ---
# This parsing logic attempts to be flexible.
# -v takes precedence for TARGET_VERSION.
# -r enables remote and sets nightly defaults if -v is not also used.

_cli_version_opt_val="" # Store value from -v option
_cli_remote_tag_opt_val="" # Store value from -r <tag>

while [ "$#" -gt 0 ]; do
    case "$1" in
        -r|--remote)
            REMOTE_UPDATE_FLAG=true
            # Check if next arg is a tag for nightly (not an option itself)
            if [[ -n "$2" && "$2" != --* && "$2" != -* ]]; then
                _cli_remote_tag_opt_val="$2"
                shift # Consume the tag
            fi
            shift # Consume -r or --remote
            ;;
        -v|--version)
            if [[ -n "$2" && "$2" != --* && "$2" != -* ]]; then
                _cli_version_opt_val="$2"
                shift 2 # Consume -v and its argument
            else
                log_error "$1 requires a version number."
                print_usage # Exits via trap
                exit 1      # Explicit exit
            fi
            ;;
        -s|--service-name)
            if [[ -n "$2" && "$2" != --* && "$2" != -* ]]; then
                SERVICE_NAME_TO_CONTROL="$2"
                shift 2
            else
                log_error "$1 requires a service name."
                print_usage; exit 1;
            fi
            ;;
        -h|--help)
            print_usage # Exits
            ;;
        *)
            log_warn "Unknown option or unexpected argument: $1. Ignoring."
            shift # Shift to avoid infinite loop on unknown options.
            ;;
    esac
done

# --- Determine Final TARGET_VERSION and IS_NIGHTLY_BUILD ---
if [ -n "$_cli_version_opt_val" ]; then
    TARGET_VERSION="$_cli_version_opt_val"
    IS_NIGHTLY_BUILD=false # Explicit version is a release
    VERSION_EXPLICITLY_PROVIDED=true
    log_info "Using specific version from --version/-v: $TARGET_VERSION"
elif [ "$REMOTE_UPDATE_FLAG" = true ]; then
    if [ -n "$_cli_remote_tag_opt_val" ]; then
        TARGET_VERSION="${_cli_remote_tag_opt_val}_NIGHTLY-$(date +%Y%m%d)"
    else # -r was specified alone
        TARGET_VERSION="NIGHTLY-$(date +%Y%m%d)"
    fi
    IS_NIGHTLY_BUILD=true
    VERSION_EXPLICITLY_PROVIDED=true
    log_info "Using nightly version for --remote: $TARGET_VERSION"
else # Local update, no -v specified
    TARGET_VERSION="$DEFAULT_APP_VERSION" # Use default for reference or if needed by local logic
    IS_NIGHTLY_BUILD=false
    VERSION_EXPLICITLY_PROVIDED=false # Not explicitly provided for download target
    log_info "Local update mode. Version for reference: $TARGET_VERSION. Will use files in '$UPDATE_DIR_NAME'."
fi

# Final check if a version was determined, critical for remote updates
if [ "$REMOTE_UPDATE_FLAG" = true ] && [ -z "$TARGET_VERSION" ]; then
    log_error "Remote update selected, but target version could not be determined."
    print_usage; exit 1;
fi
# --- End Version Determination ---


# --- Update Function ---
update_application() {
    log_info "--- Starting Application Update Process ---"
    if [ -n "$TARGET_VERSION" ]; then log_info "Application Target Version: $TARGET_VERSION"; fi
    log_info "Remote Update: $REMOTE_UPDATE_FLAG"
    if [ "$REMOTE_UPDATE_FLAG" = true ]; then log_info "Build Type: $(if $IS_NIGHTLY_BUILD; then echo "Nightly"; else echo "Release"; fi)"; fi
    if [ -n "$SERVICE_NAME_TO_CONTROL" ]; then log_info "Service Name to Control: $SERVICE_NAME_TO_CONTROL"; else log_info "Service Control: Generic (no specific service name)"; fi

    log_info "Ensuring working directory: $WORK_PATH"
    if ! mkdir -p "$WORK_PATH"; then
        log_error "Failed to create working directory '$WORK_PATH'. Aborting."
        exit 1
    fi
    if ! cd "$WORK_PATH"; then
        log_error "Could not change to directory '$WORK_PATH'. Aborting."
        exit 1
    fi

    local current_update_dir_path="./$UPDATE_DIR_NAME" # Relative to WORK_PATH
    local downloaded_package_archive_path="" # Full path to downloaded package if remote

    # --- Download and Extract (if remote update) ---
    if [ "$REMOTE_UPDATE_FLAG" = true ]; then
        local package_basename="${PNAME}-${TARGET_VERSION}-linux-amd64.tar.gz"
        downloaded_package_archive_path="${current_update_dir_path}/${package_basename}"

        local download_url_path_segment=$([ "$IS_NIGHTLY_BUILD" = true ] && echo "snapshot" || echo "stable")
        local download_url="$BASE_URL/$download_url_path_segment/$package_basename"

        log_info "Ensuring update directory '$current_update_dir_path' exists and is clean for download..."
        if ! rm -rf "$current_update_dir_path"; then log_error "Failed to clean $current_update_dir_path"; exit 1; fi
        if ! mkdir -p "$current_update_dir_path"; then log_error "Failed to create $current_update_dir_path"; exit 1; fi

        log_info "Downloading from: $download_url to $downloaded_package_archive_path ..."
        if ! wget -qN "$download_url" -O "$downloaded_package_archive_path"; then
            log_error "Failed to download package '$package_basename'."
            exit 1
        fi
        log_info "Download complete: $downloaded_package_archive_path"

        log_info "Extracting '$APP_EXECUTABLE_NAME' from '$downloaded_package_archive_path' into '$current_update_dir_path'..."
        # Assuming APP_EXECUTABLE_NAME is at the root of the tarball. Adjust if it's in a subdirectory.
        # Use --strip-components=1 if tarball has a single top-level dir containing the executable.
        if ! tar -zxvf "$downloaded_package_archive_path" -C "$current_update_dir_path/" "$APP_EXECUTABLE_NAME"; then
            log_error "Failed to extract '$APP_EXECUTABLE_NAME'. Check tarball structure and content."
            rm -f "$downloaded_package_archive_path" # Clean up download
            exit 1
        fi
        log_info "Extraction successful."

        log_info "Cleaning up downloaded archive: $downloaded_package_archive_path"
        rm -f "$downloaded_package_archive_path"
    else # Local update
        log_info "Local update. Using files from '$current_update_dir_path/'."
        if [ ! -d "$current_update_dir_path" ] || [ ! -f "$current_update_dir_path/$APP_EXECUTABLE_NAME" ]; then
            log_error "Local update mode, but '$current_update_dir_path/$APP_EXECUTABLE_NAME' not found."
            log_error "Please place the new application files in '$current_update_dir_path/'."
            exit 1
        fi
    fi

    # --- Service Control, Backup, Replace ---
    local current_executable_on_disk="./$APP_EXECUTABLE_NAME" # Relative to WORK_PATH
    local new_executable_in_update_dir="$current_update_dir_path/$APP_EXECUTABLE_NAME"
    local backup_file_created_this_run=""
    local service_control_cmd_prefix=""

    if [ -n "$SERVICE_NAME_TO_CONTROL" ]; then
        service_control_cmd_prefix="SERVICE_NAME=\"$SERVICE_NAME_TO_CONTROL\""
    fi

    # Stop service
    if [ -f "$current_executable_on_disk" ]; then
        log_info "Stopping service $([ -n "$SERVICE_NAME_TO_CONTROL" ] && echo "'$SERVICE_NAME_TO_CONTROL' ")(using '$current_executable_on_disk')..."
        # Use eval to correctly handle empty service_control_cmd_prefix
        if ! eval "$service_control_cmd_prefix \"$current_executable_on_disk\" -service stop"; then
            log_warn "Stop command failed or service was not running."
        else
            log_info "Stop command issued. Waiting a few seconds..."
            sleep 3
        fi
    else
        log_info "Current executable '$current_executable_on_disk' not found. Assuming new installation, skipping stop."
    fi

    # Backup current executable
    if [ -f "$current_executable_on_disk" ]; then
        if ! cmp -s "$current_executable_on_disk" "$new_executable_in_update_dir"; then
            timestamp_str=$(date +%Y%m%d%H%M%S)
            backup_file_created_this_run="${APP_EXECUTABLE_NAME}_${timestamp_str}.bak"
            log_info "Backing up current '$APP_EXECUTABLE_NAME' to '$backup_file_created_this_run'..."
            if ! cp -p "$current_executable_on_disk" "$backup_file_created_this_run"; then
                log_warn "Failed to back up '$current_executable_on_disk'."
                backup_file_created_this_run="" # Clear if backup failed
            else
                # Manage number of backups
                ls -1t "${APP_EXECUTABLE_NAME}_"*.bak 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while IFS= read -r old_backup; do
                    if [ -n "$old_backup" ]; then log_info "Deleting old backup: $old_backup"; rm -f "$old_backup"; fi
                done
            fi
        else
            log_info "New executable is identical to current one. No backup needed for this file."
        fi
    fi

    # Replace executable
    log_info "Moving '$new_executable_in_update_dir' to '$current_executable_on_disk'..."
    if ! mv "$new_executable_in_update_dir" "$current_executable_on_disk"; then
        log_error "Failed to move new executable into place."
        # Attempt to restart original service if it was running and we have a path to it
        if [ -f "$current_executable_on_disk" ]; then
            log_info "Attempting to restart original/current service..."
            eval "$service_control_cmd_prefix \"$current_executable_on_disk\" -service start" || \
                log_warn "Failed to restart service after move failure."
        fi
        exit 1
    fi
    if ! chmod +x "$current_executable_on_disk"; then
        log_error "Failed to set execute permission on '$current_executable_on_disk'."
        # This is critical, attempt rollback if backup exists
         if [ -n "$backup_file_created_this_run" ] && [ -f "$backup_file_created_this_run" ]; then
            log_warn "Attempting to restore from backup '$backup_file_created_this_run' due to permission error..."
            cp -p "$backup_file_created_this_run" "$current_executable_on_disk" # Ignoring cp error here for simplicity
        fi
        exit 1
    fi
    log_info "Executable updated and permissions set."

    # Start service
    log_info "Starting service $([ -n "$SERVICE_NAME_TO_CONTROL" ] && echo "'$SERVICE_NAME_TO_CONTROL' ")(using '$current_executable_on_disk')..."
    if ! eval "$service_control_cmd_prefix \"$current_executable_on_disk\" -service start"; then
        log_error "Failed to start service with the new version."
        if [ -n "$backup_file_created_this_run" ] && [ -f "$backup_file_created_this_run" ]; then
            log_warn "Attempting to restore from backup '$backup_file_created_this_run' and start..."
            if cp -p "$backup_file_created_this_run" "$current_executable_on_disk" && \
               chmod +x "$current_executable_on_disk" && \
               eval "$service_control_cmd_prefix \"$current_executable_on_disk\" -service start"; then
                log_info "Service restored and started from backup '$backup_file_created_this_run'."
                log_error "Update to version '$TARGET_VERSION' FAILED and was rolled back."
            else
                log_error "Failed to restore or start service from backup. Service may be down."
            fi
        else
            log_error "No backup from this run available to restore. Service may be down."
        fi
        exit 1
    fi
    log_info "Service started. Waiting a few seconds for initialization..."
    sleep 3

    # Clean up update directory (contents)
    if [ -d "$current_update_dir_path" ]; then
        log_info "Cleaning up contents of '$current_update_dir_path'..."
        if [ -n "$UPDATE_DIR_NAME" ] && [ "$UPDATE_DIR_NAME" != "." ] && [ "$UPDATE_DIR_NAME" != "/" ]; then
            # Check if directory is empty before attempting to remove its contents with wildcard
            if [ -n "$(ls -A "$current_update_dir_path" 2>/dev/null)" ]; then
                rm -rf "${current_update_dir_path:?}/"*
            else
                log_info "Update directory '$current_update_dir_path' is already empty."
            fi
        else
            log_warn "UPDATE_DIR_NAME is empty or invalid ('$UPDATE_DIR_NAME'), skipping contents cleanup."
        fi
    fi

    # View logs
    if [ "$REMOTE_UPDATE_FLAG" = true ]; then # Only for remote updates for now
      log_info "Viewing service log (last 200 lines)..."
      # Construct log path relative to WORK_PATH
      local log_file_path_to_tail_specific="${LOG_DIR_FOR_TAIL}/${PNAME}.log" # Needs LOG_DIR_FOR_TAIL to be relative to WORK_PATH
      
      if [ -f "$log_file_path_to_tail_specific" ]; then
          tail -200 "$log_file_path_to_tail_specific"
      else
          log_warn "Specific log file '$log_file_path_to_tail_specific' not found."
          # Fallback to a more general pattern if the specific one is not found
          local log_file_pattern_fallback="log/${PNAME}/nodes/*/${PNAME}.log" # This is relative to WORK_PATH
          if compgen -G "$log_file_pattern_fallback" > /dev/null; then
              log_info "Found logs with fallback pattern: $log_file_pattern_fallback"
              tail -200 $log_file_pattern_fallback
          else
              log_warn "No logs found with fallback pattern either in $WORK_PATH."
          fi
      fi
    fi
    log_info "--- Update process finished successfully for version '$TARGET_VERSION' ---"
}
# --- End Update Function ---


# --- Main Script Execution ---
# Check dependencies (optional, can be added for production scripts)
# check_dependencies

if [ -z "$RELEASE_URL" ] && [ "$REMOTE_UPDATE_FLAG" = true ]; then
    log_warn "RELEASE_URL environment variable is not set. Remote updates might fail if BASE_URL relies on it (current BASE_URL: $BASE_URL)."
fi

log_info "Selected Product: $PNAME"
# TARGET_VERSION is determined after parsing args

update_application

exit 0 # Explicitly exit with 0 on success