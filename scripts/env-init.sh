#!/bin/bash

# ==============================================================================
#  CI Environment Initialization Script
#
#  This script is designed to be SOURCED in a CI/CD environment.
#  It sets up tools, SSH keys, network configs, and robust HTTP clients.
# ==============================================================================

# --- Helper Functions for Logging ---
# Using functions for logging makes the script cleaner and easier to read.
log_info() {
    echo -e "ℹ️  $1"
}

log_success() {
    echo -e "✅  $1"
}

log_warn() {
    echo -e "⚠️  $1"
}

log_error() {
    echo -e "❌  $1" >&2
}

# --- One-Time Initialization Function ---
# This function contains setup logic that runs once when the script is sourced.

env_init() {
    log_info "🚀 Starting one-time environment initialization..."
    
    log_info "🌳 Setting up git config..."
    git config --global fetch.progress false
    git config --global user.name "GitHub Actions"
    git config --global user.email "ci@github.com"
    log_success "Git configuration is set."

    # --- Configure .curlrc and .wgetrc ---
    log_info "🔧 Configuring robust defaults for curl and wget..."
    
    # For curl
    cat <<-EOF | sed 's/^[ \t]*//' >> ~/.curlrc
		# Automatically added by CI init script
		location
		fail
		retry = 3
		retry-delay = 5
		connect-timeout = 15
		max-time = 90
		insecure
		silent
	EOF

    # For wget
    cat <<-EOF | sed 's/^[ \t]*//' >> ~/.wgetrc
		# Automatically added by CI init script
		check_certificate = off
		connect-timeout = 15
		read-timeout = 60
		tries = 3
		retry-connrefused = on
		waitretry = 5
		quiet = on
        timestamping = on
	EOF
    log_success "Global HTTP client settings configured."


    # --- Install Tools ---
    if [[ "$SHELL" == "/bin/bash" ]]; then
        log_info "🛠️  Setting up custom tools..."
        # Use -n to check if the directory is not empty to avoid errors
        if [ -n "$(find "$GITHUB_WORKSPACE/tools" -mindepth 1 -maxdepth 1)" ]; then
            sudo cp -rf "$GITHUB_WORKSPACE"/tools/* /usr/bin/ 2>/dev/null
			sudo chmod +x /usr/bin/* 2>/dev/null
            log_success "Custom tools installed."
        else
            log_info "No custom tools found to install."
        fi
    fi

    # --- Configure SSH ---
    # Use -n to check if the variable is not empty, which is more robust
    if [[ -n "$SSH_PRIVATE_KEY" ]]; then
        log_info "🔑  Configuring SSH key and settings..."
        # Determine SSH directory more safely
        local SSH_DIR
        if [ "$(id -u)" -eq 0 ]; then
            SSH_DIR="/root/.ssh"
        else
            SSH_DIR="$HOME/.ssh"
        fi

        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        echo "$SSH_PRIVATE_KEY" > "$SSH_DIR/id_rsa"
        
        # Initialize config file and add common settings
        cat > "$SSH_DIR/config" <<-EOF
			ConnectTimeout 600
			ServerAliveInterval 300
			ServerAliveCountMax 10
		EOF

        # Append user-provided config if it exists
        if [[ -n "$SSH_CONFIG" ]]; then
            echo -e "\n# User-provided SSH config\n$SSH_CONFIG" >> "$SSH_DIR/config"
        fi
        
        chmod 600 "$SSH_DIR"/id_rsa "$SSH_DIR"/config
        log_success "SSH configuration is complete."
    fi

    # --- Configure Network (Connect Config) ---
    if [[ -n "$LOCAL_PORT" ]]; then
        log_info "🌐  Generating network configuration file..."
        # Using a temporary variable for clarity
        local net_config
        net_config=$(cat <<-EOF
			{
			  "local_port": $LOCAL_PORT,
			  "local_address": "${LOCAL_HOST:-127.0.0.1}",
			  "servers": [
			    {
			      "server": "$CONNECT_SERVER",
			      "server_port": $CONNECT_PORT,
			      "password": "$CONNECT_KEY",
			      "timeout": $CONNECT_TIMEOUT,
			      "mode": "$CONNECT_MODE",
			      "method": "$CONNECT_METHOD"
			    }
			  ]
			}
		EOF
        )
        echo "$net_config" > "$GITHUB_WORKSPACE/.net.json"
        log_success "Network config (.net.json) created."
    fi

    # --- Configure OSS ---
    if [[ -n "$OSS_EP" ]]; then
        log_info "📦  Generating OSS configuration file..."
        cat > "$GITHUB_WORKSPACE/.oss.yml" <<-EOF
		oss:
		  endpoint: $OSS_EP
		  accesskeyid: $OSS_AK
		  accesskeysecret: $OSS_SK
		  bucket: $OSS_BK
          upload_mode: $OSS_MODE
		loglevel: "error"
		EOF
        log_success "OSS config (.oss.yml) created."
    fi

    # --- Configure Gradle ---
    if [[ -n "$GRADLE_VERSION" ]]; then
        log_info "🐘  Configuring Gradle settings..."
        local GRADLE_DIR
        if [ "$(id -u)" -eq 0 ]; then
            GRADLE_DIR="/root/.gradle"
        else
            GRADLE_DIR="$HOME/.gradle"
        fi

        mkdir -p "$GRADLE_DIR"
        # Copy only if source files exist
        if [ -d "$GITHUB_WORKSPACE/products/$PNAME/gradle/" ]; then
            cp -f "$GITHUB_WORKSPACE/products/$PNAME/gradle/"* "$GRADLE_DIR/"
            log_success "Gradle settings copied."
        else
            log_warn "Gradle config directory not found for product $PNAME."
        fi
    fi

    if [[ -n "$PROXY_RELEASE_INFINILABS" ]]; then
        log_info "🌍  Setting up etc hosts for infinilabs release..."
        echo "$PROXY_RELEASE_INFINILABS" | sudo tee -a /etc/hosts > /dev/null
        log_success "Added custom host entry."
    fi

    echo ""
    log_success "🎉 Environment initialization finished successfully!"
}

# ==============================================================================
#  EXECUTION TRIGGER
#  Run the initialization function when this script is sourced.
# ==============================================================================
env_init