#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 加载所有模块
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/install.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/service.sh"
source "${SCRIPT_DIR}/lib/user.sh"
source "${SCRIPT_DIR}/lib/setup.sh"
source "${SCRIPT_DIR}/lib/info.sh"

# 检查环境文件
load_env

function base_check() {
    check_root
    check_dependencies

    # 确保配置目录存在
    mkdir -p "${SING_BASE_PATH}"
    # 确保日志目录存在
    if [ ! -d "${LOG_DIR}" ]; then
        mkdir -p "${LOG_DIR}"
        chmod 777 "${LOG_DIR}"
    fi
    
    # 确保 LOG_PATH 文件存在并设置权限
    if [ ! -f "${LOG_PATH}" ]; then
        touch "${LOG_PATH}"
        chmod 666 "${LOG_PATH}"
    fi

    # 确保用于配置文件已存在
    init_users_config
}

function install_singbox_only() {
    install_sing_box
    create_base_config
}

# 查看日志文件
function view_logs() {
    if [ -f "${LOG_PATH}" ]; then
        echo "📜 查看日志文件：${LOG_PATH}"
        tail -50f "${LOG_PATH}"
    else
        echo "⚠️ 日志文件不存在：${LOG_PATH}"
    fi
}

# 主函数
main() {
    case "$1" in
        # 安装命令
        install)
            base_check
            install_singbox_only "$2"
            ;;
            
        # 设置协议服务命令
        setup)
            setup_service
            ;;
            
        # 升级命令
        upgrade)
            base_check
            upgrade_sing_box
            ;;
            
        # 卸载命令
        uninstall)
            uninstall_sing_box
            ;;
         # 用户管理命令
        add)
            add_user "$2"
            restart_service
            ;;
        del)
            delete_user "$2"
            restart_service
            ;;
        list)
            list_users
            ;;
        query)
            query_user "$2"
            ;;
            
        # 服务管理命令
        start)
            start_service
            ;;
        restart)
            restart_service
            ;;
        stop)
            stop_service
            ;;
        disable)
            disable_service
            ;;
        status)
            status_service
            ;;
        check)
            check_service
            ;;

        # 配置管理命令
        sync)
            sync_config
            ;;
        backup)
            backup_config
            ;;
        restore)
            restore_config "$2"
            ;;
        config)
            show_config
            ;;
        checkc)
            check_config
            ;;
            
        logs)
            view_logs
            ;;
        *)
            echo "用法: $0 <command> [args]"
            echo
            echo "系统管理命令:"
            echo "  install     安装服务[自动安装ss2022协议]"
            echo "    -f       强制重新创建配置文件"
            echo "    [port]   指定端口号 (1-65535)"
            echo "    [method] 指定加密方式:"
            echo "            - 2022-blake3-aes-128-gcm (默认)"
            echo "            - 2022-blake3-aes-256-gcm"
            echo "            - 2022-blake3-chacha20-poly1305"
            echo "  upgrade     升级服务"
            echo "  uninstall   卸载服务"
            echo
            echo "用户管理命令:"
            echo "  add         添加用户"
            echo "  del         删除用户"
            echo "  list        列出所有用户"
            echo "  query       查询用户配置"
            echo
            echo "服务管理命令:"
            echo "  start       启动服务"
            echo "  restart     重启服务"
            echo "  stop        停止服务"
            echo "  disable     禁用服务"
            echo "  status      查看服务状态"
            echo "  check       检查服务运行状态"
            echo
            echo "配置管理命令:"
            echo "  sync        同步配置文件"
            echo "  backup      备份配置"
            echo "  restore     还原配置"
            echo "  config      查看当前配置"
            echo "  checkc 检查配置文件"
            echo
            echo "日志管理命令:"
            echo "  logs        查看日志文件"
            exit 1
            ;;
    esac
}

# 调用主函数
main "$@"