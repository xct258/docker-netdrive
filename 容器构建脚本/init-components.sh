#!/bin/bash

# ============================================================
# 容器构建初始化脚本
# ============================================================

# GitHub 仓库地址（在构建文件指定即可）
GITHUB_USER=${GITHUB_USER}
GITHUB_REPO=${GITHUB_REPO}

# --------------------------------------------------
# 安装运行依赖工具
# --------------------------------------------------
apt install -y curl jq wget

# --------------------------------------------------
# 从 GitHub API 获取 7z 最新版本信息
# 仓库：ip7z/7zip
# 获取 x86_64 和 ARM64 两种架构的下载链接
# --------------------------------------------------
echo "[7z] 正在获取最新版本信息..."
latest_release_7z=$(curl -s https://api.github.com/repos/ip7z/7zip/releases/latest)
version_7z=$(echo "$latest_release_7z" | jq -r '.tag_name')
# x86_64 架构匹配 linux-x64.tar.xz
latest_7z_x64_url=$(echo "$latest_release_7z" | jq -r '.assets[] | select(.name | test("linux-x64.tar.xz")) | .browser_download_url')
# ARM64 架构匹配 linux-arm64.tar.xz
latest_7z_arm64_url=$(echo "$latest_release_7z" | jq -r '.assets[] | select(.name | test("linux-arm64.tar.xz")) | .browser_download_url')
echo "[7z] 最新版本: ${version_7z}"

# --------------------------------------------------
# 从 GitHub API 获取 OpenList 最新版本信息
# 仓库：OpenListTeam/OpenList（AList 的一个分支）
# 获取 x86_64 和 ARM64 两种架构的下载链接
# --------------------------------------------------
echo "[OpenList] 正在获取最新版本信息..."
latest_release_openlist=$(curl -s https://api.github.com/repos/OpenListTeam/OpenList/releases/latest)
version_openlist=$(echo "$latest_release_openlist" | jq -r '.tag_name')
# x86_64 架构匹配 openlist-linux-amd64.tar.gz
latest_openlist_x64_url=$(echo "$latest_release_openlist" | jq -r '.assets[] | select(.name | test("openlist-linux-amd64.tar.gz")) | .browser_download_url')
# ARM64 架构匹配 openlist-linux-arm64.tar.gz
latest_openlist_arm64_url=$(echo "$latest_release_openlist" | jq -r '.assets[] | select(.name | test("openlist-linux-arm64.tar.gz")) | .browser_download_url')
echo "[OpenList] 最新版本: ${version_openlist}"

# --------------------------------------------------
# 从 GitHub API 获取 FileBrowser 最新版本信息
# 仓库：filebrowser/filebrowser
# 获取 x86_64 和 ARM64 两种架构的下载链接
# --------------------------------------------------
echo "[FileBrowser] 正在获取最新版本信息..."
latest_release_filebrowser=$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest)
version_filebrowser=$(echo "$latest_release_filebrowser" | jq -r '.tag_name')
# x86_64 架构匹配 linux-amd64-filebrowser.tar.gz
latest_filebrowser_x64_url=$(echo "$latest_release_filebrowser" | jq -r '.assets[] | select(.name | test("linux-amd64-filebrowser.tar.gz")) | .browser_download_url')
# ARM64 架构匹配 linux-arm64-filebrowser.tar.gz
latest_filebrowser_arm64_url=$(echo "$latest_release_filebrowser" | jq -r '.assets[] | select(.name | test("linux-arm64-filebrowser.tar.gz")) | .browser_download_url')
echo "[FileBrowser] 最新版本: ${version_filebrowser}"

# --------------------------------------------------
# 从 GitHub API 获取 rclone 最新版本信息
# 仓库：rclone/rclone
# 获取 x86_64 和 ARM64 两种架构的下载链接
# --------------------------------------------------
echo "[rclone] 正在获取最新版本信息..."
latest_release_rclone=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest)
version_rclone=$(echo "$latest_release_rclone" | jq -r '.tag_name' | sed 's/^v//')
# x86_64 架构匹配 linux-amd64.tar.gz
latest_rclone_x64_url=$(echo "$latest_release_rclone" | jq -r '.assets[] | select(.name | test("linux-amd64.tar.gz")) | .browser_download_url')
# ARM64 架构匹配 linux-arm64.tar.gz
latest_rclone_arm64_url=$(echo "$latest_release_rclone" | jq -r '.assets[] | select(.name | test("linux-arm64.tar.gz")) | .browser_download_url')
echo "[rclone] 最新版本: ${version_rclone}"

# --------------------------------------------------
# 检测当前 CPU 架构，下载对应的二进制文件
# uname -m 返回值：
#   x86_64  - Intel/AMD 64位处理器
#   aarch64 - ARM 64位处理器（如树莓派、AWS Graviton）
# --------------------------------------------------
arch=$(uname -m)
echo "当前系统架构: ${arch}"

if [[ $arch == *"x86_64"* ]]; then
    # 下载 x86_64 架构的二进制文件
    echo "下载 x86_64 架构的组件..."
    wget -O /root/tmp/7zz.tar.xz "$latest_7z_x64_url"
    wget -O /root/tmp/openlist.tar.gz "$latest_openlist_x64_url"
    wget -O /root/tmp/filebrowser.tar.gz "$latest_filebrowser_x64_url"
    wget -O /root/tmp/rclone.tar.gz "$latest_rclone_x64_url"
elif [[ $arch == *"aarch64"* ]]; then
    # 下载 ARM64 架构的二进制文件
    echo "下载 ARM64 架构的组件..."
    wget -O /root/tmp/7zz.tar.xz "$latest_7z_arm64_url"
    wget -O /root/tmp/openlist.tar.gz "$latest_openlist_arm64_url"
    wget -O /root/tmp/filebrowser.tar.gz "$latest_filebrowser_arm64_url"
    wget -O /root/tmp/rclone.tar.gz "$latest_rclone_arm64_url"
fi

# --------------------------------------------------
# 安装压缩/解压工具
# tar     - 处理 .tar.gz 格式
# xz-utils - 处理 .tar.xz 格式（7z 的压缩格式）
# --------------------------------------------------
apt install -y tar xz-utils

# --------------------------------------------------
# 安装 7z（7-Zip 命令行版本）
# 解压后重命名为 7zz 并移动到 /bin 目录
# --------------------------------------------------
echo "正在安装 7z..."
tar -xf /root/tmp/7zz.tar.xz -C /root/tmp
chmod +x /root/tmp/7zz
mv /root/tmp/7zz /bin/7zz
echo "7z 安装完成"

# --------------------------------------------------
# 安装 OpenList 和 FileBrowser
# 分别解压到 /app/openlist 和 /app/filebrowser
# --------------------------------------------------
echo "正在安装 OpenList..."
mkdir -p /app/openlist
tar -xf /root/tmp/openlist.tar.gz -C /app/openlist
echo "OpenList 安装完成"

echo "正在安装 FileBrowser..."
mkdir -p /app/filebrowser
tar -xf /root/tmp/filebrowser.tar.gz -C /app/filebrowser
echo "FileBrowser 安装完成"

# --------------------------------------------------
# 安装 rclone
# rclone 的 tar.gz 解压后为 rclone-<version>-linux-<arch>/ 目录
# 需要从子目录中提取 rclone 二进制文件到 /usr/local/bin
# --------------------------------------------------
echo "正在安装 rclone..."
apt install -y unzip
mkdir -p /root/tmp/rclone_extract
tar -xf /root/tmp/rclone.tar.gz -C /root/tmp/rclone_extract
# 找到解压后的 rclone 二进制文件并移动到 /usr/local/bin
find /root/tmp/rclone_extract -name "rclone" -type f -exec mv {} /usr/local/bin/rclone \;
chmod +x /usr/local/bin/rclone
rm -rf /root/tmp/rclone_extract
echo "rclone 安装完成 ($(rclone version | head -1))"

# --------------------------------------------------
# 下载运行时脚本到 /usr/local/bin
# 这些脚本在容器启动时被 start.sh 调用
# --------------------------------------------------
echo "正在下载运行时脚本..."
wget -O /usr/local/bin/check-update.sh https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/容器构建脚本/check-update.sh
chmod +x /usr/local/bin/check-update.sh

wget -O /usr/local/bin/start-services.sh https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/容器构建脚本/start-services.sh
chmod +x /usr/local/bin/start-services.sh
echo "运行时脚本下载完成"

# --------------------------------------------------
# 写入版本信息文件到 /app/version.txt
# 该文件在容器首次启动时会被复制到 /rec/version.txt
# version.txt 包含以下信息：
#   BUILD_DATE          - 容器镜像构建时间
#   VERSION_7Z          - 7z 版本号
#   VERSION_OPENLIST    - OpenList 版本号
#   VERSION_FILEBROWSER - FileBrowser 版本号
#   VERSION_RCLONE      - rclone 版本号
#   LAST_CHECK          - 上次检查更新时间（运行时填充）
#   UPDATED_OPENLIST    - OpenList 最后更新时间（运行时填充）
#   UPDATED_FILEBROWSER - FileBrowser 最后更新时间（运行时填充）
# --------------------------------------------------
build_date="$(date '+%Y-%m-%d %H:%M:%S')"

cat << EOF > /app/version.txt
# 容器构建日期
BUILD_DATE=${build_date}

# 7z 版本
VERSION_7Z=${version_7z}

# OpenList 版本
VERSION_OPENLIST=${version_openlist}

# FileBrowser 版本
VERSION_FILEBROWSER=${version_filebrowser}

# rclone 版本
VERSION_RCLONE=${version_rclone}

# 上次检查时间
LAST_CHECK=

# 各组件最后更新时间
UPDATED_OPENLIST=
UPDATED_FILEBROWSER=
EOF

echo "=========================================="
echo "  容器构建完成"
echo "  构建时间: ${build_date}"
echo "  7z: ${version_7z}"
echo "  OpenList: ${version_openlist}"
echo "  FileBrowser: ${version_filebrowser}"
echo "  rclone: ${version_rclone}"
echo "=========================================="
