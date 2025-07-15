#!/bin/bash
# check if Easysearch is available on port 9200
# timeout after 300 seconds
# sleep for 5 seconds between checks
# if Easysearch is not available after 300 seconds, exit with error
# if Easysearch is available, sleep for 30 seconds to allow it to fully start
elapsed=0
interval=15
timeout=300
waiting=30
target="agent"

echo "Waiting for Easysearch on 127.0.0.1:9200..."

while ! nc -z 127.0.0.1 9200; do
  if [ $elapsed -ge $timeout ]; then
    echo "Timeout: Easysearch not available after ${timeout} seconds. Exiting."
    exit 1
  fi
  echo "Easysearch not ready, sleeping for ${interval}s..."
  sleep $interval
  elapsed=$((elapsed + interval))
done

# Wait for an additional period to ensure Easysearch is fully ready
sleep $waiting && echo "Wait $waiting secs for easysearch ready! Starting $target..."

# use exec to replace the bash process
# so that supervisor can manage the process directly
cd /app/easysearch/data/$target && exec ./$target