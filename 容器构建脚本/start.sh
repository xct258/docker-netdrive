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

# --------------------------------------------------
# 初始化工作目录
# 创建 OpenList 和 FileBrowser 的持久化数据目录
# --------------------------------------------------
mkdir -p ${DRIVE_DIR}/openlist ${DRIVE_DIR}/filebrowser

# --------------------------------------------------
# 首次启动时，将构建时写入的版本信息复制到工作目录
# 这样即使容器重启，版本信息也能持久保留
# --------------------------------------------------
if [ -f /app/version.txt ]; then
    cp /app/version.txt ${DRIVE_DIR}/version.txt
fi

# --------------------------------------------------
# 首次启动，先检查更新再启动服务
# 确保容器以最新版本的组件运行
# --------------------------------------------------
echo ""
echo "=========================================="
echo "  首次启动，检查组件更新..."
echo "=========================================="
bash ${DRIVE_START_SH_DIR}/check-update.sh

# --------------------------------------------------
# 启动 OpenList 和 FileBrowser 服务
# --------------------------------------------------
echo ""
echo "=========================================="
echo "  正在启动服务..."
echo "=========================================="
bash ${DRIVE_START_SH_DIR}/start-services.sh

echo ""
echo "=========================================="
echo "  所有服务已启动，每 15 天自动检查更新。"
echo "=========================================="

# --------------------------------------------------
# 进入循环检查模式
# 每 15 天检查一次组件更新
# 如果 check-update.sh 返回 2（有组件被更新），
# 则杀掉旧进程并重新启动服务
# --------------------------------------------------
while true; do
    # 等待 15 天
    sleep ${UPDATE_INTERVAL}

    echo ""
    echo "=========================================="
    echo "  定期检查更新..."
    echo "=========================================="

    # 执行更新检查，获取返回值
    bash ${DRIVE_START_SH_DIR}/check-update.sh

    # 如果返回值是 2，说明有组件已被更新
    if [ $? -eq 2 ]; then
        echo ""
        echo "有组件已更新，正在重启已更新的服务..."

        # 读取更新列表，逐个重启
        while IFS= read -r component; do
            case "$component" in
                OpenList)
                    echo "  重启 OpenList..."
                    pkill -f "/app/openlist/openlist" 2>/dev/null
                    sleep 2
                    bash ${DRIVE_START_SH_DIR}/start-services.sh openlist
                    echo "  OpenList 已重启"
                    ;;
                FileBrowser)
                    echo "  重启 FileBrowser..."
                    pkill -f "/app/filebrowser/filebrowser" 2>/dev/null
                    sleep 2
                    bash ${DRIVE_START_SH_DIR}/start-services.sh filebrowser
                    echo "  FileBrowser 已重启"
                    ;;
            esac
        done < /tmp/.updated_list

        rm -f /tmp/.updated_list
    fi
done
