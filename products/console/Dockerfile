FROM infinilabs/baseos:alpine AS builder

ARG TARGETARCH
ARG TARGETVARIANT

# 指定工作目录
WORKDIR /

# 复制文件
COPY ["config", "/config"]
COPY ["console-linux-${TARGETARCH}${TARGETVARIANT:+${TARGETVARIANT}}", "console.yml", "LICENSE", "NOTICE", "/"]

# 建立软链接
RUN ln -s console-* console

# 最终阶段
FROM scratch AS prod

LABEL description="The easiest way to operate your own search platform."
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像
COPY --from=builder / /

# 设置工作目录
WORKDIR /

CMD ["/console"]