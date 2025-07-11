#!/bin/bash

# start-agent.sh

echo "Waiting for Easysearch on 127.0.0.1:9200..."

# 循环检查端口，直到可用。添加超时机制以防无限等待。
# 设置一个总的超时时间，例如 5 分钟 (300 秒)
timeout=300
elapsed=0
interval=5

while ! nc -z 127.0.0.1 9200; do
  if [ $elapsed -ge $timeout ]; then
    echo "Timeout: Easysearch not available after ${timeout} seconds. Exiting."
    exit 1
  fi
  echo "Easysearch not ready, sleeping for ${interval}s..."
  sleep $interval
  elapsed=$((elapsed + interval))
done

echo "Easysearch is up! Starting agent..."

# 使用 exec 来让 agent 进程替换掉 bash 进程。
# 这样 supervisor 就可以直接管理 agent 进程的 PID。
cd /app/easysearch/data/agent && exec ./agent