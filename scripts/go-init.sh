#!/bin/bash

export WORKBASE=$HOME/go/src
export WORK=$WORKBASE/infini.sh

echo "Home path is $HOME"
mkdir -p $WORKBASE
ln -s $GITHUB_WORKSPACE $WORK
echo "Build path is $WORK"
# update Makefile
cp -rf $WORK/products/framework/Makefile $WORK/framework

# --- Configure go environment ---
echo "🔧 Configuring Go environment..."
export GOEXPERIMENT=greenteagc
echo "export GOEXPERIMENT=greenteagc" >> $HOME/.bashrc
source $HOME/.bashrc