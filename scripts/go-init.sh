#!/bin/bash

export WORKBASE=$HOME/go/src
export WORK=$WORKBASE/infini.sh
export GOEXPERIMENT=greenteagc

echo "Home path is $HOME"
mkdir -p $WORKBASE
ln -sf $GITHUB_WORKSPACE $WORK

echo "Build path is $WORK"

# update Makefile,if use legacy，EXT will be .legacy
EXT=$([[ "$*" == *legacy* ]] && echo ".legacy")
cp -rf "$WORK/products/framework/Makefile$EXT" "$WORK/framework/Makefile"

# --- Configure go environment ---
echo "🔧 Configuring Go environment..."
echo "PATH=$PATH:$GITHUB_WORKSPACE/tools" >> $GITHUB_ENV
echo "GOEXPERIMENT=$GOEXPERIMENT" >> $GITHUB_ENV
echo "WORKBASE=$WORKBASE" >> $GITHUB_ENV
echo "WORK=$WORK" >> $GITHUB_ENV