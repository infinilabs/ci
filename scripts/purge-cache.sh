#!/usr/bin/env bash
# Release cache purge utility
# Usage: ./purge-cache.sh <url> [header]
# Env: RELEASE_IPS (comma-separated node IPs)
set -euo pipefail

[[ $# -lt 1 || -z "${RELEASE_IPS:-}" ]] && { echo "::error::Usage: $0 <url> [header]"; exit 2; }

URL="$1"; HEADER="${2:-x-reset-cache: true}"
IFS=',' read -ra IPS <<< "$RELEASE_IPS"
DOMAIN=$(echo "$URL" | awk -F[/:] '{print $4}')
PORT=$([[ "$URL" == https* ]] && echo 443 || echo 80)

echo "======================== Purging: $URL =========================="
# Wait for rollout (30s max)
for i in {1..30}; do echo -n "."; sleep 1; done; echo " [✓]"

# Parallel purge requests
PIDS=(); FAILS=0
for IP in "${IPS[@]}"; do
  IP=$(echo "$IP" | tr -d ' '); MASK=$(echo "$IP" | sed 's/\.[^.]*\.[^.]*$/.xxx.xxx/')
  curl -sS --resolve "$DOMAIN:$PORT:$IP" -o /dev/null -w "  [%{http_code}] $MASK\n" \
    -H "$HEADER" --connect-timeout 10 "$URL" & PIDS+=($!)
done

# Collect results
for PID in "${PIDS[@]}"; do wait "$PID" || { echo "::warning::Node failed"; ((FAILS++))||true; }; done

[[ $FAILS -gt 0 ]] && { echo "======================== Done ($FAILS failed) ========================"; exit 1; }
echo "======================== Done ========================"