FROM alpine AS builder

ARG TARGETARCH
ARG TARGETVARIANT

# 指定工作目录
WORKDIR /

# 复制文件
COPY ["config", "/config"]
COPY ["coco-linux-${TARGETARCH}${TARGETVARIANT:+${TARGETVARIANT}}", "coco.yml", "LICENSE", "NOTICE", "/"]

# 建立软链接
RUN ln -s coco-* coco

# 最终阶段
FROM scratch AS prod

LABEL description="Search, Connect, Collaborate, AI-powered Enterprise Search, all in one space."
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像
COPY --from=builder / /

# 设置工作目录
WORKDIR /

CMD ["/coco"]