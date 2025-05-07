#!/bin/bash

# 全局变量
SS_BASE_PATH="/usr/local/etc/shadowsocks2022"
CONFIG_PATH="${SS_BASE_PATH}/config.json"
BASE_CONFIG_PATH="${SS_BASE_PATH}/base_config.json"
USERS_PATH="${SS_BASE_PATH}/users.json"
BACKUP_DIR="${SS_BASE_PATH}/backup"
LOG_DIR="/var/log/shadowsocks2022"
SS_BIN="/usr/local/bin/ssserver"
SERVICE_NAME="shadowsocks2022"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
MAX_RESULTS=10

# 检查root权限
function check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本需要以 root 权限运行，请使用 sudo 或切换到 root 用户。"
    exit 1
  fi
}

# 创建软链接
function create_symlinks() {
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

# 加载环境变量
function load_env() {
  #echo "🔍 调试：ENV_FILE 路径为 $ENV_FILE"
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "🔍 调试：.env 文件不存在"
    echo "❌ 错误：未找到 .env 文件，该文件必须存在于脚本同级目录。"
    echo "请创建 .env 文件并配置以下内容："
    echo "NODENAME=your-node-name"
    echo "NODEDOMAIN=your-domain.com (可选)"
    exit 1
  fi

  #echo "🔍 调试：.env 文件存在，准备读取"
  source "$ENV_FILE"
  #echo "🔍 调试：.env 文件内容："
  #cat "$ENV_FILE"

  if [[ -z "$NODENAME" ]]; then
    echo "🔍 调试：NODENAME 变量为空"
    echo "❌ 错误：.env 文件中必须设置 NODENAME 变量。"
    exit 1
  fi

  #echo "📌 从 .env 文件读取节点名称: $NODENAME"
  if [[ -n "$NODEDOMAIN" ]]; then
    echo "📌 从 .env 文件读取节点域名: $NODEDOMAIN"
  fi
}