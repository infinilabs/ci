#!/bin/bash

LOCAL_ADDRE="127.0.0.1"

# for tools
sudo cp -rf $GITHUB_WORKSPACE/tools/* /usr/bin && echo "Tools setting done."

# for ssh
if [[ ! -z "$SSH_PRIVATE_KEY" ]]; then
	if [ "$(id -u)" -eq 0 ]; then
		SSH_DIR="/root/.ssh"
	else
		SSH_DIR="$HOME/.ssh"
	fi

	mkdir -p $SSH_DIR
	echo "$SSH_PRIVATE_KEY" > $SSH_DIR/id_rsa
	if [[ ! -z "$SSH_CONFIG" ]]; then
	 	echo "ConnectTimeout 60" >> $SSH_DIR/config
		echo "ServerAliveInterval 30" >> $SSH_DIR/config
		echo "ServerAliveCountMax 3" >> $SSH_DIR/config
		echo "$SSH_CONFIG" >> $SSH_DIR/config
	fi
	chmod 600 $SSH_DIR/{id_rsa,config}
	echo "SSH config setting done."
fi

# for proxy
if [[ ! -z "$LOCAL_PORT" ]]; then
  cat <<-EOF > "$GITHUB_WORKSPACE/.oss.json"
	{
	  "local_port": $LOCAL_PORT,
	  "local_address": "$LOCAL_ADDRE",
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
  echo "Connect config setting done."
fi

# for oss
if [[ ! -z "$OSS_EP" ]]; then
  cat <<-EOF > "$GITHUB_WORKSPACE/.oss.yml"
	endpoint: $OSS_EP
	accesskeyid: $OSS_AK
	accesskeysecret: $OSS_SK
	bucket: $OSS_BK
	mode: $OSS_MODE
	EOF
  echo "OSS config setting done."
fi

# for gradle
if [[ ! -z "$GRADLE_VERSION" ]]; then
	if [ "$(id -u)" -eq 0 ]; then
		GRADLE_DIR="/root/.gradle"
	else
		GRADLE_DIR="$HOME/.gradle"
	fi

	mkdir -p "$GRADLE_DIR"
	cp "$GITHUB_WORKSPACE/products/$PNAME/gradle/"* "$GRADLE_DIR"
	echo "Gradle config setting done."
fi