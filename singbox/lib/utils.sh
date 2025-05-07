#!/bin/bash

# 全局变量
SING_BASE_PATH="/usr/local/etc/sing-box"
CONFIG_PATH="${SING_BASE_PATH}/config.json"
BASE_CONFIG_PATH="${SB_BASE_PATH}/base_config.json"
USERS_PATH="${SING_BASE_PATH}/users.json"
BACKUP_DIR="${SING_BASE_PATH}/backup"
LOG_DIR="/var/log/sing-box"
SING_BIN="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 默认配置
DEFAULT_PORT=7388
DEFAULT_METHOD="2022-blake3-aes-128-gcm"

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


# 检查服务状态
check_service() {
    echo "🔍 Sing-box 服务状态："
    if pgrep -x "sing-box" > /dev/null; then
        echo "✅ 服务正在运行"
        echo
        echo "📊 进程信息："
        ps aux | grep sing-box | grep -v grep
        echo
        echo "🔌 监听端口："
        lsof -i -P -n | grep sing-box
        echo
        echo "📈 资源使用："
        top -b -n 1 | grep sing-box
        echo
        echo "📜 最近日志："
        if [ -f "${LOG_DIR}/sing-box.log" ]; then
            tail -n 10 "${LOG_DIR}/sing-box.log"
        else
            echo "❌ 日志文件不存在"
        fi
    else
        echo "❌ 服务未运行"
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