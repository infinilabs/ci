#!/bin/bash

LOCAL_ADDRE="127.0.0.1"

# for tools
cp -rf $GITHUB_WORKSPACE/tools/* /usr/bin && echo "Tools setting done."

# for ssh
if [[ ! -z "$SSH_PRIVATE_KEY" ]]; then
  for x in "$HOME" /root; do
    mkdir -p $x/.ssh
    echo "$SSH_PRIVATE_KEY" > $x/.ssh/id_rsa
    if [[ ! -z "$SSH_CONFIG" ]]; then
      echo "$SSH_CONFIG" >> $x/.ssh/config
    fi
    chmod 600 $x/.ssh/{id_rsa,config}
  done
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
  for x in "$HOME" /root; do
    mkdir -p $x/.gradle
    cp $GITHUB_WORKSPACE/products/$PNAME/gradle/* $x/.gradle
  done
  echo "Gradle config setting done."
fi