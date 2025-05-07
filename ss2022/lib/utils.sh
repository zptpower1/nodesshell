#!/bin/bash

# 全局变量
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
    
    if [ -d "${SS_BASE_PATH}" ]; then
        ln -sf "${SS_BASE_PATH}" "${SCRIPT_DIR}/ss2022_config"
        echo "✅ 软链接 ss2022_config 创建成功"
    else
        echo "⚠️ 目标路径 ${SS_BASE_PATH} 不存在，无法创建软链接"
    fi
    
    if [ -d "${LOG_DIR}" ]; then
        ln -sf "${LOG_DIR}" "${SCRIPT_DIR}/ss2022_logs"
        echo "✅ 软链接 ss2022_logs 创建成功"
    else
        echo "⚠️ 目标路径 ${LOG_DIR} 不存在，无法创建软链接"
    fi
}