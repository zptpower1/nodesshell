#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 加载所有模块
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/install.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/service.sh"
source "${SCRIPT_DIR}/lib/user.sh"

# 检查环境文件
load_env

function base_check() {
    check_root
    check_dependencies
}

function install_ss2022_multiuser() {
    local force="$1"
    install_sing_box
    create_config "$force"
    add_user "admin"
    sync_config
    setup_service
    check_service
    # generate_client_configs
}

# 主函数
main() {
    case "$1" in
        # 安装命令
        install)
            base_check
            if [ "$2" = "-f" ]; then
                install_ss2022_multiuser "force"
            else
                install_ss2022_multiuser
            fi
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
            
        *)
            echo "用法: $0 <command> [args]"
            echo
            echo "系统管理命令:"
            echo "  install     安装服务[自动安装ss2022协议]"
            echo "    -f       强制重新创建配置文件"
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
            exit 1
            ;;
    esac
}

# 调用主函数
main "$@"