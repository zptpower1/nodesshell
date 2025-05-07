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
    local port="$2"
    local method="$3"
    
    # 设置默认值
    if [ -z "$port" ]; then
        read -p "请输入端口号 [默认: ${DEFAULT_PORT}]: " port
        port=${port:-${DEFAULT_PORT}}
    fi
    
    if [ -z "$method" ]; then
        echo "可用的加密方式:"
        echo "1) 2022-blake3-aes-128-gcm (默认)"
        echo "2) 2022-blake3-aes-256-gcm"
        echo "3) 2022-blake3-chacha20-poly1305"
        read -p "请选择加密方式 [1-3]: " method_choice
        
        case $method_choice in
            2) method="2022-blake3-aes-256-gcm";;
            3) method="2022-blake3-chacha20-poly1305";;
            *) method="${DEFAULT_METHOD}";;
        esac
    fi
    
    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "❌ 无效的端口号: ${port}"
        return 1
    fi
    
    # 设置环境变量
    export DEFAULT_PORT="$port"
    export DEFAULT_METHOD="$method"
    
    # 继续安装流程
    install_sing_box
    create_config "$force"
    add_user "admin"
    sync_config
    setup_service
    check_service
    
    # 创建配置目录软链接
    if [ ! -L "$SCRIPT_DIR/configs" ]; then
        ln -s "$SING_BASE_PATH" "$SCRIPT_DIR/configs"
        echo "✅ 创建配置目录软链接: $SING_BASE_PATH -> $SCRIPT_DIR/configs"
    fi
    
    # 创建日志目录软链接
    if [ ! -L "$SCRIPT_DIR/logs" ]; then
        ln -s "${LOG_DIR}" "$SCRIPT_DIR/logs" 
        echo "✅ 创建日志目录软链接: $LOG_DIR -> $SCRIPT_DIR/logs"
    fi
    
    # 显示安装信息
    echo
    echo "✅ 安装完成！"
    echo "-------------------------------------------"
    echo "端口: ${port}"
    echo "加密方式: ${method}"
    echo "配置目录: ${SCRIPT_DIR}/configs"
    echo "日志目录: ${SCRIPT_DIR}/logs"
    echo "-------------------------------------------"
}

# 主函数
main() {
    case "$1" in
        # 安装命令
        install)
            base_check
            if [ "$2" = "-f" ]; then
                shift  # 移除 -f 参数
                install_ss2022_multiuser "force" "$2" "$3"
            else
                install_ss2022_multiuser "" "$2" "$3"
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