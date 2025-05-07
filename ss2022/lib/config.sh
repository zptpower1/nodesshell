#!/bin/bash

source "$(dirname "$0")/utils.sh"

# 设置配置文件
setup_config() {
    mkdir -p "${SS_BASE_PATH}"
    local uuid=$(uuidgen)
    cat > "${CONFIG_PATH}" << EOF
{
    "server": ["0.0.0.0", "::"],
    "mode": "tcp_and_udp",
    "timeout": 300,
    "method": "2022-blake3-aes-128-gcm",
    "port_password": {
        "8388": "${uuid}"
    }
}
EOF
    echo "✅ 配置文件创建成功"
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