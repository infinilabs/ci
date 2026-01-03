#!/bin/bash

export WORKBASE=$HOME/go/src
export WORK=$WORKBASE/infini.sh
export GOEXPERIMENT=greenteagc

echo "Home path is $HOME"
mkdir -p $WORKBASE
ln -s $GITHUB_WORKSPACE $WORK
echo "Build path is $WORK"
# update Makefile
cp -rf $WORK/products/framework/Makefile $WORK/framework

# --- Configure go environment ---
echo "🔧 Configuring Go environment..."
echo "GOEXPERIMENT=$GOEXPERIMENT" >> $GITHUB_ENV