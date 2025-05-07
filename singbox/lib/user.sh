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

# 检查用户是否已存在
check_user_exists() {
    local name="$1"
    jq -e ".users[] | select(.name == \"${name}\")" "${USERS_PATH}" > /dev/null
}

# 添加用户
add_user() {
    local name="$1"
    if [ -z "${name}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
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

    sync_config
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
    

    sync_config
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
    local realpwd=$(jq -r ".inbounds[0].users[] | select(.name == \"${name}\") | .password" "${CONFIG_PATH}")
    if [ -z "${port}" ] || [ "${port}" = "null" ] || [ -z "${method}" ] || [ "${method}" = "null" ]; then
        echo "❌ 服务器配置读取失败"
        return 1
    fi
    local server_ip=$(get_server_ip)
    local node_domain=$(source "$ENV_FILE" && echo "$NODEDOMAIN")
    local node_name=$(source "$ENV_FILE" && echo "$NODENAME")
    
    if [[ -n "$node_domain" ]]; then
        server_ip="$node_domain"
        echo "📌 使用节点域名: $server_ip"
    else
        echo "📌 使用服务器 IP: $server_ip"
    fi
    
    echo "服务器: ${server_ip}"
    echo "端口: ${port}"
    echo "加密方法: ${method}"
    echo "密码: ${realpwd}"
    echo
    
    # 对比两个密码
    if [ "${password}" != "${realpwd}" ]; then
        echo "⚠️ 警告: 用户配置和服务器配置中的密码不匹配！"
    fi
    
    # 生成 URL
    echo "🔗 连接信息："
    local config="${method}:${realpwd}@${server_ip}:${port}"
    local ss_url="ss://${config}#${node_name:-$name}"

    local config_base64=$(echo -n "${config}" | base64 -w 0)
    local ss_url_base64="ss://${config_base64}#${node_name:-$name}"
   
    echo "Shadowsocks URL: ${ss_url}"
    echo "Shadowsocks URL (Base64): ${ss_url_base64}"
    echo "-------------------------------------------"

    # 根据环境变量配置决定是否显示二维码
    SHOW_QRCODE=$(source "$ENV_FILE" && echo "${SHOWQRCODE:-true}")
    if [[ "$SHOW_QRCODE" == "true" ]]; then
        echo "🔲 二维码:"
        echo "$ss_url_base64" | qrencode -t UTF8
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