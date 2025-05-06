#!/bin/bash
#通用工具函数

# 通用变量
CONFIG_PATH="/usr/local/etc/shadowsocks/config.json"
USERS_PATH="/usr/local/etc/shadowsocks/users.json"
BACKUP_DIR="/usr/local/etc/shadowsocks/backup"
LOG_DIR="/var/log/shadowsocks"
SS_BIN="/usr/bin/ss-server"
SERVICE_NAME="shadowsocks"
SERVICE_FILE="/etc/systemd/system/shadowsocks.service"
SCRIPT_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
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
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    if [[ -n "$NODENAME" ]]; then
      echo "📌 从 .env 文件读取节点名称: $NODENAME"
    fi
    if [[ -n "$NODEDOMAIN" ]]; then
      echo "📌 从 .env 文件读取节点域名: $NODEDOMAIN"
    fi
  fi
  if [[ -z "$NODENAME" ]]; then
    echo "⚠️ 未找到 NODENAME 设置。"
    while true; do
      read -p "请输入节点名称（不能为空）: " NODENAME
      if [[ -n "$NODENAME" ]]; then
        echo "📌 设置节点名称: $NODENAME"
        if [[ -n "$NODEDOMAIN" ]]; then
          echo "NODENAME=$NODENAME" > "$ENV_FILE"
          echo "NODEDOMAIN=$NODEDOMAIN" >> "$ENV_FILE"
        else
          echo "NODENAME=$NODENAME" > "$ENV_FILE"
        fi
        break
      else
        echo "❌ 节点名称不能为空，请重新输入。"
      fi
    done
  fi
}