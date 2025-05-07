#!/bin/bash
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")/utils.sh"

#添加新的 inbound 模块
add_protocol() {
    # 检查基础配置文件是否已存在
    if [ ! -f "${BASE_CONFIG_PATH}" ]; then
        echo "❌ 基础配置文件不存在：${BASE_CONFIG_PATH}"
        return 1
    fi
    
    # 生成32字节(64个十六进制字符)的主密钥
    local server_key=$(generate_key "${SERVER_METHOD}")
    local protocol="shadowsocks"
    local tag_name="ss-brutal-sb-in"
    
    # 检查是否已存在同名的 inbound 模块
    if jq -e ".inbounds[] | select(.tag == \"${tag_name}\")" "${BASE_CONFIG_PATH}" > /dev/null; then
        # 为 tag 增加随机数后缀
        local random_suffix=$((RANDOM % 10000))
        tag_name="${tag_name}-${random_suffix}"
        echo "⚠️ 已存在同名的 inbound 模块，使用新的 tag：${tag_name}"
    fi

    # 定义新的 inbound 模块
    local new_inbound=$(cat <<EOF
{
  "type": "${protocol}",
  "tag": "${tag_name}",
  "listen": "::",
  "listen_port": ${SERVER_PORT},
  "sniff": true,
  "sniff_override_destination": true,
  "method": "${SERVER_METHOD}",
  "password": "${server_key}",
  "multiplex": {
    "enabled": true,    
    "padding": true,
    "brutal": {
      "enabled": true,
      "up_mbps": 600,
      "down_mbps": 600
    }
  }
}
EOF
)

    # 使用 jq 将新的 inbound 模块添加到现有配置中
    jq --argjson new_inbound "$new_inbound" '.inbounds += [$new_inbound]' "${BASE_CONFIG_PATH}" > "${BASE_CONFIG_PATH}.tmp" && mv "${BASE_CONFIG_PATH}.tmp" "${BASE_CONFIG_PATH}"

    echo "✅ 新的入站模块已成功添加到配置文件中。协议类型：${protocol}，标签名：${tag_name}"
}

