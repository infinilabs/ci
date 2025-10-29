FROM infinilabs/baseos:jdk-17 AS builder

ARG TARGETARCH

# 切换到工作目录
WORKDIR /app/elasticsearch

# Agent 与 配置项
ADD entrypoint.sh /sbin
ADD config/agent/ /app/tpl/
ADD config/supervisor/ /app/tpl/
ADD config/scripts/ /app/tpl/

# 安装 Agent
ADD --chown=ezs:ezs agent-$TARGETARCH /app/agent
RUN cd /app/agent && ln -s agent-* agent

# 安装 Elasticsearch
ADD --chown=ezs:ezs elasticsearch-$TARGETARCH /app/elasticsearch
RUN cd /app/elasticsearch && \
    rm -rf ./jdk && \
    ln -s /usr/local/jdk .

# 最终阶段
FROM scratch AS prod

LABEL description="Elasticsearch with INFINI Agent integrated."
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像，权限会丢失
COPY --from=builder / /

# 环境变量
ENV PATH=/sbin:/app/elasticsearch/jdk/bin:/app/elasticsearch/bin:$PATH

# 切换到工作目录
WORKDIR /app/elasticsearch

# 权限处理
RUN chown -R ezs:ezs /app/elasticsearch

EXPOSE 9200 9300

ENTRYPOINT ["/sbin/tini", "--", "/sbin/entrypoint.sh"]
CMD ["elasticsearch"]