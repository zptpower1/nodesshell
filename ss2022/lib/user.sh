#!/bin/bash

source "$(dirname "$0")/utils.sh"

# 添加用户
add_user() {
    check_root
    local username="$1"
    if [ -z "${username}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    local uuid=$(uuidgen)
    mkdir -p "${SS_BASE_PATH}"
    
    if [ ! -f "${USERS_PATH}" ]; then
        echo '{"users":{}}' > "${USERS_PATH}"
    fi
    
    local temp_file=$(mktemp)
    jq ".users[\"${username}\"] = {\"uuid\": \"${uuid}\"}" "${USERS_PATH}" > "${temp_file}"
    mv "${temp_file}" "${USERS_PATH}"
    
    echo "✅ 用户 ${username} 添加成功，UUID: ${uuid}"
}

# 删除用户
del_user() {
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
    
    local temp_file=$(mktemp)
    jq "del(.users[\"${username}\"])" "${USERS_PATH}" > "${temp_file}"
    mv "${temp_file}" "${USERS_PATH}"
    
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
    }
    
    local user_info=$(jq -r ".users[\"${username}\"].uuid" "${USERS_PATH}")
    if [ "${user_info}" != "null" ]; then
        echo "用户: ${username}, UUID: ${user_info}"
    else
        echo "❌ 用户 ${username} 不存在"
    fi
}