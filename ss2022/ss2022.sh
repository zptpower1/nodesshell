#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 加载所有模块
source "$SCRIPT_DIR/lib/utils.sh"

# 检查环境文件
load_env

# 加载其他模块
source "${SCRIPT_DIR}/lib/install.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/service.sh"
source "${SCRIPT_DIR}/lib/user.sh"



# 主函数
main() {
    case "$1" in
        # 系统管理命令
        install)
            install
            restart_service
            ;;
        uninstall)
            uninstall
            ;;
        upgrade)
            upgrade_shadowsocks
            ;;
            
        # 服务管理命令
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            status_service
            ;;
        logs)
            show_logs
            ;;
            
        # 用户管理命令
        add)
            add_user "$2"
            restart_service
            ;;
        del)
            del_user "$2"
            restart_service
            ;;
        list)
            list_users
            ;;
        query)
            query_user "$2"
            ;;
            
        # 配置管理命令
        backup)
            backup_config
            ;;
        restore)
            restore_config "$2"
            ;;
        config)
            show_config
            ;;
            
        *)
            echo "用法: $0 <command> [args]"
            echo
            echo "系统管理命令:"
            echo "  install     安装服务"
            echo "  uninstall   卸载服务"
            echo "  upgrade     升级服务"
            echo
            echo "服务管理命令:"
            echo "  start       启动服务"
            echo "  stop        停止服务"
            echo "  restart     重启服务"
            echo "  status      查看服务状态"
            echo "  logs        查看服务日志"
            echo
            echo "用户管理命令:"
            echo "  add         添加用户"
            echo "  del         删除用户"
            echo "  list        列出所有用户"
            echo "  query       查询用户信息"
            echo
            echo "配置管理命令:"
            echo "  sync        同步配置文件"
            echo "  backup      备份配置"
            echo "  restore     还原配置"
            echo "  config      查看当前配置"
            exit 1
            ;;
    esac
}

main "$@"

# 升级服务
upgrade_shadowsocks() {
    check_root
    echo "🔄 正在检查更新..."
    local current_version=$(${SS_BIN} --version 2>/dev/null | awk '{print $2}')
    local latest_version=$(get_latest_version)
    
    if [ "$current_version" = "$latest_version" ]; then
        echo "✅ 当前已是最新版本：${current_version}"
        return 0
    fi
    
    echo "📦 发现新版本：${latest_version}"
    echo "当前版本：${current_version}"
    
    read -p "是否升级？(y/N) " confirm
    if [ "$confirm" != "y" ]; then
        echo "❌ 已取消升级"
        return 1
    fi
    
    install_from_binary
    restart_service
    echo "✅ 升级完成"
}

# 服务管理函数
start_service() {
    check_root
    echo "🚀 启动服务..."
    systemctl start ${SERVICE_NAME}
    echo "✅ 服务已启动"
}

stop_service() {
    check_root
    echo "🛑 停止服务..."
    systemctl stop ${SERVICE_NAME}
    echo "✅ 服务已停止"
}

restart_service() {
    check_root
    echo "🔄 重启服务..."
    systemctl restart ${SERVICE_NAME}
    echo "✅ 服务已重启"
}

status_service() {
    check_root
    echo "📊 服务状态："
    systemctl status ${SERVICE_NAME}
}

show_logs() {
    check_root
    echo "📜 服务日志："
    journalctl -u ${SERVICE_NAME} -n 100 --no-pager
}

# 配置管理函数
backup_config() {
    check_root
    local backup_time=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/config_${backup_time}.tar.gz"
    
    mkdir -p "${BACKUP_DIR}"
    tar -czf "${backup_file}" -C "$(dirname ${SS_BASE_PATH})" "$(basename ${SS_BASE_PATH})"
    echo "✅ 配置已备份至：${backup_file}"
}

restore_config() {
    check_root
    local backup_file="$1"
    
    if [ -z "${backup_file}" ]; then
        echo "❌ 请指定备份文件"
        return 1
    fi
    
    if [ ! -f "${backup_file}" ]; then
        echo "❌ 备份文件不存在：${backup_file}"
        return 1
    fi
    
    stop_service
    tar -xzf "${backup_file}" -C "$(dirname ${SS_BASE_PATH})"
    start_service
    echo "✅ 配置已还原"
}

show_config() {
    check_root
    if [ -f "${CONFIG_PATH}" ]; then
        echo "📄 当前配置："
        cat "${CONFIG_PATH}" | jq '.'
    else
        echo "❌ 配置文件不存在"
    fi
}