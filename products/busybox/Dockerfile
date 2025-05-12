ARG BUSYBOX_VERSION=1.37.0

FROM busybox:${BUSYBOX_VERSION}-glibc AS builder

# 指定工作目录
WORKDIR /

# 最终阶段
FROM scratch AS prod

LABEL description="INFINILabs Busybox base image."
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像
COPY --from=builder / /

# 设置工作目录
WORKDIR /

CMD ["/bin/sh"]