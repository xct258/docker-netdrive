#!/bin/bash

# ============================================================
# 容器构建脚本 - 组件更新检查
# 功能：检查 OpenList 和 FileBrowser 是否有新版本，
#       有则自动下载更新，并记录版本号和更新时间到 version.txt
# ============================================================

# 工作目录（宿主机挂载目录），可从环境变量覆盖
DRIVE_DIR=${DRIVE_DIR:-/rec}

# --------------------------------------------------
# 版本比较函数
# 使用 sort -V（语义化版本排序）判断第一个版本是否大于第二个
# 返回：0（真）表示 $1 > $2，1（假）表示 $1 <= $2
# --------------------------------------------------
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | tail -n 1)" != "$1"
}

# --------------------------------------------------
# 检查并更新单个组件
# 参数：
#   $1 - 组件名称（如 OpenList / FileBrowser）
#   $2 - GitHub 仓库（user/repo）
#   $3 - version.txt 中对应的版本变量名
#   $4 - x86_64 架构的压缩包文件名匹配规则
#   $5 - aarch64 架构的压缩包文件名匹配规则
#   $6 - 组件安装目录
# 返回值：
#   0 - 已是最新，无需更新
#   1 - 检查/下载/解压过程中出错
#   2 - 已成功更新到新版本
# --------------------------------------------------
check_and_update() {
    local name=$1          # 组件名称
    local repo=$2          # GitHub 仓库地址
    local var_name=$3      # version.txt 中的版本变量名
    local asset_x64=$4     # x64 压缩包文件名匹配规则
    local asset_arm64=$5   # arm64 压缩包文件名匹配规则
    local install_dir=$6   # 安装目录

    # 从 version.txt 中读取当前安装的版本号
    local current_version=""
    if [ -f "${DRIVE_DIR}/version.txt" ]; then
        # 从文件中提取指定变量名的值
        current_version=$(grep "^${var_name}=" "${DRIVE_DIR}/version.txt" | cut -d'=' -f2)
    fi

    # 从 GitHub API 获取最新 release 信息
    local latest_release
    latest_release=$(curl -sf "https://api.github.com/repos/${repo}/releases/latest") || {
        echo "[${name}] -> 获取最新版本失败，跳过更新"
        return 1
    }

    # 从 API 返回的 JSON 中提取最新版本号（tag_name 字段）
    local latest_version
    latest_version=$(echo "$latest_release" | jq -r '.tag_name')
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo "[${name}] -> 解析版本号失败，跳过更新"
        return 1
    fi

    echo "[${name}] 当前版本: ${current_version:--}, 最新版本: ${latest_version}"

    # --------------------------------------------------
    # 版本对比：如果当前版本非空且不低于最新版本，则跳过
    # 使用 version_gt 函数比较语义化版本号
    # --------------------------------------------------
    if [ -n "$current_version" ] && ! version_gt "$latest_version" "$current_version"; then
        echo "[${name}] -> 已是最新版本 (${current_version})"
        return 0
    fi

    # --------------------------------------------------
    # 根据 CPU 架构选择对应的下载文件
    # x86_64（Intel/AMD 64位）或 aarch64（ARM 64位）
    # --------------------------------------------------
    local arch
    arch=$(uname -m)
    local download_url=""
    if [[ $arch == *"x86_64"* ]]; then
        # 从 API 返回的 assets 列表中匹配 x86_64 架构的下载链接
        download_url=$(echo "$latest_release" | jq -r ".assets[] | select(.name | test(\"${asset_x64}\")) | .browser_download_url")
    elif [[ $arch == *"aarch64"* ]]; then
        # 从 API 返回的 assets 列表中匹配 ARM64 架构的下载链接
        download_url=$(echo "$latest_release" | jq -r ".assets[] | select(.name | test(\"${asset_arm64}\")) | .browser_download_url")
    fi

    # 如果没有找到当前架构对应的下载文件，跳过更新
    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        echo "[${name}] -> 未找到当前架构（${arch}）的下载文件，跳过更新"
        return 1
    fi

    # --------------------------------------------------
    # 下载最新版本的压缩包
    # 下载到 /tmp/update 临时目录，避免污染工作目录
    # --------------------------------------------------
    echo "[${name}] -> 发现新版本，开始下载..."
    mkdir -p /tmp/update
    wget -q -O "/tmp/update/${name}.tar.gz" "$download_url" || {
        echo "[${name}] -> 下载失败，跳过更新"
        rm -rf /tmp/update
        return 1
    }

    # --------------------------------------------------
    # 解压压缩包到安装目录，覆盖旧文件
    # 使用 2>/dev/null 忽略解压时的警告信息
    # --------------------------------------------------
    mkdir -p "${install_dir}"
    if ! tar -xf "/tmp/update/${name}.tar.gz" -C "${install_dir}" 2>/dev/null; then
        echo "[${name}] -> 解压失败，跳过更新"
        rm -rf /tmp/update
        return 1
    fi

    # 给安装目录下的所有文件添加执行权限
    chmod +x "${install_dir}"/* 2>/dev/null

    # --------------------------------------------------
    # 更新 version.txt 中的版本信息
    # 获取当前时间作为更新时间戳
    # --------------------------------------------------
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    # 更新或新增版本号字段
    if [ -f "${DRIVE_DIR}/version.txt" ]; then
        if grep -q "^${var_name}=" "${DRIVE_DIR}/version.txt"; then
            # 如果已存在该字段，替换为新版本号
            sed -i "s|^${var_name}=.*|${var_name}=${latest_version}|" "${DRIVE_DIR}/version.txt"
        else
            # 如果不存在该字段，追加到文件末尾
            echo "${var_name}=${latest_version}" >> "${DRIVE_DIR}/version.txt"
        fi
    else
        # 如果 version.txt 不存在，则新建并写入
        echo "${var_name}=${latest_version}" > "${DRIVE_DIR}/version.txt"
    fi

    # 更新该组件的最后更新时间字段（如 UPDATED_OPENLIST、UPDATED_FILEBROWSER）
    local time_var="UPDATED_${name^^}"
    if grep -q "^${time_var}=" "${DRIVE_DIR}/version.txt" 2>/dev/null; then
        sed -i "s|^${time_var}=.*|${time_var}=${now}|" "${DRIVE_DIR}/version.txt"
    else
        echo "${time_var}=${now}" >> "${DRIVE_DIR}/version.txt"
    fi

    # 清理临时下载文件
    rm -rf /tmp/update
    echo "[${name}] -> 已更新至 ${latest_version}"
    return 2
}

# --------------------------------------------------
# 主流程
# 依次检查 OpenList 和 FileBrowser
# UPDATED 标记是否有组件被更新（0=无更新，2=有更新）
# --------------------------------------------------

UPDATED=0
rm -f /tmp/.updated_list

# 检查 OpenList 更新
# 仓库：OpenListTeam/OpenList
# 版本变量：VERSION_OPENLIST
# x86_64 匹配：openlist-linux-amd64.tar.gz
# ARM64 匹配：openlist-linux-arm64.tar.gz
# 安装目录：/app/openlist
check_and_update \
    "OpenList" \
    "OpenListTeam/OpenList" \
    "VERSION_OPENLIST" \
    "openlist-linux-amd64.tar.gz" \
    "openlist-linux-arm64.tar.gz" \
    "/app/openlist"
# 捕获返回值，如果返回 2 则将组件名写入更新列表
if [ $? -eq 2 ]; then
    UPDATED=2
    echo "OpenList" >> /tmp/.updated_list
fi

# 检查 FileBrowser 更新
# 仓库：filebrowser/filebrowser
# 版本变量：VERSION_FILEBROWSER
# x86_64 匹配：linux-amd64-filebrowser.tar.gz
# ARM64 匹配：linux-arm64-filebrowser.tar.gz
# 安装目录：/app/filebrowser
check_and_update \
    "FileBrowser" \
    "filebrowser/filebrowser" \
    "VERSION_FILEBROWSER" \
    "linux-amd64-filebrowser.tar.gz" \
    "linux-arm64-filebrowser.tar.gz" \
    "/app/filebrowser"
# 捕获返回值，如果返回 2 则将组件名写入更新列表
if [ $? -eq 2 ]; then
    UPDATED=2
    echo "FileBrowser" >> /tmp/.updated_list
fi

# --------------------------------------------------
# 无论是否有更新，都记录本次检查时间
# 这样可以追踪上次检查的时间点
# --------------------------------------------------
now=$(date '+%Y-%m-%d %H:%M:%S')
if grep -q "^LAST_CHECK=" "${DRIVE_DIR}/version.txt" 2>/dev/null; then
    # 更新已有字段
    sed -i "s|^LAST_CHECK=.*|LAST_CHECK=${now}|" "${DRIVE_DIR}/version.txt"
else
    # 新增字段
    echo "LAST_CHECK=${now}" >> "${DRIVE_DIR}/version.txt"
fi

# 返回是否有组件被更新（0=无，2=有），供调用方（如 start.sh）判断是否需要重启服务
exit $UPDATED
