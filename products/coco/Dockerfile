FROM infinilabs/baseos:almalinux-jdk-21 AS builder

ARG TARGETARCH

# 切换到工作目录
WORKDIR /app/easysearch

# 启动项与配置文件
ADD entrypoint.sh /sbin
ADD config/supervisor /app/tpl
ADD config/scripts /app/tpl

# 安装 Coco
ADD --chown=602:602 coco-$TARGETARCH /app/coco
RUN cd /app/coco && ln -s coco-* coco

# 安装 Easysearch
ADD --chown=602:602 easysearch-$TARGETARCH /app/easysearch
RUN cd /app/easysearch && ln -s /usr/local/jdk .

# 最终阶段
FROM scratch AS prod

LABEL description="INFINI Coco AI Server - Search, Connect, Collaborate, AI-powered enterprise search, all in one space."
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像，权限会丢失
COPY --from=builder / /

# 环境变量
ENV PATH=/sbin:/app/easysearch/jdk/bin:/app/easysearch/bin:$PATH

# 切换到工作目录
WORKDIR /app/easysearch

# 权限处理
RUN chown -R 602:602 /app/easysearch && chown -R 602:602 /app/coco

EXPOSE 9000 2900

ENTRYPOINT ["/sbin/tini", "--", "/sbin/entrypoint.sh"]
CMD ["easysearch"]