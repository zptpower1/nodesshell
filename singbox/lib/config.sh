#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"


# 创建基础配置
config_create_base() {
    # 检查基础配置文件是否已存在
    if [ -f "${BASE_CONFIG_PATH}" ]; then
        echo "✅ 基础配置文件已存在。"
        read -p "是否要覆盖现有的基础配置文件？(n[默认]/y): " choice
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
    echo "DEBUG: Starting config_sync"
    echo "DEBUG: BASE_CONFIG_PATH=${BASE_CONFIG_PATH}"
    echo "DEBUG: USERS_PATH=${USERS_PATH}"
    echo "DEBUG: CONFIG_PATH=${CONFIG_PATH}"

    # 检查文件存在性
    if [ ! -f "${BASE_CONFIG_PATH}" ] || [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 基础配置文件或用户配置文件不存在"
        return 1
    fi
    echo "DEBUG: Input files exist"

    # 验证 JSON 格式
    if ! jq '.' "${BASE_CONFIG_PATH}" >/dev/null 2>&1; then
        echo "❌ base_config.json JSON 格式无效"
        return 1
    fi
    if ! jq '.' "${USERS_PATH}" >/dev/null 2>&1; then
        echo "❌ users.json JSON 格式无效"
        return 1
    fi
    echo "DEBUG: Input files are valid JSON"

    # 检查目标目录权限
    local config_dir=$(dirname "${CONFIG_PATH}")
    if [ ! -w "${config_dir}" ]; then
        echo "❌ 目标目录 ${config_dir} 不可写"
        return 1
    fi
    echo "DEBUG: Config directory is writable"

    # 创建临时文件
    local temp_file
    temp_file=$(mktemp /tmp/sing-box-config.XXXXXX) || {
        echo "❌ 无法创建临时文件"
        return 1
    }
    echo "DEBUG: Temporary file created: ${temp_file}"

    # 定义白名单和密钥映射
    local method_map='{
        "2022-blake3-aes-128-gcm": "password_16",
        "2022-blake3-aes-256-gcm": "password_32",
        "2022-blake3-chacha20-poly1305": "password_32"
    }'

    # 运行 jq 合并
    echo "DEBUG: Running jq command"
    if ! jq -s --argjson method_map "${method_map}" '
        .[0] as $base |
        .[1] as $users |
        # 验证 users 数组
        if ($users.users | type) != "array" then
            error("users.json must contain a valid users array")
        else
            # 验证 inbounds 数组
            if ($base.inbounds | type) != "array" then
                error("base_config.json must contain a valid inbounds array")
            else
                $base * {
                    "inbounds": [
                        ($base.inbounds[] | . as $parent |
                        if .type == "shadowsocks" then
                            . + {
                                "users": ($users.users | map({
                                    "name": .name,
                                    "password": (
                                        if $parent.method == "2022-blake3-aes-128-gcm" then .password_16
                                        elif $parent.method == "2022-blake3-aes-256-gcm" then .password_32
                                        elif $parent.method == "2022-blake3-chacha20-poly1305" then .password_32
                                        else .uuid
                                        end
                                    )
                                }))
                            }
                        elif .type == "vless" or .type == "vmess" then
                            . + {
                                "users": ($users.users | map({
                                    "name": .name,
                                    "uuid": .uuid
                                }))
                            }
                        else . end)
                    ]
                }
            end
        end
    ' "${BASE_CONFIG_PATH}" "${USERS_PATH}" > "${temp_file}" 2> "${temp_file}.err"; then
        echo "❌ jq 命令执行失败: $(cat ${temp_file}.err)"
        rm -f "${temp_file}" "${temp_file}.err"
        return 1
    fi
    echo "DEBUG: jq command completed"

    # 检查 jq 错误
    if [ -s "${temp_file}.err" ]; then
        echo "❌ jq 错误: $(cat ${temp_file}.err)"
        rm -f "${temp_file}" "${temp_file}.err"
        return 1
    fi
    echo "DEBUG: No jq errors"

    # 检查输出文件
    if [ ! -s "${temp_file}" ]; then
        echo "❌ 临时文件为空"
        rm -f "${temp_file}" "${temp_file}.err"
        return 1
    fi
    echo "DEBUG: Temporary file has content"

    # 验证输出 JSON
    if ! jq '.' "${temp_file}" >/dev/null 2>&1; then
        echo "❌ 配置文件格式无效"
        rm -f "${temp_file}" "${temp_file}.err"
        return 1
    fi
    echo "DEBUG: Output JSON is valid"

    # 移动文件
    if ! mv "${temp_file}" "${CONFIG_PATH}"; then
        echo "❌ 无法移动临时文件到 ${CONFIG_PATH}"
        rm -f "${temp_file}" "${temp_file}.err"
        return 1
    fi
    echo "DEBUG: File moved to ${CONFIG_PATH}"

    # 设置权限
    chmod 644 "${CONFIG_PATH}" || {
        echo "❌ 无法设置 ${CONFIG_PATH} 权限"
        return 1
    }
    rm -f "${temp_file}.err"
    echo "DEBUG: Permissions set"

    echo "✅ 配置同步完成"
}

# 备份配置
config_backup() {
    check_root
    local backup_time=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/config_${backup_time}.tar.gz"
    
    tar -czf "${backup_file}" -C "$(dirname ${CONFIGS_DIR})" "$(basename ${CONFIGS_DIR})"
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
    
    service_stop
    tar -xzf "${backup_file}" -C "$(dirname ${CONFIGS_DIR})"
    service_start
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
