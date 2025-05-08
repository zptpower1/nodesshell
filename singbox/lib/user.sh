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
    # 生成16字节(32个十六进制字符)的密钥
    # local password=$(openssl rand -base64 16 | head -c 24)
    local password=$(generate_key "${SERVER_METHOD}")
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

    config_sync
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
    

    config_sync
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