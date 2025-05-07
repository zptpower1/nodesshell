#!/bin/bash

# 全局变量
SING_BASE_PATH="/usr/local/etc/sing-box"
CONFIG_PATH="${SING_BASE_PATH}/config.json"
USERS_PATH="${SING_BASE_PATH}/users.json"
BACKUP_DIR="${SING_BASE_PATH}/backup"
LOG_DIR="/var/log/sing-box"
SING_BIN="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 默认配置
DEFAULT_PORT=7388
DEFAULT_METHOD="2022-blake3-aes-256-gcm"

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 此脚本需要以 root 权限运行"
        exit 1
    fi
}

# 获取服务器IP
get_server_ip() {
    curl -s https://api.ipify.org || ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1
}

# 检查依赖
check_dependencies() {
    for cmd in wget curl jq; do
        if ! command -v $cmd &> /dev/null; then
            echo "📦 安装依赖 $cmd..."
            apt-get update && apt-get install -y $cmd || \
            yum install -y $cmd || \
            apk add $cmd || \
            pacman -S $cmd
        fi
    done
}