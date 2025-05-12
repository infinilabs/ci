FROM alpine AS builder

ARG TARGETARCH

ENV APP=cloud_terraform_app

WORKDIR /

COPY ["init.sh", "/bin/init.sh"]
COPY ["app/gateway", "terraform/gateway"]
COPY ["app/runtime", "terraform/runtime"]

RUN cd /terraform \
    && wget https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_${TARGETARCH}.zip \
    && unzip terraform_1.9.8_linux_${TARGETARCH}.zip \
    && /bin/init.sh \
    && rm -f terraform_1.9.8_linux_${TARGETARCH}.zip

FROM scratch AS prod

LABEL description="INFINILabs Terraform base image."
LABEL maintainer="Medcl、Hardy@INFINILabs <luohf@infinilabs.com>"

# 从构建阶段拷贝文件到最终镜像
COPY --from=builder / /