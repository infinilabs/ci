FROM python:3.12-slim

LABEL org.opencontainers.image.name="mem0/openmemory-mcp-easysearch"

# 使用阿里云镜像
ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/mem0
COPY pyproject.toml README.md ./
COPY mem0/ ./mem0/

WORKDIR /usr/src/openmemory
COPY openmemory/api/requirements.txt .

# 先升级基础工具（使用镜像）
RUN pip install --upgrade pip setuptools wheel -i ${PIP_INDEX_URL} \
    && pip install --no-cache-dir packaging>=24.2 hatchling -i ${PIP_INDEX_URL}

# 安装项目依赖（使用镜像）
RUN pip install --no-cache-dir -r requirements.txt -i ${PIP_INDEX_URL}

# 移除旧版 mem0ai（忽略错误）
RUN pip uninstall -y mem0ai || true

# 安装本地 mem0 源码（仍使用镜像源安装可能需要的额外依赖）
RUN pip install --no-cache-dir "/usr/src/mem0[extras]" -i ${PIP_INDEX_URL}

COPY openmemory/api/ .

EXPOSE 8765
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8765"]