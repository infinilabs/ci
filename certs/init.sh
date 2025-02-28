#!/bin/bash

# Workaround script to copy cert to container as described on: https://docs.docker.com/registry/insecure/
# Instruct every Docker daemon to trust that certificate. The way to do this depends on your OS.

CERTS_DIR=/etc/docker/certs.d/registry.infini.dev
LOCAL_CERT=/usr/local/share/ca-certificates/registry.infini.dev.crt
DEAMON_JSON=/etc/docker/daemon.json
mkdir -p $CERTS_DIR

cd $GITHUB_WORKSPACE/certs

sudo cp ca.crt $CERTS_DIR/ca.crt
sudo cp ca.crt $LOCAL_CERT
sudo update-ca-certificates

eval "cat <<EOF
$(cat daemon.json)
EOF" > $DEAMON_JSON
cat $DEAMON_JSON