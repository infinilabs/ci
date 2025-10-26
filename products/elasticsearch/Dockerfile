FROM infinilabs/baseos:24 AS builder

ARG TARGETARCH

# 创建 elasticsearch 用户（UID 603, GID 603）
RUN groupadd -g 603 elasticsearch && \
    useradd -u 603 -g 603 -m -d /usr/share/elasticsearch -s /sbin/nologin elasticsearch

# 切换到工作目录
WORKDIR /usr/share/elasticsearch

# Agent 与 配置项
ADD entrypoint.sh /sbin
ADD config/agent/ /app/tpl/
ADD config/supervisor/ /app/tpl/
ADD config/scripts/ /app/tpl/

# 安装 Agent
ADD --chown=elasticsearch:elasticsearch agent-$TARGETARCH /app/agent
RUN cd /app/agent && ln -s agent-* agent

# 安装 Elasticsearch
ADD --chown=elasticsearch:elasticsearch elasticsearch-$TARGETARCH /usr/share/elasticsearch
RUN cd /usr/share/elasticsearch && ln -s /usr/local/jdk .

# 最终阶段
FROM scratch AS prod

LABEL description="Elasticsearch"
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像，权限会丢失
COPY --from=builder / /

# 环境变量
ENV PATH=/sbin:/usr/share/elasticsearch/jdk/bin:/usr/share/elasticsearch/bin:$PATH

# 切换到工作目录
WORKDIR /usr/share/elasticsearch

# 权限处理
RUN chown -R elasticsearch:elasticsearch /usr/share/elasticsearch

EXPOSE 9200 9300

ENTRYPOINT ["/sbin/tini", "--", "/sbin/entrypoint.sh"]
CMD ["elasticsearch"]