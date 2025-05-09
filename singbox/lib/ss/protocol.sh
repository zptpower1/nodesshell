#!/bin/bash
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")/utils.sh"

#添加新的 inbound 模块
add_protocol() {
    local port="$1"
    local method="$2"
    
    if [ -z "$method" ] || [ -z "$port" ]; then
        echo "❌ 请提供加密方法和端口号"
        echo "用法: add_protocol <port> <method> "
        return 1
    fi
    
    # 检查基础配置文件是否已存在
    if [ ! -f "${BASE_CONFIG_PATH}" ]; then
        echo "❌ 基础配置文件不存在：${BASE_CONFIG_PATH}"
        return 1
    fi
    
    # 生成32字节(64个十六进制字符)的主密钥
    local server_key=$(generate_key "${method}")
    local protocol="shadowsocks"
    local tag_name="ss-brutal-sb-in"
    
    # 定义新的 inbound 模块
    local new_inbound=$(cat <<EOF
{
  "type": "${protocol}",
  "tag": "${tag_name}-${port}",
  "listen": "::",
  "listen_port": ${port},
  "sniff": true,
  "sniff_override_destination": true,
  "method": "${method}",
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

