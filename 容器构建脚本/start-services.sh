#!/bin/bash

# ============================================================
# 服务启动脚本
# 功能：启动 OpenList 和 FileBrowser 服务
#       每个服务都以后台进程方式运行（nohup）
# ============================================================

# 工作目录（宿主机挂载目录）
DRIVE_DIR=/rec

# 日志文件路径
LOG_FILE="${DRIVE_DIR}/log/container.log"
mkdir -p "$(dirname "$LOG_FILE")"

# --------------------------------------------------
# 日志函数
# log()     写入日志文件
# console() 同时输出到 stdout 和日志文件
# --------------------------------------------------
log()     { echo "$(date '+%Y-%m-%d %H:%M:%S') [start-services] $*" >> "$LOG_FILE"; }
console() { echo "$@"; log "$@"; }

# --------------------------------------------------
# 启动 OpenList 服务
# OpenList 是一个文件列表服务，支持多存储源
# 官方启动方式：./openlist server --no-prefix
# 数据目录（含配置文件）存放在 /rec/openlist
# OpenList 默认监听端口：5244
# --------------------------------------------------
start_openlist() {
    local binary="/app/openlist/openlist"

    if [ ! -f "$binary" ]; then
        console "[OpenList] 未找到程序文件 ${binary}，跳过启动"
        return 1
    fi

    local data_dir="${DRIVE_DIR}/openlist/data"
    mkdir -p "$data_dir"

    local needs_init=false
    if [ -z "$(ls -A "$data_dir" 2>/dev/null)" ]; then
        needs_init=true
        console "[OpenList] 检测到首次启动，正在生成随机密码..."
    else
        log "[OpenList] 正在启动..."
    fi

    # 启动 OpenList 服务
    if [ "$needs_init" = true ]; then
        nohup "$binary" server --data "$data_dir" > /tmp/openlist_startup.log 2>&1 &
    else
        nohup "$binary" server --data "$data_dir" > /dev/null 2>&1 &
    fi

    # 等待进程启动
    local wait_seconds=10
    local pid=""
    local binary_name
    binary_name=$(basename "$binary")
    for ((i = 1; i <= wait_seconds; i++)); do
        pid=$(pidof "$binary_name" 2>/dev/null)
        if [ -n "$pid" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$pid" ]; then
        console "[OpenList] 启动失败，未检测到运行中的进程"
        return 1
    fi

    # 首次启动：提取随机密码并输出到控制台
    if [ "$needs_init" = true ]; then
        sleep 2
        local ol_password
        ol_password=$(grep -i "password" /tmp/openlist_startup.log 2>/dev/null | head -1)
        if [ -n "$ol_password" ]; then
            console "[OpenList] ${ol_password}"
            console "[OpenList] 初始账号: admin，请登录后修改密码"
        else
            log "[OpenList] 未提取到密码，原始日志:"
            cat /tmp/openlist_startup.log >> "$LOG_FILE"
            console "[OpenList] 密码信息见上方日志，请查看 docker logs"
        fi
        rm -f /tmp/openlist_startup.log
    fi

    log "[OpenList] 启动成功 (PID ${pid})"
}

# --------------------------------------------------
# 启动 FileBrowser 服务
# FileBrowser 是一个网页文件管理器
# 默认监听 8080 端口，以 /rec 为根目录
# 数据库文件存放在 /rec/filebrowser/database.db
# --------------------------------------------------
start_filebrowser() {
    local binary="/app/filebrowser/filebrowser"

    if [ ! -f "$binary" ]; then
        console "[FileBrowser] 未找到程序文件 ${binary}，跳过启动"
        return 1
    fi

    local db_dir="${DRIVE_DIR}/filebrowser"
    mkdir -p "$db_dir"

    local is_first_run=false
    if [ ! -f "${db_dir}/filebrowser.db" ]; then
        is_first_run=true
        console "[FileBrowser] 检测到首次启动，正在生成随机密码..."
    fi

    # 启动 FileBrowser
    if [ "$is_first_run" = true ]; then
        nohup "$binary" \
            -a 0.0.0.0 \
            -p 5470 \
            -d "${db_dir}/filebrowser.db" \
            -r /mnt \
            > /tmp/filebrowser_startup.log 2>&1 &

        sleep 3

        local fb_password
        fb_password=$(grep -i "password" /tmp/filebrowser_startup.log 2>/dev/null | head -1)
        if [ -n "$fb_password" ]; then
            console "[FileBrowser] ${fb_password}"
            console "[FileBrowser] 初始账号: admin，请登录后修改密码"
        else
            log "[FileBrowser] 未提取到密码，原始日志:"
            cat /tmp/filebrowser_startup.log >> "$LOG_FILE"
            console "[FileBrowser] 密码信息见上方日志，请查看 docker logs"
        fi
        rm -f /tmp/filebrowser_startup.log
    else
        nohup "$binary" \
            -a 0.0.0.0 \
            -p 5470 \
            -d "${db_dir}/filebrowser.db" \
            -r /mnt \
            > /dev/null 2>&1 &
    fi

    local fb_pid
    fb_pid=$(pidof filebrowser 2>/dev/null)
    log "[FileBrowser] 启动成功 (PID ${fb_pid:-unknown})"
}

# --------------------------------------------------
# 主流程：根据参数启动指定服务
# 不带参数时启动所有服务
# --------------------------------------------------
if [ $# -eq 0 ]; then
    start_openlist
    start_filebrowser
else
    for arg in "$@"; do
        case "$arg" in
            openlist)   start_openlist ;;
            filebrowser) start_filebrowser ;;
            *)          log "[start-services] 未知服务: ${arg}，跳过" ;;
        esac
    done
fi
