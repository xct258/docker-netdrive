# ============================================================
# Dockerfile - 容器镜像构建文件
# 功能：构建一个包含 7z、OpenList、FileBrowser 的运行环境
# 使用方式：
#   docker build \
#     --build-arg GITHUB_USER=你的用户名 \
#     --build-arg GITHUB_REPO=你的仓库名 \
#     -t 镜像名:标签 .
# ============================================================

# 使用 Debian 作为基础镜像（稳定、包管理成熟）
FROM debian

# --------------------------------------------------
# 构建参数（通过 docker build --build-arg 传入）
# GITHUB_USER - GitHub 用户名
# GITHUB_REPO - GitHub 仓库名
# 用于构建时从 GitHub 下载 init-components.sh 等脚本
# --------------------------------------------------
ARG GITHUB_USER=
ARG GITHUB_REPO=

# 将构建参数传递为环境变量，供 init-components.sh 等脚本使用
ENV GITHUB_USER=${GITHUB_USER}
ENV GITHUB_REPO=${GITHUB_REPO}

# --------------------------------------------------
# 设置中文语言环境和时区
# LANG=zh_CN.UTF-8     - 中文 UTF-8 编码
# TZ=Asia/Shanghai     - 中国标准时间（东八区）
# --------------------------------------------------
RUN apt-get update && apt-get install -y locales tzdata && rm -rf /var/lib/apt/lists/* \
    # 生成中文 locale（zh_CN.UTF-8）
    && localedef -i zh_CN -c -f UTF-8 -A /usr/share/locale/locale.alias zh_CN.UTF-8

# 设置环境变量为中文
ENV LANG=zh_CN.UTF-8
# 设置时区为上海
ENV TZ=Asia/Shanghai

# --------------------------------------------------
# 安装构建依赖并执行初始化脚本
# 具体工作由 init-components.sh 完成：
#   1. 安装 curl、jq、wget 等工具
#   2. 从 GitHub API 获取 7z、OpenList、FileBrowser 的最新版本
#   3. 根据架构下载并安装对应二进制文件
#   4. 下载运行时脚本到 /usr/local/bin
#   5. 写入版本信息到 /app/version.txt
# --------------------------------------------------
RUN apt update \
    && apt install -y wget \
    # 创建临时目录（用于存放下载的脚本）
    && mkdir -p /root/tmp \
    # 从 GitHub 下载 init-components.sh
    && wget -O /root/tmp/init-components.sh https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/容器构建脚本/init-components.sh \
    && chmod +x /root/tmp/init-components.sh \
    # 执行初始化脚本（安装所有组件）
    && /root/tmp/init-components.sh \
    # 清理临时目录（减少镜像体积）
    && rm -rf /root/tmp \
    # 下载容器入口脚本到 /usr/local/bin
    && wget -O /usr/local/bin/start.sh https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/容器构建脚本/start.sh \
    && chmod +x /usr/local/bin/start.sh

# --------------------------------------------------
# 设置容器启动时执行的入口脚本
# start.sh 负责：
#   1. 初始化工作目录 /rec
#   2. 首次启动时检查组件更新
#   3. 启动 OpenList 和 FileBrowser 服务
#   4. 每 15 天循环检查更新，有更新则自动重启
# --------------------------------------------------
ENTRYPOINT ["/usr/local/bin/start.sh"]
