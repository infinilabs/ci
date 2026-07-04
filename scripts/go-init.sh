#!/bin/bash

export WORKBASE=$HOME/go/src
export WORK=$WORKBASE/infini.sh
export GOEXPERIMENT=greenteagc

echo "Home path is $HOME"
mkdir -p $WORKBASE
ln -sf $GITHUB_WORKSPACE $WORK

echo "Build path is $WORK"

# update Makefile,if use legacy，EXT will be .legacy
if [[ "$*" == *legacy* ]] || [[ "$LEGACY_MODE" == "true" ]]; then
    EXT=".legacy"
else
    EXT=""
fi

MAKEFILE_PATH="$GITHUB_WORKSPACE/products/framework/Makefile$EXT"
if [ -f "$MAKEFILE_PATH" ]; then
    echo "Update with ci makefile: $MAKEFILE_PATH"
    cp -rf "$MAKEFILE_PATH" "$WORK/framework/Makefile"
else
    echo "Warning: $MAKEFILE_PATH not found, skipping"
fi

# --- Configure go environment ---
echo "🔧 Configuring Go environment..."
echo "PATH=$PATH:$GITHUB_WORKSPACE/tools" >> $GITHUB_ENV
echo "GOEXPERIMENT=$GOEXPERIMENT" >> $GITHUB_ENV
echo "WORKBASE=$WORKBASE" >> $GITHUB_ENV
echo "WORK=$WORK" >> $GITHUB_ENV