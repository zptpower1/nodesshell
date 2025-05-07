#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SS_BASE_PATH="/usr/local/etc/shadowsocks2022"
CONFIG_PATH="${SS_BASE_PATH}/config.json"
USERS_PATH="${SS_BASE_PATH}/users.json"
BACKUP_DIR="${SS_BASE_PATH}/backup"
LOG_DIR="/var/log/shadowsocks2022"
SERVICE_NAME="shadowsocks2022"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SS_BIN="/usr/local/bin/ssserver"

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "❌ 此脚本需要以 root 权限运行"
        exit 1
    fi
}

# 获取最新版本号
get_latest_version() {
    echo "ℹ️ 正在获取最新版本号..."
    curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# 获取下载URL
get_download_url() {
    local version=$(get_latest_version)
    echo "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/shadowsocks-${version}.x86_64-unknown-linux-gnu.tar.xz"
}

# 创建软链接
create_symlinks() {
    echo "🔗 正在创建软链接..."
    
    # 创建配置目录软链接
    if [ -d "${SS_BASE_PATH}" ]; then
        ln -sf "${SS_BASE_PATH}" "${SCRIPT_DIR}/ss2022_config"
        echo "✅ 软链接 ss2022_config 创建成功"
    else
        echo "⚠️ 目标路径 ${SS_BASE_PATH} 不存在，无法创建软链接"
    fi
    
    # 创建日志目录软链接
    if [ -d "${LOG_DIR}" ]; then
        ln -sf "${LOG_DIR}" "${SCRIPT_DIR}/ss2022_logs"
        echo "✅ 软链接 ss2022_logs 创建成功"
    else
        echo "⚠️ 目标路径 ${LOG_DIR} 不存在，无法创建软链接"
    fi
}

# 安装服务
install() {
    check_root
    echo "📦 开始安装 SS2022..."
    
    # 尝试apt安装
    if command -v apt-get &> /dev/null; then
        echo "ℹ️ 尝试通过 apt 安装 shadowsocks-rust..."
        apt-get update
        if apt-get install -y shadowsocks-rust; then
            echo "✅ 通过apt安装成功"
        else
            echo "📌 apt安装失败，尝试使用预编译二进制包安装..."
            install_from_binary
        fi
    else
        echo "ℹ️ 使用预编译二进制包安装..."
        install_from_binary
    fi
    
    setup_service
    setup_config
    create_symlinks
    echo "✅ 安装完成！"
}

# 从二进制包安装
install_from_binary() {
    local temp_dir="/tmp/ssrust"
    local download_url=$(get_download_url)
    
    mkdir -p "${temp_dir}"
    echo "📥 下载预编译包..."
    wget "${download_url}" -O "${temp_dir}/ss.tar.xz"
    
    echo "📦 解压安装..."
    tar -xf "${temp_dir}/ss.tar.xz" -C "/usr/local/bin/"
    chmod +x "${SS_BIN}"
}

# 设置配置文件
setup_config() {
    mkdir -p "${SS_BASE_PATH}"
    local uuid=$(uuidgen)
    cat > "${CONFIG_PATH}" << EOF
{
    "server": ["0.0.0.0", "::"],
    "mode": "tcp_and_udp",
    "timeout": 300,
    "method": "2022-blake3-aes-128-gcm",
    "port_password": {
        "8388": "${uuid}"
    }
}
EOF
    echo "✅ 配置文件创建成功"
}

# 设置服务
setup_service() {
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Shadowsocks-rust Server Service
After=network.target

[Service]
Type=simple
ExecStart=${SS_BIN} -c ${CONFIG_PATH}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"
    echo "✅ 服务设置完成"
}

# 卸载服务
uninstall() {
    check_root
    echo "⚠️ 即将卸载 SS2022，并删除其所有配置文件和程序。"
    
    # 停止和禁用服务
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    
    # 删除文件和目录
    rm -f "${SERVICE_FILE}" "${CONFIG_PATH}" "${USERS_PATH}" "${SS_BIN}"
    rm -rf "${SS_BASE_PATH}" "${LOG_DIR}"
    
    # 删除软链接
    rm -f "${SCRIPT_DIR}/ss2022_config" "${SCRIPT_DIR}/ss2022_logs"
    
    echo "✅ 卸载完成。"
}

# 用户管理
add_user() {
    check_root
    local username="$1"
    if [ -z "${username}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    local uuid=$(uuidgen)
    mkdir -p "${SS_BASE_PATH}"
    
    if [ ! -f "${USERS_PATH}" ]; then
        echo '{"users":{}}' > "${USERS_PATH}"
    fi
    
    # 使用临时文件来更新JSON
    local temp_file=$(mktemp)
    jq ".users[\"${username}\"] = {\"uuid\": \"${uuid}\"}" "${USERS_PATH}" > "${temp_file}"
    mv "${temp_file}" "${USERS_PATH}"
    
    echo "✅ 用户 ${username} 添加成功，UUID: ${uuid}"
}

del_user() {
    check_root
    local username="$1"
    if [ -z "${username}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    if [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 用户文件不存在"
        return 1
    fi
    
    # 使用临时文件来更新JSON
    local temp_file=$(mktemp)
    jq "del(.users[\"${username}\"])" "${USERS_PATH}" > "${temp_file}"
    mv "${temp_file}" "${USERS_PATH}"
    
    echo "✅ 用户 ${username} 删除成功"
}

list_users() {
    check_root
    if [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 用户文件不存在"
        return 1
    fi
    
    echo "📋 当前用户列表："
    jq -r '.users | to_entries[] | "用户: \(.key), UUID: \(.value.uuid)"' "${USERS_PATH}"
}

query_user() {
    check_root
    local username="$1"
    if [ -z "${username}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    if [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 用户文件不存在"
        return 1
    fi
    
    local user_info=$(jq -r ".users[\"${username}\"].uuid" "${USERS_PATH}")
    if [ "${user_info}" != "null" ]; then
        echo "用户: ${username}, UUID: ${user_info}"
    else
        echo "❌ 用户 ${username} 不存在"
    fi
}

# 获取所有模块
source "${SCRIPT_DIR}/lib/utils.sh"
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
            ;;
        del)
            del_user "$2"
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