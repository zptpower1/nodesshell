#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 生成用户配置
generate_user_config() {
    local name="$1"
    local password=$(openssl rand -hex 16)  # 使用hex编码而不是base64
    echo "{\"name\":\"${name}\",\"password\":\"${password}\"}"
}

# 创建基础配置
create_config() {
    mkdir -p "${SING_BASE_PATH}"
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
      "key": "$(openssl rand -hex 16)",
      "users": [
        $(generate_user_config "user1"),
        $(generate_user_config "user2"),
        $(generate_user_config "user3")
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