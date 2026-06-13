#!/bin/bash

# ============================================================
# 容器构建脚本 - 组件更新检查
# 功能：检查 OpenList 和 FileBrowser 是否有新版本，
#       有则自动下载更新，并记录版本号和更新时间到 version.txt
# ============================================================

# 工作目录（宿主机挂载目录），可从环境变量覆盖
DRIVE_DIR=${DRIVE_DIR:-/rec}

# 日志文件路径
LOG_FILE="${DRIVE_DIR}/log/container.log"
mkdir -p "$(dirname "$LOG_FILE")"

# --------------------------------------------------
# 日志函数
# log()     写入日志文件
# console() 同时输出到 stdout 和日志文件
# --------------------------------------------------
log()     { echo "$(date '+%Y-%m-%d %H:%M:%S') [check-update] $*" >> "$LOG_FILE"; }
console() { echo "[check-update] $@"; log "$@"; }

# --------------------------------------------------
# 版本比较函数
# 使用 sort -V（语义化版本排序）判断第一个版本是否大于第二个
# 返回：0（真）表示 $1 > $2，1（假）表示 $1 <= $2
# --------------------------------------------------
version_gt() {
    local sorted
    sorted=$(printf '%s\n' "$@" | sort -V | tail -n 1)
    test "$sorted" != "$2"
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
        current_version=$(grep "^${var_name}=" "${DRIVE_DIR}/version.txt" | cut -d'=' -f2)
    fi

    # 从 GitHub API 获取最新 release 信息
    local latest_release
    latest_release=$(curl -sf "https://api.github.com/repos/${repo}/releases/latest") || {
        log "[${name}] 获取最新版本失败，跳过更新"
        return 1
    }

    # 从 API 返回的 JSON 中提取最新版本号（tag_name 字段）
    local latest_version
    latest_version=$(echo "$latest_release" | jq -r '.tag_name')
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        log "[${name}] 解析版本号失败，跳过更新"
        return 1
    fi

    log "[${name}] 当前版本: ${current_version:--}, 最新版本: ${latest_version}"

    # 版本对比：如果当前版本非空且不低于最新版本，则跳过
    if [ -n "$current_version" ] && ! version_gt "$latest_version" "$current_version"; then
        log "[${name}] 已是最新版本 (${current_version})"
        return 0
    fi

    # 根据 CPU 架构选择对应的下载文件
    local arch
    arch=$(uname -m)
    local download_url=""
    if [[ $arch == *"x86_64"* ]]; then
        download_url=$(echo "$latest_release" | jq -r ".assets[] | select(.name | test(\"${asset_x64}\")) | .browser_download_url")
    elif [[ $arch == *"aarch64"* ]]; then
        download_url=$(echo "$latest_release" | jq -r ".assets[] | select(.name | test(\"${asset_arm64}\")) | .browser_download_url")
    fi

    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        log "[${name}] 未找到当前架构（${arch}）的下载文件，跳过更新"
        return 1
    fi

    # 下载最新版本的压缩包
    log "[${name}] 发现新版本 ${latest_version}，开始下载..."
    mkdir -p /tmp/update
    wget -q -O "/tmp/update/${name}.tar.gz" "$download_url" || {
        log "[${name}] 下载失败，跳过更新"
        rm -rf /tmp/update
        return 1
    }

    # 解压压缩包到安装目录，覆盖旧文件
    mkdir -p "${install_dir}"
    if ! tar -xf "/tmp/update/${name}.tar.gz" -C "${install_dir}" 2>/dev/null; then
        log "[${name}] 解压失败，跳过更新"
        rm -rf /tmp/update
        return 1
    fi

    # 给安装目录下的所有文件添加执行权限
    chmod +x "${install_dir}"/* 2>/dev/null

    # 更新 version.txt 中的版本信息
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    if [ -f "${DRIVE_DIR}/version.txt" ]; then
        if grep -q "^${var_name}=" "${DRIVE_DIR}/version.txt"; then
            sed -i "s|^${var_name}=.*|${var_name}=${latest_version}|" "${DRIVE_DIR}/version.txt"
        else
            echo "${var_name}=${latest_version}" >> "${DRIVE_DIR}/version.txt"
        fi
    else
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
    log "[${name}] 已更新至 ${latest_version}"
    return 2
}

# --------------------------------------------------
# 主流程
# 依次检查 OpenList 和 FileBrowser
# --------------------------------------------------

UPDATED=0
rm -f /tmp/.updated_list

# 检查 OpenList 更新
check_and_update \
    "OpenList" \
    "OpenListTeam/OpenList" \
    "VERSION_OPENLIST" \
    "openlist-linux-amd64.tar.gz" \
    "openlist-linux-arm64.tar.gz" \
    "/app/openlist"
if [ $? -eq 2 ]; then
    UPDATED=2
    echo "OpenList" >> /tmp/.updated_list
fi

# 检查 FileBrowser 更新
check_and_update \
    "FileBrowser" \
    "filebrowser/filebrowser" \
    "VERSION_FILEBROWSER" \
    "linux-amd64-filebrowser.tar.gz" \
    "linux-arm64-filebrowser.tar.gz" \
    "/app/filebrowser"
if [ $? -eq 2 ]; then
    UPDATED=2
    echo "FileBrowser" >> /tmp/.updated_list
fi

# 记录本次检查时间
now=$(date '+%Y-%m-%d %H:%M:%S')
if grep -q "^LAST_CHECK=" "${DRIVE_DIR}/version.txt" 2>/dev/null; then
    sed -i "s|^LAST_CHECK=.*|LAST_CHECK=${now}|" "${DRIVE_DIR}/version.txt"
else
    echo "LAST_CHECK=${now}" >> "${DRIVE_DIR}/version.txt"
fi

exit $UPDATED
