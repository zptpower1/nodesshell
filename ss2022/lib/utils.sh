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
    local version
    version=$(curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        echo "v1.15.3"
        return 1
    fi
    echo "$version"
    return 0
}

# 获取下载URL
get_download_url() {
    local version=$(get_latest_version)
    local status=$?
    local download_url
    
    if [ $status -ne 0 ]; then
        echo >&2 "⚠️ 获取版本号失败，使用默认版本：${version}"
    else
        echo >&2 "✅ 获取到最新版本：${version}"
    fi
    
    download_url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/shadowsocks-${version}.x86_64-unknown-linux-gnu.tar.xz"
    echo "${download_url}"
}

# 创建软链接
create_symlinks() {
    echo "🔗 正在创建软链接..."
    
    if [ -d "${SS_BASE_PATH}" ]; then
        ln -sf "${SS_BASE_PATH}" "${SCRIPT_DIR}/configs"
        echo "✅ 软链接 configs 创建成功"
    else
        echo "⚠️ 目标路径 ${SS_BASE_PATH} 不存在，无法创建软链接"
    fi
    
    if [ -d "${LOG_DIR}" ]; then
        ln -sf "${LOG_DIR}" "${SCRIPT_DIR}/logs"
        echo "✅ 软链接 logs 创建成功"
    else
        echo "⚠️ 目标路径 ${LOG_DIR} 不存在，无法创建软链接"
    fi
}