#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 初始化用户配置文件
init_users_config() {
    if [ ! -f "${USERS_PATH}" ]; then
        echo '{"users":[]}' > "${USERS_PATH}"
    fi
}

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
    
    init_users_config
    
    # 检查用户是否已存在
    if jq -e ".users[] | select(.name == \"${name}\")" "${USERS_PATH}" > /dev/null; then
        echo "❌ 用户 ${name} 已存在"
        return 1
    fi
    
    # 生成用户配置并添加到用户文件
    local user_config=$(generate_user_config "${name}")
    local temp_file=$(mktemp)
    jq ".users += [${user_config}]" "${USERS_PATH}" > "${temp_file}"
    mv "${temp_file}" "${USERS_PATH}"
    
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
    
    # 从用户文件中删除用户
    local temp_file=$(mktemp)
    jq ".users |= map(select(.name != \"${name}\"))" "${USERS_PATH}" > "${temp_file}"
    mv "${temp_file}" "${USERS_PATH}"
    
    echo "✅ 用户 ${name} 删除成功"
}

# 列出所有用户
list_users() {
    if [ ! -f "${USERS_PATH}" ]; then
        echo "📋 暂无用户"
        return 0
    fi
    
    echo "📋 用户列表："
    echo "-------------------------------------------"
    jq -r '.users[] | "用户名: \(.name)"' "${USERS_PATH}"
    echo "-------------------------------------------"
}

# 生成客户端配置
generate_client_config() {
    local name="$1"
    
    echo "📱 用户 ${name} 的配置信息："
    echo "-------------------------------------------"
    
    # 从 USERS_PATH 获取用户信息
    echo "👤 用户配置 (来自 ${USERS_PATH})："
    local password=$(jq -r ".users[] | select(.name == \"${name}\") | .password" "${USERS_PATH}")
    if [ -z "${password}" ] || [ "${password}" = "null" ]; then
        echo "❌ 未在用户配置中找到用户 ${name}"
        return 1
    fi
    echo "用户名: ${name}"
    echo "密码: ${password}"
    echo
    
    # 从 CONFIG_PATH 获取服务器配置
    echo "🔧 服务器配置 (来自 ${CONFIG_PATH})："
    local port=$(jq -r '.inbounds[0].listen_port' "${CONFIG_PATH}")
    local method=$(jq -r '.inbounds[0].method' "${CONFIG_PATH}")
    if [ -z "${port}" ] || [ "${port}" = "null" ] || [ -z "${method}" ] || [ "${method}" = "null" ]; then
        echo "❌ 服务器配置读取失败"
        return 1
    fi
    local server_ip=$(get_server_ip)
    echo "服务器: ${server_ip}"
    echo "端口: ${port}"
    echo "加密方法: ${method}"
    echo
    
    # 生成 URL
    echo "🔗 连接信息："
    local ss_url="ss://${method}:${password}@${server_ip}:${port}#${name}"
    echo "Shadowsocks URL: ${ss_url}"
    echo "-------------------------------------------"

    # 根据环境变量配置决定是否显示二维码
    SHOW_QRCODE=$(source "$ENV_FILE" && echo "${SHOWQRCODE:-true}")
    if [[ "$SHOW_QRCODE" == "true" ]]; then
        echo "🔲 二维码:"
        echo "$SS_URL" | qrencode -t UTF8
    fi
    echo "-------------------------------------------"
}

# 查询用户
query_user() {
    local name="$1"
    if [ -z "${name}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    if [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 用户配置文件不存在"
        return 1
    fi
    
    local user_exists=$(jq -r ".users[] | select(.name == \"${name}\") | .name" "${USERS_PATH}")
    
    if [ -z "${user_exists}" ]; then
        echo "❌ 用户 ${name} 不存在"
        return 1
    fi
    
    echo "✅ 找到用户 ${name}"
    echo "-------------------------------------------"
    generate_client_config "${name}"
}