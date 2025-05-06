#!/bin/bash
#通用工具函数

# 通用变量
SSBASE_PATH="/usr/local/etc/shadowsocks"
CONFIG_PATH="$SSBASE_PATH/config.json"
USERS_PATH="$SSBASE_PATH/users.json"
BACKUP_DIR="$SSBASE_PATH/backup"
LOG_DIR="/var/log/shadowsocks"
SS_BIN="/usr/bin/ss-server"
SERVICE_NAME="shadowsocks"
SERVICE_FILE="/etc/systemd/system/shadowsocks.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# 检查root权限
function check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本需要以 root 权限运行，请使用 sudo 或切换到 root 用户。"
    exit 1
  fi
}

# 确保shadowsocks用户存在
function ensure_ss_user() {
  if ! getent group shadowsocks >/dev/null; then
    echo "📌 创建 shadowsocks 组..."
    groupadd -r shadowsocks || {
      echo "⚠️ 无法创建 shadowsocks 组，使用 nobody 组作为回退。"
      return 1
    }
  fi
  if ! id shadowsocks >/dev/null 2>&1; then
    echo "📌 创建 shadowsocks 用户..."
    useradd -r -g shadowsocks -s /sbin/nologin -M shadowsocks || {
      echo "⚠️ 无法创建 shadowsocks 用户，使用 nobody 用户作为回退。"
      return 1
    }
  fi
  echo "✅ shadowsocks 用户和组已准备就绪。"
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