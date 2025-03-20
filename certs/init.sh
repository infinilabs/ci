#!/bin/bash

# Workaround script to copy cert to container as described on: https://docs.docker.com/registry/insecure/
# Instruct every Docker daemon to trust that certificate. The way to do this depends on your OS.

CERTS_DIR=/etc/docker/certs.d/registry.infini.dev
LOCAL_DIR=/usr/local/share/ca-certificates
LOCAL_CERT=$LOCAL_DIR/registry.infini.dev.crt
DEAMON_JSON=/etc/docker/daemon.json

cd $GITHUB_WORKSPACE/certs
sudo mkdir -p $CERTS_DIR && sudo mkdir -p $LOCAL_DIR && sudo mkdir -p /etc/docker

sudo cp $GITHUB_WORKSPACE/certs/ca.crt $CERTS_DIR/ca.crt
sudo cp $GITHUB_WORKSPACE/certs/ca.crt $LOCAL_CERT
sudo update-ca-certificates

eval "cat <<EOF
$(cat daemon.json)
EOF" > /tmp/daemon.json
sudo cp /tmp/daemon.json $DEAMON_JSON