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
    install_sing_box
    create_config
    setup_service
    check_service
    generate_client_configs
}

# 主函数
main() {
    case "$1" in
        # 安装命令
        install)
            base_check
            install_ss2022_multiuser
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
            
        *)
            echo "用法: $0 <command> [args]"
            echo
            echo "系统管理命令:"
            echo "  install     安装服务[自动安装ss2022协议]"
            echo "  upgrade     升级服务"
            echo "  uninstall   卸载服务"
            echo
            echo "服务管理命令:"
            echo "  stop        停止服务"
            echo "  disable     禁用服务"
            echo "  status      查看服务状态"
            echo "  check       检查服务运行状态"
            exit 1
            ;;
    esac
}

# 调用主函数
main "$@"