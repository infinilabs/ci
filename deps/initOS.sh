#!/bin/bash

FROM=almalinux;TO=infinios;YEAR=$(date +%Y);VENDOR="INFINI";OU="Labs"
date "+%Y%m%d_%H%M" > /etc/BUILDTIME
sed -i "s/$FROM/$TO/g" /etc/system-release-cpe

rm -rf /etc/$FROM-release
echo "$VENDOR OS release $YEAR ($VENDOR $OU)" > /etc/$TO-release
unlink /etc/system-release && ln -s /etc/$TO-release /etc/system-release
unlink /etc/redhat-release && ln -s /etc/$TO-release /etc/redhat-release

cat <<EOF > /etc/os-release
NAME="$VENDOR OS"
VERSION="$YEAR"
ID="$TO"
VERSION_ID="$YEAR"
PLATFORM_ID="platform:$TO"
PRETTY_NAME="$VENDOR OS release $YEAR ($VENDOR $OU)"
ANSI_COLOR="0;34"
EOF