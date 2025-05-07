#!/bin/bash

# 全局变量
SING_BASE_PATH="/usr/local/etc/sing-box"
CONFIG_PATH="${SING_BASE_PATH}/config.json"
BASE_CONFIG_PATH="${SING_BASE_PATH}/base_config.json"
USERS_PATH="${SING_BASE_PATH}/users.json"
BACKUP_DIR="${SING_BASE_PATH}/backup"
LOG_DIR="/var/log/sing-box"
LOG_PATH="$LOG_DIR/sing-box.log"
SING_BIN="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="$SCRIPT_DIR/.env"

# 默认配置
# SERVER_PORT=7388
# SERVER_METHOD="2022-blake3-aes-128-gcm"

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

# 生成密钥
generate_key() {
    local method="$1"
    local key_length

    case "$method" in
        "2022-blake3-aes-128-gcm")
            key_length=16
            ;;
        "2022-blake3-aes-256-gcm" | "2022-blake3-chacha20-poly1305")
            key_length=32
            ;;
        *)
            echo "✅ 加密方法: $method，默认使用 UUID 生成密码"
            uuidgen | tr -d '-' | head -c 32
            return 0
            ;;
    esac

    # openssl rand -base64 "$key_length" | head -c "$((key_length * 2))"
    $SING_BIN generate rand $key_length --base64
}

# 生成随机端口并检查占用
generate_random_port() {
    local port
    while true; do
        port=$((RANDOM % 1000 + 50000))  # 生成50000到51000之间的随机端口
        if ! lsof -i:"$port" &>/dev/null; then
            if ! jq -e ".inbounds[] | select(.listen_port == $port)" "$CONFIG_PATH" &>/dev/null; then
                echo "✅ 端口可用: $port"
                break
            else
                echo "⚠️ 配置文件中已存在端口: $port"
            fi
        else
            echo "⚠️ 端口已被占用: $port"
        fi
    done
    echo "$port"  # 通过 echo 返回端口号
}

# 配置防火墙规则
allow_firewall() {
    echo "🛡️ 配置防火墙规则..."
    if command -v ufw >/dev/null 2>&1; then
        echo "使用 ufw 配置防火墙规则..."
        ufw allow "${SERVER_PORT}"/tcp
        ufw allow "${SERVER_PORT}"/udp
    else
        echo "ufw 不可用，使用 iptables 配置防火墙规则..."
        iptables -C INPUT -p tcp --dport "${SERVER_PORT}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "${SERVER_PORT}" -j ACCEPT
        iptables -C INPUT -p udp --dport "${SERVER_PORT}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport "${SERVER_PORT}" -j ACCEPT
    fi
}