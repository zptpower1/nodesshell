#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 添加用户
add_user() {
    check_root
    local username="$1"
    if [ -z "${username}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    mkdir -p "${SS_BASE_PATH}"
    
    # 初始化用户配置文件
    if [ ! -f "${USERS_PATH}" ]; then
        echo "📝 创建用户配置文件..."
        echo '{"users":{}}' > "${USERS_PATH}"
        chmod 644 "${USERS_PATH}"
    fi
    
    # 检查用户是否已存在
    if jq -e ".users[\"${username}\"]" "${USERS_PATH}" >/dev/null 2>&1; then
        echo "❌ 用户 ${username} 已存在"
        return 1
    fi
    
    local uuid=$(uuidgen)
    
    # 更新用户数据文件
    local temp_users_file=$(mktemp)
    if ! jq ".users[\"${username}\"] = {\"uuid\": \"${uuid}\", \"created_at\": \"$(date +%Y-%m-%d\ %H:%M:%S)\"}" "${USERS_PATH}" > "${temp_users_file}"; then
        echo "❌ 更新用户数据失败"
        rm -f "${temp_users_file}"
        return 1
    fi
    mv "${temp_users_file}" "${USERS_PATH}"
    chmod 644 "${USERS_PATH}"
    
    echo "✅ 用户 ${username} 添加成功"
    echo "📌 用户信息："
    echo "  用户名: ${username}"
    echo "  UUID: ${uuid}"
    
    # 同步配置
    sync_config
}

# 删除用户
del_user() {
    check_root
    local username="$1"
    if [ -z "${username}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    if [ "${username}" = "admin" ]; then
        echo "❌ 不能删除管理员用户"
        return 1
    }
    
    if [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 用户文件不存在"
        return 1
    fi
    
    # 检查用户是否存在
    if ! jq -e ".users[\"${username}\"]" "${USERS_PATH}" >/dev/null 2>&1; then
        echo "❌ 用户 ${username} 不存在"
        return 1
    }
    
    # 更新用户数据文件
    local temp_users_file=$(mktemp)
    jq "del(.users[\"${username}\"])" "${USERS_PATH}" > "${temp_users_file}"
    mv "${temp_users_file}" "${USERS_PATH}"
    
    # 更新配置文件
    local temp_config_file=$(mktemp)
    jq "del(.users[\"${username}\"])" "${CONFIG_PATH}" > "${temp_config_file}"
    mv "${temp_config_file}" "${CONFIG_PATH}"
    
    echo "✅ 用户 ${username} 删除成功"
}

# 列出用户
list_users() {
    check_root
    if [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 用户文件不存在"
        return 1
    fi
    
    echo "📋 当前用户列表："
    jq -r '.users | to_entries[] | "用户: \(.key), UUID: \(.value.uuid)"' "${USERS_PATH}"
}

# 查询用户
query_user() {
    check_root
    local username="$1"
    if [ -z "${username}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    if [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 用户文件不存在"
        return 1
    fi
    
    local user_info=$(jq -r ".users[\"${username}\"].uuid" "${USERS_PATH}")
    if [ "${user_info}" != "null" ]; then
        echo "用户: ${username}, UUID: ${user_info}"
    else
        echo "❌ 用户 ${username} 不存在"
    fi
}