#!/bin/bash

PNAME="coco-website"
WORK="/opt/$PNAME"
EXT="zip"

if [[ ! -d "$WORK" ]]; then
  echo "Creating directory $WORK"
  mkdir -p "$WORK" || {
    echo "Failed to create directory $WORK"
    exit 1
  }
fi

ls -lh "$WORK.$EXT" || true
unzip -qo "$WORK.$EXT" -d "$WORK" || {
  echo "Failed to unzip $WORK.$EXT"
  exit 1
}

chown -RLf www-data:www-data "$WORK" || {
  echo "Failed to change ownership of $WORK"
  exit 1
}

rm -rvf "$WORK.$EXT" || {
  echo "Failed to remove $WORK.$EXT"
  exit 1
}