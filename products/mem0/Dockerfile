# Dockerfile for OpenMemory MCP server with Easysearch vector store support.
# Build context must be the repo root.
#
# Build:
#   docker build \
#     -t public/openmemory-mcp-easysearch \
#     -f Dockerfile.easysearch .
#
# Run:
#   docker run -d \
#     --name openmemory-mcp \
#     -v $(pwd)/openmemory/api/.env:/app/.env:ro \
#     -p 8765:8765 \
#     public/openmemory-mcp-easysearch
#
# Override defaults at runtime (no rebuild needed):
#   docker run ... -e APP_PORT=9000 -e APP_WORKERS=4 -e LOG_LEVEL=debug ...

# ══════════════════════════════════════════════════════
# Stage 1 — builder: compile deps, never ships to prod
# ══════════════════════════════════════════════════════
FROM python:3.12-slim AS builder

ARG PIP_INDEX_URL=https://pypi.org/simple/

# ── Install build-time OS dependencies ──
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
    && rm -rf /var/lib/apt/lists/*

# ── Upgrade packaging tools ──
RUN pip install --no-cache-dir --upgrade \
        pip setuptools wheel packaging hatchling \
    -i ${PIP_INDEX_URL}

# ── Step 1: copy the local mem0 package ──
COPY mem0/pyproject.toml mem0/README.md /usr/src/mem0/
COPY mem0/mem0/                          /usr/src/mem0/mem0/

# ── Step 2: install openmemory/api dependencies ──
#    Copy requirements first so this layer is cached when only app code changes.
COPY openmemory/api/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt -i ${PIP_INDEX_URL} \
    && pip uninstall -y mem0ai || true \
    && pip install --no-cache-dir "/usr/src/mem0[extras]" -i ${PIP_INDEX_URL}

# ══════════════════════════════════════════════════════
# Stage 2 — runtime: minimal image, no compiler toolchain
# ══════════════════════════════════════════════════════
FROM python:3.12-slim AS runtime

LABEL org.opencontainers.image.name="public/openmemory-mcp-easysearch" \
      org.opencontainers.image.description="OpenMemory MCP server with Easysearch vector store support." \
      maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# Runtime tunables — all overridable via -e / environment in compose
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_HOST=0.0.0.0 \
    APP_PORT=8765 \
    APP_WORKERS=1 \
    LOG_LEVEL=info

# ── Bring in installed packages from builder (no gcc/build tools) ──
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin                           /usr/local/bin

# ── Create a non-root user for least-privilege execution ──
RUN groupadd --gid 1001 appgroup \
    && useradd  --uid 1001 --gid appgroup --no-create-home appuser

# ── Step 3: copy application code ──
WORKDIR /app
COPY openmemory/api/ .
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE ${APP_PORT}

# Health probe — replace /healthz with your actual liveness endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c \
        "import urllib.request; urllib.request.urlopen('http://localhost:${APP_PORT}/healthz')" \
    || exit 1

CMD ["sh", "-c", \
     "uvicorn main:app \
        --host ${APP_HOST} \
        --port ${APP_PORT} \
        --workers ${APP_WORKERS} \
        --log-level ${LOG_LEVEL}"]