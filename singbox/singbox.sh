#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 加载所有模块
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/install.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/config_protocol.sh"
source "${SCRIPT_DIR}/lib/service.sh"
source "${SCRIPT_DIR}/lib/user.sh"
source "${SCRIPT_DIR}/lib/info.sh"

# 检查环境文件
load_env

function base_check() {
    check_root
    check_dependencies

    #初始化目录
    init_directories

    # 确保用于配置文件已存在
    init_users_config
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

# 创建命令软链接
create_command_links() {
    echo "🔗 创建命令软链接..."
    local script_path=$(realpath "${SCRIPT_DIR}/singbox.sh")
    for cmd in config service user tail; do
        local link_path="${SCRIPT_DIR}/${cmd}"
        if [ -L "${link_path}" ]; then
            rm -f "${link_path}"
        fi
        ln -sf "${script_path}" "${link_path}"
        echo "   创建软链接: ${cmd}"
    done
}

# 删除命令软链接
remove_command_links() {
    echo "🔗 删除命令软链接..."
    for cmd in config service user tail; do  # 将 logs 改为 log
        local link_path="${SCRIPT_DIR}/${cmd}"
        if [ -L "${link_path}" ]; then
            rm -f "${link_path}"
            echo "   删除软链接: ${cmd}"
        fi
    done
}

# 主函数
main() {
    # 获取脚本名称（用于支持软链接调用）
    local script_name=$(basename "$0")
    script_name="${script_name%.*}"  # 移除扩展名
    
    # 根据脚本名称直接执行对应模块
    case "$script_name" in
        "config")
            # 直接执行配置管理命令
            main_with_args "config" "$@"
            ;;
        "service")
            # 直接执行服务管理命令
            main_with_args "service" "$@"
            ;;
        "user")
            # 直接执行用户管理命令
            main_with_args "user" "$@"
            ;;
        "log")  # 将 logs 改为 log
            # 直接执行日志查看命令
            view_logs
            ;;
        *)
            # 原有的命令处理逻辑
            main_with_args "$@"
            ;;
    esac
}

# 处理命令参数
main_with_args() {
    local command="$1"
    local subcommand="$2"
    local arg="$3"
    
    case "$command" in
        # 系统管理命令
        install)
            base_check
            install_sing_box
            create_command_links  # 安装时创建软链接
            ;;
        upgrade)
            base_check
            upgrade_sing_box
            ;;
        uninstall)
            remove_command_links  # 卸载时删除软链接
            uninstall_sing_box
            ;;
            
        # 用户管理命令
        user)
            case "$subcommand" in
                add)
                    user_add
                    service_restart
                    ;;
                del|delete|remove)
                    user_del "$arg"
                    service_restart
                    ;;
                list|ls)
                    user_list
                    ;;
                query|show)
                    user_query
                    ;;
                reset)
                    user_reset "$arg"
                    service_restart
                    ;;
                enable)
                    user_set_actived "$arg" "true"
                    service_restart
                    ;;
                disable)
                    user_set_actived "$arg" "false"
                    service_restart
                    ;;
                migrate)
                    shift 2  # 移除 user 和 migrate 参数
                    user_migrate "$@"  # 传递剩余的所有参数
                    ;;
                *)
                    echo "用户管理命令用法: $0 user <subcommand> [args]"
                    echo "可用的子命令:"
                    echo "  add              添加用户"
                    echo "  list             列出所有用户"
                    echo "  query            查询用户配置"
                    echo "  reset <username>  重置用户(密码)"
                    echo "  enable <username>     启用用户"
                    echo "  disable <username>    停用用户"
                    echo "  del <username>   删除用户"
                    echo "  migrate <field> [value] [type]  迁移用户数据"
                    echo "    示例:"
                    echo "      migrate actived true boolean  # 添加布尔类型字段"
                    echo "      migrate email \"\" string      # 添加字符串类型字段"
                    echo "      migrate score 0 number       # 添加数字类型字段"
                    exit 1
                    ;;
            esac
            ;;
            
        # 服务管理命令
        service)
            case "$subcommand" in
                start)
                    service_start
                    ;;
                restart)
                    service_restart
                    ;;
                stop)
                    service_stop
                    ;;
                disable)
                    service_disable
                    ;;
                enable)
                    service_enable
                    ;;
                install)
                    service_install
                    ;;
                remove)
                    service_remove
                    ;;
                status)
                    service_status
                    ;;
                check)
                    service_check
                    ;;
                *)
                    echo "服务(systemctl)管理命令用法: $0 service <subcommand>"
                    echo "可用的子命令:"
                    echo "  install   安装系统服务"
                    echo "  remove    卸载系统服务"
                    echo "  start     启动服务"
                    echo "  restart   重启服务"
                    echo "  stop      停止服务"
                    echo "  disable   禁用服务"
                    echo "  enable    启用服务"
                    echo "  status    查看服务状态"
                    echo "  check     检查服务运行状态"
                    exit 1
                    ;;
            esac
            ;;
            
        # 配置管理命令
        config)
            case "$subcommand" in
                sync)
                    config_sync
                    ;;
                backup)
                    config_backup
                    ;;
                restore)
                    config_restore "$arg"
                    ;;
                show)
                    config_show
                    ;;
                check)
                    config_check
                    ;;
                setup)
                    config_protocol_setup
                    ;;
                remove)
                    config_protocol_remove
                    ;;
                *)
                    echo "配置管理命令用法: $0 config <subcommand> [args]"
                    echo "可用的子命令:"
                    echo "  sync           同步配置文件"
                    echo "  backup         备份配置"
                    echo "  restore <file> 还原配置"
                    echo "  show           查看当前配置"
                    echo "  check          检查配置文件"
                    echo "  setup          协议安装"
                    echo "  remove         协议卸载"
                    exit 1
                    ;;
            esac
            ;;
            
        # 日志管理命令
        log|logs|tail)
            view_logs
            ;;
            
        # 帮助信息
        *)
            echo "用法: $0 <command> <subcommand> [args]"
            echo
            echo "系统管理命令:"
            echo "  install     安装服务[自动安装ss2022协议]"
            echo "    -f       强制重新创建配置文件"
            echo "    [port]   指定端口号 (1-65535)"
            echo "    [method] 指定加密方式:"
            echo "            - 2022-blake3-aes-128-gcm (默认)"
            echo "            - 2022-blake3-aes-256-gcm"
            echo "            - 2022-blake3-chacha20-poly1305"
            echo "  upgrade    升级服务"
            echo "  uninstall  卸载服务"
            echo
            echo "用户管理命令:"
            echo "  user add              添加新用户"
            echo "  user del <name>       删除指定用户"
            echo "  user list             列出所有用户"
            echo "  user query            查询用户配置"
            echo "  user reset <name>     重置用户密钥"
            echo "  user enable <name>    启用用户"
            echo "  user disable <name>   禁用用户"
            echo "  user migrate <field> [value] [type]  迁移用户数据"
            echo "    示例:"
            echo "      migrate actived true boolean  # 添加布尔类型字段"
            echo "      migrate email \"\" string      # 添加字符串类型字段"
            echo "      migrate score 0 number       # 添加数字类型字段"
            echo
            echo "服务管理命令:"
            echo "  service install    安装系统服务"
            echo "  service remove     卸载系统服务"
            echo "  service start      启动服务"
            echo "  service restart    重启服务"
            echo "  service stop       停止服务"
            echo "  service disable    禁用服务"
            echo "  service enable     启用服务"
            echo "  service status     查看服务状态"
            echo "  service check      检查服务运行状态"
            echo
            echo "配置管理命令:"
            echo "  config sync           同步用户配置到服务配置"
            echo "  config backup         备份所有配置文件"
            echo "  config restore <file> 从备份文件还原配置"
            echo "  config show           查看当前服务配置"
            echo "  config check          检查配置文件格式"
            echo "  config setup          安装新的协议配置"
            echo "  config remove         卸载协议配置"
            echo
            echo "日志管理命令:"
            echo "  logs                  实时查看最新50行日志"
            exit 1
            ;;
    esac
}

# 调用主函数
main "$@"