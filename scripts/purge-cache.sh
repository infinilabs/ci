#!/usr/bin/env bash

URL="${1:?Usage: $0 <url> [extra-header]}"
HEADER="${2:-x-reset-cache: true}"

IFS=',' read -ra NODE_IPS <<< "${RELEASE_IPS:?RELEASE_IPS env var is required}"

DOMAIN=$(echo "$URL" | awk -F[/:] '{print $4}')
[[ "$URL" == https* ]] && PORT="443" || PORT="80"

echo "=== Purging: $URL ==="
# Wait a bit to ensure the deployment is fully rolled out and the cache is warmed up
for i in $(seq 30); do
  printf '.'
  sleep 1
done
echo

PIDS=()
for IP in "${NODE_IPS[@]}"; do
  IP=$(echo "$IP" | tr -d ' ')
  MASKED=$(echo "$IP" | sed 's/\.[^.]*\.[^.]*$/.xxx.xxx/')
  curl --resolve "$DOMAIN:$PORT:$IP" \
    -o /dev/null \
    -w "  [%{http_code}] Node $MASKED\n" \
    -H "$HEADER" \
    "$URL" &
  PIDS+=($!)
done

for PID in "${PIDS[@]}"; do
  wait "$PID" || echo "  WARN: PID $PID failed, continuing..."
done

echo "=== Done ==="