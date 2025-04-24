#!/bin/bash

export WORKBASE=$HOME/go/src
export WORK=$WORKBASE/infini.sh

echo "Home path is $HOME"
mkdir -p $WORKBASE
ln -s $GITHUB_WORKSPACE $WORK
echo "Build path is $WORK"