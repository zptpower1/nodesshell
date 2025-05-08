#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"


# 创建基础配置
config_create_base() {
    # 检查目录是否存在，不存在则创建
    if [ ! -d "${SING_BASE_PATH}" ]; then
        mkdir -p "${SING_BASE_PATH}"
    fi
    
    # 检查基础配置文件是否已存在
    if [ -f "${BASE_CONFIG_PATH}" ]; then
        echo "✅ 基础配置文件已存在。"
        read -p "是否要覆盖现有配置文件？(n[默认]/y): " choice
        if [ "$choice" != "y" ]; then
            echo "跳过创建"
            return 0
        fi
    fi
    
    # 创建基础配置文件
    cat > "${BASE_CONFIG_PATH}" << EOF
{
  "log": {
    "level": "info",
    "output": "${LOG_PATH}",
    "timestamp": true,
    "disabled": false
  },
  "inbounds": [
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
config_sync() {
    if [ ! -f "${BASE_CONFIG_PATH}" ] || [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 基础配置文件或用户配置文件不存在"
        return 1
    fi
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 定义支持多用户的协议和方法白名单，作为 JSON 对象
    local whitelist='{
        "shadowsocks": "^2022-blake3-aes-.*-gcm$"
    }'
    
    # 合并基础配置和用户配置
    jq --argjson whitelist "${whitelist}" '
        .[0] * {
            "inbounds": (
                .[0].inbounds | map(
                    if .type == "shadowsocks" and (.method | test($whitelist[.type])) then
                        . + { "users": .[1].users }
                    else
                        .
                    end
                )
            )
        }
    ' "${BASE_CONFIG_PATH}" "${USERS_PATH}" > "${temp_file}"
    
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
config_backup() {
    check_root
    local backup_time=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/config_${backup_time}.tar.gz"
    
    mkdir -p "${BACKUP_DIR}"
    tar -czf "${backup_file}" -C "$(dirname ${SING_BASE_PATH})" "$(basename ${SING_BASE_PATH})"
    echo "✅ 配置已备份至：${backup_file}"
}

# 还原配置
config_restore() {
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
config_show() {
    check_root
    if [ -f "${CONFIG_PATH}" ]; then
        echo "📄 当前配置："
        cat "${CONFIG_PATH}" | jq '.'
    else
        echo "❌ 配置文件不存在"
    fi
}

# 检查配置文件
config_check() {
    if [ ! -f "${CONFIG_PATH}" ]; then
        echo "❌ 配置文件不存在"
        return 1
    fi

    # 使用 sing-box 检查配置文件，并将错误输出到临时文件
    local temp_log=$(mktemp)
    if ! $SING_BIN check -c "${CONFIG_PATH}" 2> "${temp_log}"; then
        echo "❌ 配置文件格式无效"
        cat "${temp_log}"  # 打印具体的错误信息
        rm -f "${temp_log}"
        return 1
    fi

    rm -f "${temp_log}"
    echo "✅ 配置文件有效"
}