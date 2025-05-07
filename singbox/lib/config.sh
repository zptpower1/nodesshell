#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"


# 创建基础配置
create_config() {
    local force="$1"
    
    # 检查目录是否存在，不存在则创建
    if [ ! -d "${SING_BASE_PATH}" ]; then
        mkdir -p "${SING_BASE_PATH}"
    fi
    
    # 检查基础配置文件是否已存在
    if [ -f "${BASE_CONFIG_PATH}" ] && [ "$force" != "force" ]; then
        echo "✅ 基础配置文件已存在，跳过创建"
        return 0
    fi
    
    # 生成32字节(64个十六进制字符)的主密钥
    local server_key=$(openssl rand -base64 32 | head -c 44)
    #local server_key=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p -c 64)
    
    # 创建基础配置文件
    cat > "${BASE_CONFIG_PATH}" << EOF
{
  "log": {
    "level": "info",
    "output": "${LOG_PATH}",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${SERVER_PORT},
      "method": "${SERVER_METHOD}",
      "password": "${server_key}"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    echo "✅ 基础配置文件创建成功"
}

# 生成客户端配置
generate_client_configs() {
    local config_dir="/tmp/ss2022_configs"
    mkdir -p $config_dir
    
    USERS=$(jq -r '.inbounds[0].users[] | .name + ":" + .password' "${CONFIG_PATH}")
    while IFS=: read -r username password; do
        SS_URL="ss://${SERVER_METHOD}:${password}@$(get_server_ip):${SERVER_PORT}#${username}"
        echo "用户: ${username}" >> "${config_dir}/client_configs.txt"
        echo "Shadowsocks URL: ${SS_URL}" >> "${config_dir}/client_configs.txt"
        echo "-------------------" >> "${config_dir}/client_configs.txt"
    done <<< "$USERS"
    
    echo "✅ 客户端配置已保存至: ${config_dir}/client_configs.txt"
}

# 同步配置
sync_config() {
    if [ ! -f "${BASE_CONFIG_PATH}" ] || [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 基础配置文件或用户配置文件不存在"
        return 1
    fi
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 合并基础配置和用户配置
    jq -s '.[0] * {"inbounds":[.[0].inbounds[0] * {"users":.[1].users}]}' \
        "${BASE_CONFIG_PATH}" "${USERS_PATH}" > "${temp_file}"
    
    # 检查合并后的配置文件是否有效
    if ! jq '.' "${temp_file}" >/dev/null 2>&1; then
        echo "❌ 配置文件格式无效"
        rm -f "${temp_file}"
        return 1
    fi
    
    # 更新配置文件
    mv "${temp_file}" "${CONFIG_PATH}"
    chmod 644 "${CONFIG_PATH}"
    
    echo "✅ 配置同步完成"
}

# 备份配置
backup_config() {
    check_root
    local backup_time=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/config_${backup_time}.tar.gz"
    
    mkdir -p "${BACKUP_DIR}"
    tar -czf "${backup_file}" -C "$(dirname ${SING_BASE_PATH})" "$(basename ${SING_BASE_PATH})"
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
    tar -xzf "${backup_file}" -C "$(dirname ${SING_BASE_PATH})"
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

# 检查配置文件
check_config() {
    if [ ! -f "${CONFIG_PATH}" ]; then
        echo "❌ 配置文件不存在"
        return 1
    fi

    # 使用 sing-box 检查配置文件
    if ! $SING_BIN check -c "${CONFIG_PATH}" >/dev/null 2>&1; then
        echo "❌ 配置文件格式无效"
        return 1
    fi

    echo "✅ 配置文件有效"
}