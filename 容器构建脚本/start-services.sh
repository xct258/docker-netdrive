#!/bin/bash

# ============================================================
# 服务启动脚本
# 功能：启动 OpenList 和 FileBrowser 服务
#       每个服务都以后台进程方式运行（nohup）
# ============================================================

# 工作目录（宿主机挂载目录）
DRIVE_DIR=${DRIVE_DIR:-/rec}

# --------------------------------------------------
# 启动 OpenList 服务
# OpenList 是一个文件列表服务，支持多存储源
# 官方启动方式：./openlist server --no-prefix
# 数据目录（含配置文件）存放在 /rec/openlist
# OpenList 默认监听端口：5244
# --------------------------------------------------
start_openlist() {
    # OpenList 二进制文件路径
    local binary="/app/openlist/openlist"

    # 检查二进制文件是否存在
    if [ ! -f "$binary" ]; then
        echo "[OpenList] 未找到程序文件 ${binary}，跳过启动"
        return 1
    fi

    # OpenList 数据目录（存放配置、数据库和会话）
    # 通过 --data 参数指定，OpenList 会在该目录下创建 data/ 子目录
    local data_dir="${DRIVE_DIR}/openlist/data"
    mkdir -p "$data_dir"

    # 标记是否需要首次初始化（检查 data 目录是否为空）
    local needs_init=false
    if [ -z "$(ls -A "$data_dir" 2>/dev/null)" ]; then
        needs_init=true
        echo "[OpenList] 检测到首次启动，初始化完成后将设置默认密码..."
    else
        echo "[OpenList] 正在启动..."
    fi

    # 后台启动 OpenList 服务
    #   server        启动 Web 服务（OpenList 主命令）
    #   --data        指定数据库和配置文件存放目录
    #   --no-prefix   禁用 URL 前缀，直接通过根路径访问
    nohup "$binary" server --data "$data_dir" > /dev/null 2>&1 &

    # 等待进程启动，最多等待 10 秒
    # 通过 pgrep 查找实际的 openlist 进程（nohup 的 $! 可能不准）
    local wait_seconds=10
    local pid=""
    for ((i = 1; i <= wait_seconds; i++)); do
        pid=$(pgrep -f "/app/openlist/openlist" 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$pid" ]; then
        echo "[OpenList] 启动失败，未检测到运行中的进程"
        return 1
    fi

    # 如果是首次启动，等待初始化完成并设置默认管理员密码
    if [ "$needs_init" = true ]; then
        # 等待 3 秒，确保 OpenList 完成数据库和配置文件的创建
        sleep 3

        # 设置默认管理员密码为 123456
        # 用户后续可以通过 Web 界面登录后自行修改
        echo "[OpenList] 设置默认管理员密码..."
        "$binary" admin set 123456 --data "$data_dir" > /dev/null 2>&1

        echo "[OpenList] 初始化完成，默认管理密码: 123456"
    fi

    echo "[OpenList] 启动成功 (PID ${pid})"
}

# --------------------------------------------------
# 启动 FileBrowser 服务
# FileBrowser 是一个网页文件管理器
# 默认监听 8080 端口，以 /rec 为根目录
# 数据库文件存放在 /rec/filebrowser/database.db
# --------------------------------------------------
start_filebrowser() {
    # FileBrowser 二进制文件路径
    local binary="/app/filebrowser/filebrowser"

    # 检查二进制文件是否存在
    if [ ! -f "$binary" ]; then
        echo "[FileBrowser] 未找到程序文件 ${binary}，跳过启动"
        return 1
    fi

    # 确保数据库目录存在
    local db_dir="${DRIVE_DIR}/filebrowser"
    mkdir -p "$db_dir"

    # 启动 FileBrowser
    #   -a 0.0.0.0      监听所有网络接口
    #   -p 5470          服务端口
    #   -d 数据库文件路径 存储用户配置
    #   -r /mnt          文件浏览根目录
    echo "[FileBrowser] 正在启动..."
    nohup "$binary" \
        -a 0.0.0.0 \
        -p 5470 \
        -d "${db_dir}/filebrowser.db" \
        -r /mnt \
        > /dev/null 2>&1 &
    echo "[FileBrowser] 已启动 (PID $!)"
}

# --------------------------------------------------
# 主流程：根据参数启动指定服务
# 不带参数时启动所有服务
# --------------------------------------------------
if [ $# -eq 0 ]; then
    # 无参数：启动全部服务
    start_openlist
    start_filebrowser
else
    # 有参数：只启动指定的服务
    for arg in "$@"; do
        case "$arg" in
            openlist)   start_openlist ;;
            filebrowser) start_filebrowser ;;
            *)          echo "[start-services] 未知服务: ${arg}，跳过" ;;
        esac
    done
fi
