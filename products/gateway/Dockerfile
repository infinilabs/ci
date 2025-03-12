FROM alpine AS builder

ARG TARGETARCH
ARG TARGETVARIANT

# 指定工作目录
WORKDIR /

# 安装启动器
RUN command -v tini || apk add --no-cache tini

# 复制文件
COPY ["gateway-linux-${TARGETARCH}${TARGETVARIANT:+${TARGETVARIANT}}", "gateway.yml", "LICENSE", "NOTICE", "/"]

# 建立软链接
RUN ln -s gateway-* gateway

# 最终阶段
FROM scratch AS prod

LABEL description="A light-weight, powerful and high-performance search gateway."
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像
COPY --from=builder / /

# 设置工作目录
WORKDIR /

ENTRYPOINT ["tini", "--"]
CMD ["/gateway"]