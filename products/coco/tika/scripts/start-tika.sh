#!/bin/bash
set -e

echo "[entrypoint] Starting Apache Tika ${TIKA_VERSION:-3.2.3} on port 9998..."

# 健康检查：等待 Tika 就绪（在前台启动前先做预热判断）
# 先后台启动做健康检查
java -jar /opt/tika-server.jar --port 9998 &
TIKA_PID=$!

READY=false
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:9998/tika >/dev/null 2>&1; then
        echo "[entrypoint] Tika is ready."
        READY=true
        break
    fi
    if ! kill -0 "$TIKA_PID" 2>/dev/null; then
        echo "[entrypoint] Tika process exited unexpectedly." >&2
        exit 1
    fi
    echo "[entrypoint] Waiting for Tika... ($i/30)"
    sleep 2
done

if [ "$READY" = false ]; then
    echo "[entrypoint] Tika failed to become ready in time." >&2
    kill "$TIKA_PID" 2>/dev/null || true
    exit 1
fi

# 等待 Java 进程（让 supervisor 持有这个前台进程）
wait "$TIKA_PID"