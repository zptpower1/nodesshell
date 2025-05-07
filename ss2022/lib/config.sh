#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 设置配置文件
setup_config() {
    mkdir -p "${SS_BASE_PATH}"
    mkdir -p "${LOG_DIR}"
    
    # 让用户选择端口号
    read -p "请输入服务器端口号（默认: 8789）: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-8789}
    echo "📌 使用端口: $SERVER_PORT"
    
    # 让用户选择加密方法
    echo "请选择加密方法："
    echo "1) 2022-blake3-aes-128-gcm [默认]"
    echo "2) 2022-blake3-aes-256-gcm"
    echo "3) 2022-blake3-chacha20-poly1305"
    read -p "请输入选项 [1-3]: " METHOD_OPTION
    case "$METHOD_OPTION" in
        2) METHOD="2022-blake3-aes-256-gcm" ;;
        3) METHOD="2022-blake3-chacha20-poly1305" ;;
        *) METHOD="2022-blake3-aes-128-gcm" ;;
    esac
    echo "📌 使用加密方法: $METHOD"
    
    # 让用户选择 IP 协议支持
    echo "请选择 IP 协议支持："
    echo "1) 仅 IPv4"
    echo "2) 同时支持 IPv4 和 IPv6 [默认]"
    read -p "请输入选项 [1-2]: " IP_VERSION
    case "$IP_VERSION" in
        1) SERVER_IP="\"0.0.0.0\"" ;;
        *) SERVER_IP="\"::\"" ;;
    esac
    echo "📌 IP 协议支持已设置"
    
    # 创建配置文件
    cat > "${BASE_CONFIG_PATH}" << EOF
{
    "server": ${SERVER_IP},
    "server_port": ${SERVER_PORT},
    "mode": "tcp_and_udp",
    "timeout": 300,
    "method": "${METHOD}"
}
EOF
    echo "✅ 基础配置文件创建成功"
    
    # 创建管理员用户
    add_user "admin"
    
    # 设置日志轮替
    cat > /etc/logrotate.d/shadowsocks2022 << EOF
${LOG_DIR}/ss-server.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl restart ${SERVICE_NAME} >/dev/null 2>&1 || true
    endscript
}
EOF
    echo "✅ 日志轮替配置完成"
}

# 备份配置
backup_config() {
    check_root
    local backup_time=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/config_${backup_time}.tar.gz"
    
    mkdir -p "${BACKUP_DIR}"
    tar -czf "${backup_file}" -C "$(dirname ${SS_BASE_PATH})" "$(basename ${SS_BASE_PATH})"
    echo "✅ 配置已备份至：${backup_file}"
}

# 还原配置
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

# 显示配置
show_config() {
    check_root
    if [ -f "${CONFIG_PATH}" ]; then
        echo "📄 当前配置："
        cat "${CONFIG_PATH}" | jq '.'
    else
        echo "❌ 配置文件不存在"
    fi
}

# 同步配置文件
sync_config() {
    if [ ! -f "${BASE_CONFIG_PATH}" ] || [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 基础配置文件或用户配置文件不存在"
        return 1
    fi

    # 创建临时文件
    local temp_config_file=$(mktemp)
    
    # 合并基础配置和用户配置
    jq -s '.[0] * {"users": .[1].users}' "${BASE_CONFIG_PATH}" "${USERS_PATH}" > "${temp_config_file}"
    
    # 检查合并后的配置文件是否有效
    if ! jq '.' "${temp_config_file}" >/dev/null 2>&1; then
        echo "❌ 配置文件格式无效"
        rm -f "${temp_config_file}"
        return 1
    fi
    
    # 备份当前配置
    backup_config
    
    # 更新配置文件
    mv "${temp_config_file}" "${CONFIG_PATH}"
    chmod 644 "${CONFIG_PATH}"
    
    echo "✅ 配置同步完成"
}