#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 生成用户配置
generate_user_config() {
    local name="$1"
    # 生成32字节(64个十六进制字符)的密钥
    local password=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p -c 64)
    echo "{\"name\":\"${name}\",\"password\":\"${password}\"}"
}

# 添加用户
add_user() {
    local name="$1"
    if [ -z "${name}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    local user_config=$(generate_user_config "${name}")
    local temp_file=$(mktemp)
    
    jq ".inbounds[0].users += [${user_config}]" "${CONFIG_PATH}" > "${temp_file}"
    mv "${temp_file}" "${CONFIG_PATH}"
    
    echo "✅ 用户 ${name} 添加成功"
    generate_client_config "${name}"
}

# 删除用户
delete_user() {
    local name="$1"
    if [ -z "${name}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    local temp_file=$(mktemp)
    jq ".inbounds[0].users |= map(select(.name != \"${name}\"))" "${CONFIG_PATH}" > "${temp_file}"
    mv "${temp_file}" "${CONFIG_PATH}"
    
    echo "✅ 用户 ${name} 删除成功"
}

# 列出所有用户
list_users() {
    echo "📋 用户列表："
    echo "-------------------------------------------"
    jq -r '.inbounds[0].users[] | "用户名: \(.name)"' "${CONFIG_PATH}"
    echo "-------------------------------------------"
}

# 生成客户端配置
generate_client_config() {
    local name="$1"
    local password=$(jq -r ".inbounds[0].users[] | select(.name == \"${name}\") | .password" "${CONFIG_PATH}")
    local server_ip=$(get_server_ip)
    local port=$(jq -r '.inbounds[0].listen_port' "${CONFIG_PATH}")
    local method=$(jq -r '.inbounds[0].method' "${CONFIG_PATH}")
    
    echo "📱 用户 ${name} 的配置信息："
    echo "服务器: ${server_ip}"
    echo "端口: ${port}"
    echo "密码: ${password}"
    echo "加密方法: ${method}"
    
    local ss_url="ss://${method}:${password}@${server_ip}:${port}#${name}"
    echo "🔗 SS URL: ${ss_url}"
}