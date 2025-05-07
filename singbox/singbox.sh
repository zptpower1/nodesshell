#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 全局变量
SS_BASE_PATH="/usr/local/etc/sing-box"
CONFIG_PATH="${SS_BASE_PATH}/config.json"
BASE_CONFIG_PATH="${SS_BASE_PATH}/base_config.json"
USERS_PATH="${SS_BASE_PATH}/users.json"
BACKUP_DIR="${SS_BASE_PATH}/backup"
LOG_DIR="/var/log/sing-box"
SS_BIN="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 检查服务状态
check_service() {
    echo "🔍 Sing-box 服务状态："
    if pgrep -x "sing-box" > /dev/null; then
        echo "✅ 服务正在运行"
        echo
        echo "📊 进程信息："
        ps aux | grep sing-box | grep -v grep
        echo
        echo "🔌 监听端口："
        lsof -i -P -n | grep sing-box
        echo
        echo "📈 资源使用："
        top -b -n 1 | grep sing-box
        echo
        echo "📜 最近日志："
        if [ -f "${LOG_DIR}/sing-box.log" ]; then
            tail -n 10 "${LOG_DIR}/sing-box.log"
        else
            echo "❌ 日志文件不存在"
        fi
    else
        echo "❌ 服务未运行"
    fi
}

# 主函数
main() {
    case "$1" in
        status)
            check_service
            ;;
        *)
            echo "用法: $0 <command> [args]"
            echo
            echo "服务管理命令:"
            echo "  status      查看服务状态"
            exit 1
            ;;
    esac
}

# 调用主函数
main "$@"