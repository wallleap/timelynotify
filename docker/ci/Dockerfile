# ============================================================
# HarmonyOS CI 构建镜像（DevEco Command Line Tools + JDK 17）
#
# 用途：GitHub Actions 托管 runner 无 DevEco SDK，本镜像把工具链固化，
#       app 流水线（release.yml / build-check.yml）通过 job.container 使用，
#       替代"每次构建下载 2GB CLT zip"的方案。
#
# 构建推送：由 .github/workflows/docker-image.yml 自动完成（推 ghcr.io/<owner>/harmonyos-ci）
#
# CLT 下载源说明：
#   默认指向自托管直链（官方 Command Line Tools for Linux(x86) 26.0.0.621 zip 的转存），
#   并固定 SHA256。项目 targetSdkVersion=26.0.0，必须用 26.0.0 线 CLT（6.1.x 线 SDK 过旧编不过）。
#   下载中心获取新版后，用 --build-arg CLT_URL=... CLT_SHA256=... 覆盖重建镜像。
#   ⚠️ 直链请保持长期可访问（CLT 体积 2.2GB，CI 重建镜像时依赖它）。
# ============================================================

# syntax=docker/dockerfile:1
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# ---- 可覆盖的构建参数：CLT 下载源与校验和 ----
ARG CLT_URL=https://static.oicode.cn/temp/ctl/commandline-tools-linux-x64-26.0.0.621.zip
ARG CLT_SHA256=0cea7ad6cc1af98ac701b9c61b7c9aae2d0f2104749a80ae84c1f6ca0fc17555

# ---- 基础工具 ----
# wget/curl: 下载 CLT；unzip: 解包；zstd: actions/cache 条目压缩必需（缺失会导致缓存永远 miss）
# openjdk-17-jdk: hap-sign-tool.jar 与 hvigor 运行；jq: 流水线 JSON 解析
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget curl zstd zip unzip python3 openjdk-17-jdk build-essential git jq \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

# ---- 安装 HarmonyOS Command Line Tools ----
# 解包布局：/opt/harmonyos-tools/command-line-tools/{bin, sdk/default, tool/node, ...}
#   bin/          → hvigorw / ohpm / hdc 等可执行
#   sdk/default   → HarmonyOS SDK（DEVECO_SDK_HOME）
#   tool/node     → hvigor 依赖的 Node.js（NODE_HOME）
RUN mkdir -p /opt/harmonyos-tools \
    && wget -q -O /tmp/clt.zip "$CLT_URL" \
    && echo "$CLT_SHA256  /tmp/clt.zip" | sha256sum -c - \
    && unzip -q /tmp/clt.zip -d /opt/harmonyos-tools/ \
    && rm -f /tmp/clt.zip \
    && chmod -R +x /opt/harmonyos-tools/command-line-tools/bin

# ---- 工具链环境变量（与 app 流水线 release.yml 中的路径约定一致）----
ENV COMMANDLINE_TOOL_DIR=/opt/harmonyos-tools
ENV DEVECO_SDK_HOME="$COMMANDLINE_TOOL_DIR/command-line-tools/sdk/default"
ENV NODE_HOME="$COMMANDLINE_TOOL_DIR/command-line-tools/tool/node"
ENV HVIGORW="$COMMANDLINE_TOOL_DIR/command-line-tools/bin/hvigorw"
ENV OHPM="$COMMANDLINE_TOOL_DIR/command-line-tools/bin/ohpm"
ENV HDC_HOME="$DEVECO_SDK_HOME/openharmony/toolchains"
ENV PATH="$COMMANDLINE_TOOL_DIR/command-line-tools/bin:$NODE_HOME/bin:$PATH"

# ---- 构建自检：关键工具必须可用（在镜像构建期就暴露问题，而不是 app 构建期）----
RUN node -v \
    && java -version \
    && "$OHPM" -v \
    && [ -x "$HVIGORW" ] && echo "hvigorw OK: $HVIGORW" \
    && [ -d "$DEVECO_SDK_HOME" ] && echo "SDK OK: $DEVECO_SDK_HOME"

WORKDIR /workspace
CMD ["bash"]
