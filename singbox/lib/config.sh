#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 生成用户配置
generate_user_config() {
    local name="$1"
    # 生成32字节(64个十六进制字符)的密钥
    local password=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p -c 64)
    echo "{\"name\":\"${name}\",\"password\":\"${password}\"}"
}

# 创建基础配置
create_config() {
    mkdir -p "${SING_BASE_PATH}"
    # 生成32字节(64个十六进制字符)的主密钥
    local server_key=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p -c 64)
    cat > "${CONFIG_PATH}" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${DEFAULT_PORT},
      "method": "${DEFAULT_METHOD}",
      "password": "${server_key}",
      "users": [
        $(generate_user_config "admin")
      ]
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
}

# 生成客户端配置
generate_client_configs() {
    local config_dir="/tmp/ss2022_configs"
    mkdir -p $config_dir
    
    USERS=$(jq -r '.inbounds[0].users[] | .name + ":" + .password' "${CONFIG_PATH}")
    while IFS=: read -r username password; do
        SS_URL="ss://${DEFAULT_METHOD}:${password}@$(get_server_ip):${DEFAULT_PORT}#${username}"
        echo "用户: ${username}" >> "${config_dir}/client_configs.txt"
        echo "Shadowsocks URL: ${SS_URL}" >> "${config_dir}/client_configs.txt"
        echo "-------------------" >> "${config_dir}/client_configs.txt"
    done <<< "$USERS"
    
    echo "✅ 客户端配置已保存至: ${config_dir}/client_configs.txt"
}