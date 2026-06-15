#!/bin/bash

# ============================================================
# 容器入口脚本
# 功能：容器启动时的主入口，负责初始化目录、检查更新、启动服务
#       以及定期（每 15 天）循环检查组件更新
# ============================================================

# 宿主机挂载目录（工作目录），所有持久化数据存放于此
DRIVE_DIR=/rec

# 启动脚本存放目录（初始化组件时下载到 /usr/local/bin/）
DRIVE_START_SH_DIR=/usr/local/bin

# 更新检查周期：15 天（单位：秒）
UPDATE_INTERVAL=$((15 * 24 * 60 * 60))

# 日志文件路径
LOG_FILE="${DRIVE_DIR}/log/container.log"
mkdir -p "$(dirname "$LOG_FILE")"

# --------------------------------------------------
# 日志函数
# log()     写入日志文件（不输出到 docker logs）
# console() 同时输出到 docker logs 和日志文件
# --------------------------------------------------
log()     { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"; }
console() { echo "$(date '+%Y-%m-%d %H:%M:%S') $@"; log "$@"; }

# --------------------------------------------------
# 初始化工作目录
# 创建 OpenList 和 FileBrowser 的持久化数据目录
# --------------------------------------------------
mkdir -p ${DRIVE_DIR}/openlist ${DRIVE_DIR}/filebrowser

# --------------------------------------------------
# 首次启动时，将构建时写入的版本信息复制到工作目录
# 仅当 /rec/version.txt 不存在时才复制，避免覆盖用户手动修改
# --------------------------------------------------
if [ -f /app/version.txt ] && [ ! -f ${DRIVE_DIR}/version.txt ]; then
    cp /app/version.txt ${DRIVE_DIR}/version.txt
    log "已从构建镜像初始化版本信息"
fi

log "=========================================="
log "  容器启动，检查组件更新..."
log "=========================================="
bash ${DRIVE_START_SH_DIR}/check-update.sh

log "=========================================="
log "  正在启动服务..."
log "=========================================="
bash ${DRIVE_START_SH_DIR}/start-services.sh

log "=========================================="
log "  服务启动流程结束，进入定期检查模式。"
log "  日志文件: ${LOG_FILE}"
log "=========================================="

# --------------------------------------------------
# 进入循环检查模式
# 每 15 天检查一次组件更新
# 如果 check-update.sh 返回 2（有组件被更新），
# 则杀掉旧进程并重新启动服务
# --------------------------------------------------
while true; do
    sleep ${UPDATE_INTERVAL}

    log "=========================================="
    log "  定期检查更新..."
    log "=========================================="

    bash ${DRIVE_START_SH_DIR}/check-update.sh

    if [ $? -eq 2 ]; then
        log "有组件已更新，正在重启已更新的服务..."

        while IFS= read -r component; do
            case "$component" in
                OpenList)
                    log "  重启 OpenList..."
                    pkill -f "/app/openlist/openlist" 2>/dev/null
                    sleep 2
                    bash ${DRIVE_START_SH_DIR}/start-services.sh openlist
                    log "  OpenList 已重启"
                    ;;
                FileBrowser)
                    log "  重启 FileBrowser..."
                    pkill -f "/app/filebrowser/filebrowser" 2>/dev/null
                    sleep 2
                    bash ${DRIVE_START_SH_DIR}/start-services.sh filebrowser
                    log "  FileBrowser 已重启"
                    ;;
            esac
        done < /tmp/.updated_list
        rm -f /tmp/.updated_list
    fi
done
