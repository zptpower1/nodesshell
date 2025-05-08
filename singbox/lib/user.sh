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
    # 生成UUID
    local uuid=$(uuidgen)
    # 生成16字节密钥
    local key_16=$($SING_BIN generate rand 16 --base64)
    # 生成32字节密钥
    local key_32=$($SING_BIN generate rand 32 --base64)
    
    echo "{\"name\":\"${name}\",\"uuid\":\"${uuid}\",\"password_16\":\"${key_16}\",\"password_32\":\"${key_32}\",\"actived\":true}"
}

# 检查用户是否已存在
check_user_exists() {
    local name="$1"
    jq -e ".users[] | select(.name == \"${name}\")" "${USERS_PATH}" > /dev/null
}

# 添加用户
user_add() {
    local name
    
    # 交互式获取用户名
    while true; do
        read -p "👤 请输入用户名: " name
        if [ -z "${name}" ]; then
            echo "❌ 用户名不能为空，请重新输入"
            continue
        fi
        
        # 检查用户名是否包含特殊字符
        if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "❌ 用户名只能包含字母、数字、下划线和连字符，请重新输入"
            continue
        fi
        
        # 检查用户是否已存在
        if check_user_exists "${name}"; then
            echo "❌ 用户 ${name} 已存在，请重新输入"
            continue
        fi
        
        break
    done
    
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
user_del() {
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
user_list() {
    if [ ! -f "${USERS_PATH}" ]; then
        echo "📋 暂无用户"
        return 0
    fi
    
    echo "📋 用户列表："
    echo "-------------------------------------------"
    jq -r '.users[].name' "${USERS_PATH}" | while read -r name; do
        display_user_info "${name}"
    done
    echo "-------------------------------------------"
}

# 查询用户
user_query() {
    local name
    
    # 交互式获取用户名
    while true; do
        read -p "👤 请输入要查询的用户名: " name
        if [ -z "${name}" ]; then
            echo "❌ 用户名不能为空，请重新输入"
            continue
        fi
        
        if [ ! -f "${USERS_PATH}" ]; then
            echo "❌ 用户配置文件不存在"
            return 1
        fi
        
        local user_exists=$(jq -r ".users[] | select(.name == \"${name}\") | .name" "${USERS_PATH}")
        
        if [ -z "${user_exists}" ]; then
            echo "❌ 用户 ${name} 不存在，请重新输入"
            continue
        fi
        
        break
    done
    
    echo "✅ 找到用户 ${name}"
    echo "-------------------------------------------"
    
    # 显示用户配置信息
    echo "📋 用户配置信息："
    display_user_info "${name}" "true"
    echo "-------------------------------------------"
    
    # 生成客户端配置
    generate_client_config "${name}"
}

# 重置用户密码
user_reset_pwd() {
    local name="$1"
    if [ -z "${name}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    # 检查用户是否存在
    if ! check_user_exists "${name}"; then
        echo "❌ 用户 ${name} 不存在"
        return 1
    }
    
    # 生成新的密钥
    local uuid=$(uuidgen)
    local key_16=$($SING_BIN generate rand 16 --base64)
    local key_32=$($SING_BIN generate rand 32 --base64)
    
    # 更新用户密钥
    local temp_file=$(mktemp)
    jq ".users |= map(if .name == \"${name}\" then . + {\"uuid\": \"${uuid}\", \"password_16\": \"${key_16}\", \"password_32\": \"${key_32}\"} else . end)" "${USERS_PATH}" > "${temp_file}"
    mv "${temp_file}" "${USERS_PATH}"
    
    config_sync
    echo "✅ 用户 ${name} 密码重置成功"
    generate_client_config "${name}"
}

# 切换用户状态
user_toggle_status() {
    local name="$1"
    if [ -z "${name}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    # 检查用户是否存在
    if ! check_user_exists "${name}"; then
        echo "❌ 用户 ${name} 不存在"
        return 1
    }
    
    # 切换用户状态
    local temp_file=$(mktemp)
    jq ".users |= map(if .name == \"${name}\" then . + {\"actived\": (if .actived == null then false elif .actived then false else true end)} else . end)" "${USERS_PATH}" > "${temp_file}"
    mv "${temp_file}" "${USERS_PATH}"
    
    # 获取新状态
    local new_status=$(jq -r ".users[] | select(.name == \"${name}\") | .actived" "${USERS_PATH}")
    local status_text
    if [ "${new_status}" = "true" ]; then
        status_text="启用"
    else
        status_text="禁用"
    fi
    
    config_sync
    echo "✅ 用户 ${name} 已${status_text}"
}

# 显示用户配置信息
display_user_info() {
    local name="$1"
    local show_detail="${2:-false}"  # 第二个参数控制是否显示详细信息，默认为 false
    
    if [ "${show_detail}" = "true" ]; then
        # 显示详细信息
        jq -r ".users[] | select(.name == \"${name}\") | to_entries | .[] | \"\(.key): \(.value)\"" "${USERS_PATH}"
    else
        # 显示简略信息
        jq -r ".users[] | select(.name == \"${name}\") | \"用户名: \(.name)\n状态: \(if .actived == null or .actived then \"✅ 启用\" else \"❌ 禁用\" end)\"" "${USERS_PATH}"
    fi
}