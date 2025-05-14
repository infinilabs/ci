FROM alpine AS builder

ARG TARGETARCH
ARG TARGETVARIANT

# 指定工作目录
WORKDIR /

# 复制文件
COPY ["config", "/config"]
COPY ["cloud-linux-${TARGETARCH}${TARGETVARIANT:+${TARGETVARIANT}}", "cloud.yml", "LICENSE", "NOTICE", "/"]

# 建立软链接
RUN ln -s cloud-* cloud

# 最终阶段
FROM scratch AS prod

LABEL description="INFINI Cloud for Easysearch, Elasticsearch, Opensearch operate platform."
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像
COPY --from=builder / /

# 设置工作目录
WORKDIR /

CMD ["/cloud"]