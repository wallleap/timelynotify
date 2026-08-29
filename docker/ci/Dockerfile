# ============================================================
# HarmonyOS CI 构建镜像（DevEco Command Line Tools + JDK 17）
#
# 用途：GitHub Actions 托管 runner 无 DevEco SDK，本镜像把工具链固化，
#       app 流水线（release.yml / build-check.yml）通过 job.container 使用，
#       替代"每次构建下载 2GB CLT zip"的方案。
#
# 构建推送：由 .github/workflows/docker-image.yml 自动完成（推 ghcr.io/<owner>/harmonyos-ci）
#
# CLT zip 来源说明（构建 context 中必须包含 clt.zip）：
#   - CI：docker-image.yml 会先下载官方 zip（带 actions/cache + SHA256 固定校验）再构建
#   - 本地：把官方 Command Line Tools for Linux(x86) zip 下载后放到 docker/ci/clt.zip：
#       docker buildx build --platform linux/amd64 -f docker/ci/Dockerfile -t harmonyos-ci docker/ci
#   项目 targetSdkVersion=26.0.0，必须用 26.0.0 线 CLT（6.1.x 线 SDK 过旧编不过）。
# ============================================================

# syntax=docker/dockerfile:1
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# ---- 可覆盖的构建参数：CLT zip 的 SHA256（用于构建期完整性校验） ----
ARG CLT_SHA256=0cea7ad6cc1af98ac701b9c61b7c9aae2d0f2104749a80ae84c1f6ca0fc17555

# ---- 基础工具 ----
# unzip: 解包 CLT；zstd: docker GHA 缓存压缩所需；openjdk-17-jdk: hap-sign-tool.jar 与 hvigor 运行；jq: 流水线 JSON 解析
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl zstd zip unzip python3 openjdk-17-jdk build-essential git jq \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

# ---- 引入 CLT zip（来自构建 context），先校验 SHA256 再解包 ----
COPY clt.zip /tmp/clt.zip
RUN echo "$CLT_SHA256  /tmp/clt.zip" | sha256sum -c - \
    && mkdir -p /opt/harmonyos-tools \
    && unzip -q /tmp/clt.zip -d /opt/harmonyos-tools/ \
    && rm -f /tmp/clt.zip \
    && chmod -R +x /opt/harmonyos-tools/command-line-tools/bin

# 解包布局：/opt/harmonyos-tools/command-line-tools/{bin, sdk/default, tool/node, ...}
#   bin/          → hvigorw / ohpm / hdc 等可执行
#   sdk/          → DEVECO_SDK_HOME 必须指向这里（其下才有 default/，指向 default 本身会报 00303168 SDK component missing）
#   tool/node     → hvigor 依赖的 Node.js（NODE_HOME）

# ---- 工具链环境变量（与 app 流水线 release.yml 中的路径约定一致）----
ENV COMMANDLINE_TOOL_DIR=/opt/harmonyos-tools
ENV DEVECO_SDK_HOME="$COMMANDLINE_TOOL_DIR/command-line-tools/sdk"
ENV NODE_HOME="$COMMANDLINE_TOOL_DIR/command-line-tools/tool/node"
ENV HVIGORW="$COMMANDLINE_TOOL_DIR/command-line-tools/bin/hvigorw"
ENV OHPM="$COMMANDLINE_TOOL_DIR/command-line-tools/bin/ohpm"
ENV HDC_HOME="$DEVECO_SDK_HOME/default/openharmony/toolchains"
ENV PATH="$COMMANDLINE_TOOL_DIR/command-line-tools/bin:$NODE_HOME/bin:$PATH"

# ---- 构建自检：关键工具必须可用（在镜像构建期就暴露问题，而不是 app 构建期）----
RUN node -v \
    && java -version \
    && "$OHPM" -v \
    && [ -x "$HVIGORW" ] && echo "hvigorw OK: $HVIGORW" \
    && [ -d "$DEVECO_SDK_HOME" ] && echo "SDK OK: $DEVECO_SDK_HOME"

# ---- git 安全策略：容器内用户(通常 root)与挂载仓库属主不一致时，git 会以
#      dubious ownership 拒绝操作仓库；系统级信任任意目录，流水线无需逐 step 配置 ----
RUN git config --system --add safe.directory '*'

WORKDIR /workspace
CMD ["bash"]
