#!/bin/bash

# 全局变量
SCRIPT_DIR="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
LOGS_DIR="${SCRIPT_DIR}/logs"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# 配置文件优先级逻辑
if [ -f "/etc/sing-box/config.json" ]; then
    CONFIG_PATH="/etc/sing-box/config.json"
else
    CONFIG_PATH="${CONFIGS_DIR}/config.json"
fi

BASE_CONFIG_PATH="${CONFIGS_DIR}/base_config.json"
USERS_PATH="${CONFIGS_DIR}/users.json"
LOG_PATH="${LOGS_DIR}/sing-box.log"

SING_BIN="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="${SCRIPT_DIR}/.env"

# 读取系统 ID（ubuntu/debian 等）
get_os_id() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    fi
}

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
    local os_id=$(get_os_id)
    local missing=()
    # 统一检测依赖，并包含 tar（用于解压）
    for cmd in wget curl jq tar; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "📦 安装依赖: ${missing[*]}..."
        if [ "$os_id" = "ubuntu" ] || [ "$os_id" = "debian" ]; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y "${missing[@]}"
        else
            # 其他发行版的兜底处理
            apt-get update && apt-get install -y "${missing[@]}" || \
            yum install -y "${missing[@]}" || \
            apk add "${missing[@]}" || \
            pacman -S --noconfirm "${missing[@]}"
        fi
    fi
}

# 加载环境变量
function load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "🔍 调试：.env 文件不存在，正在创建..."
        echo "NODENAME=PRV-$(hostname)" > "$ENV_FILE"
        echo "NODEDOMAIN=" >> "$ENV_FILE"
        echo "SHOW_QRCODE=false" >> "$ENV_FILE"
        echo "✅ .env 文件已创建，NODENAME 设置为 PRV-$(hostname)"
    else
        source "$ENV_FILE"
        if [[ -z "$NODENAME" ]]; then
            echo "🔍 调试：NODENAME 变量为空"
            echo "❌ 错误：.env 文件中必须设置 NODENAME 变量。"
            exit 1
        fi
        if [[ -n "$NODEDOMAIN" ]]; then
            echo "📌 从 .env 文件读取节点域名: $NODEDOMAIN"
        fi
    fi
}

# 生成 UUID
generate_uuid() {
    if [ -x "$SING_BIN" ]; then
        "$SING_BIN" generate uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback to random string
        cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1 | sed -e 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/'
    fi
}

# 生成密钥
generate_key() {
    local method="$1"

    case "$method" in
        "2022-blake3-aes-128-gcm")
            $SING_BIN generate rand 16 --base64
            ;;
        "2022-blake3-aes-256-gcm" | "2022-blake3-chacha20-poly1305")
            $SING_BIN generate rand 32 --base64
            ;;
        "short-id")
            $SING_BIN generate rand 3 --hex
            ;;
        "reality-keypair")
            $SING_BIN generate reality-keypair
            ;;
        *)
            echo "✅ 加密方法: $method，默认使用 UUID 生成密码"
            generate_uuid
            return 0
            ;;
    esac

    # openssl rand -base64 "$key_length" | head -c "$((key_length * 2))"
    # $SING_BIN generate rand $key_length --base64
}

# 生成随机端口并检查占用
generate_random_port() {
    local port
    while true; do
        port=$((RANDOM % 1000 + 50000))  # 生成50000到51000之间的随机端口
        if ! lsof -i:"$port" &>/dev/null; then
            if ! jq -e ".inbounds[] | select(.listen_port == $port)" "$CONFIG_PATH" &>/dev/null; then
                break
            fi
        fi
    done
    echo "$port"  # 通过 echo 返回端口号
}

# 配置防火墙规则-配置文件自适应
allow_firewall() {
     # 配置防火墙规则
    if [ -f "${CONFIG_PATH}" ]; then
        echo "🛡️ 开始同步防火墙规则..."
        local config_ports=$(jq -r '.inbounds[].listen_port' "${CONFIG_PATH}")
        
        # 1. 开放配置中的端口
        for port in $config_ports; do
            allow_firewall_port $port
        done

        # 2. 清理不再使用的端口 (仅针对带有 sing-box 标记的端口)
        if command -v ufw >/dev/null 2>&1; then
             # 获取所有带有 'sing-box' 注释的已开放端口
            local ufw_ports=$(ufw status | grep 'sing-box' | awk '{print $1}' | cut -d'/' -f1 | sort -u)
            
            for u_port in $ufw_ports; do
                local keep=false
                for c_port in $config_ports; do
                    if [ "$u_port" == "$c_port" ]; then
                        keep=true
                        break
                    fi
                done
                
                if [ "$keep" = false ]; then
                    echo "🗑️ 端口 $u_port 已不再使用，正在移除..."
                    delete_firewall_port $u_port
                fi
            done
        fi
        
        echo "🛡️ 防火墙规则同步完成..."
    fi
}

# 配置防火墙-单端口
allow_firewall_port() {
    local port="$1"
    
    if [ -z "$port" ]; then
        echo "❌ 请提供端口号"
        return 1
    fi
    
    if command -v ufw >/dev/null 2>&1; then
        # 检查端口是否已开放且有正确备注
        if ! ufw status | grep -q "${port}.*sing-box"; then
            echo "   使用 ufw 配置防火墙规则 (端口: ${port})..."
            ufw allow "${port}" comment 'sing-box'
        else
             echo "   端口 ${port} 已开放 (跳过)"
        fi
    else
        echo "   使用 iptables 配置防火墙规则 (端口: ${port})..."
        for proto in tcp udp; do
            iptables -C INPUT -p $proto --dport "${port}" -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p $proto --dport "${port}" -j ACCEPT
        done
    fi
    echo "✅ 端口 ${port} 已开放"
}

# 移除防火墙规则-配置文件自适应
delete_firewall() {
    # 移除防火墙规则
    if [ -f "${CONFIG_PATH}" ]; then
        echo "🛡️ 开始批量移除防火墙规则..."
        local ports=$(jq -r '.inbounds[].listen_port' "${CONFIG_PATH}")
        for port in $ports; do
            delete_firewall_port $port
        done
        echo "🛡️ 批量移除防火墙规则已完成..."
    fi
}

# 移除防火墙-单端口
delete_firewall_port() {
    local port="$1"
    
    if [ -z "$port" ]; then
        echo "❌ 请提供端口号"
        return 1
    fi
    
    if command -v ufw >/dev/null 2>&1; then
        echo "   使用 ufw 移除防火墙规则 (端口: ${port})..."
        # 使用正则表达式匹配端口和注释
        ufw status numbered | grep "${port}.*sing-box" | awk '{print $1}' | sed 's/\[//;s/\]//' | sort -rn | while read rule_num; do
             yes | ufw delete $rule_num
        done
        # 兜底删除（如果没有注释的旧规则）
        ufw delete allow "${port}" >/dev/null 2>&1 || true
    else
        echo "   使用 iptables 移除防火墙规则 (端口: ${port})..."
        for proto in tcp udp; do
            iptables -D INPUT -p $proto --dport "${port}" -j ACCEPT 2>/dev/null || true
        done
    fi
    echo "✅ 端口 ${port} 已关闭"
}

# 初始化目录结构
init_directories() {
    echo "📂 初始化目录结构..."
    
    # 创建配置目录
    echo "   创建配置目录: ${CONFIGS_DIR}"
    mkdir -p "${CONFIGS_DIR}"
    
    echo "   创建备份目录: ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
    
    # 创建日志目录
    echo "   创建日志目录: ${LOGS_DIR}"
    mkdir -p "${LOGS_DIR}"
    
    # 设置适当的权限
    echo "🔒 设置目录权限..."
    chmod 755 "${CONFIGS_DIR}" "${LOGS_DIR}"
    chmod 700 "${BACKUP_DIR}"  # 备份目录设置更严格的权限
    
    echo "✅ 目录结构初始化完成"
}