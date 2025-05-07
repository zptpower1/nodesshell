#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 添加用户
function add_user() {
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
    
    # 打印客户端配置信息
    print_client_info "${username}"
}

# 删除用户
function del_user() {
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

    # 同步配置
    sync_config
}

# 列出用户
function list_users() {
    check_root
    if [ ! -f "${USERS_PATH}" ]; then
        echo "❌ 用户文件不存在"
        return 1
    fi
    
    echo "📋 当前用户列表："
    jq -r '.users | to_entries[] | "用户: \(.key), UUID: \(.value.uuid)"' "${USERS_PATH}"
}

# 查询用户
function query_user() {
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

# 打印客户端配置信息
function print_client_info() {
    local username="$1"
    if [ -z "${username}" ]; then
        echo "❌ 请提供用户名"
        return 1
    fi
    
    if [ ! -f "${CONFIG_PATH}" ]; then
        echo "❌ 配置文件不存在"
        return 1
    fi
    
    # 获取用户配置信息
    PASSWORD=$(jq -r ".users[\"${username}\"].uuid" "${USERS_PATH}")
    if [ "$PASSWORD" == "null" ]; then
        echo "❌ 用户 ${username} 不存在"
        return 1
    fi

    METHOD=$(jq -r '.method' "$CONFIG_PATH")
    NODENAME=$(source "$ENV_FILE" && echo "$NODENAME")
    NODEDOMAIN=$(source "$ENV_FILE" && echo "$NODEDOMAIN")
    if [[ -n "$NODEDOMAIN" ]]; then
        ADD="$NODEDOMAIN"
        echo "📌 使用节点域名: $ADD"
    else
        ADD=$(curl -s ipv4.ip.sb || echo "your.server.com")
        echo "📌 使用服务器 IP: $ADD"
    fi
    
    # 获取服务器配置
    PORT=$(jq -r '.server_port' "$CONFIG_PATH")
    
    echo "📱 Clash 配置："
    echo "  - name: $NODENAME"
    echo "    type: ss2022"
    echo "    server: $ADD"
    echo "    port: $PORT"
    echo "    cipher: $METHOD"
    echo "    password: $PASSWORD"
    
    # 生成 SS URL
    CONFIG="$METHOD:$PASSWORD@$ADD:$PORT"
    SS_URL="ss://$(echo -n "$CONFIG" | base64 -w 0)#$NODENAME"
    echo
    echo "🔗 SS 链接:"
    echo "${SS_URL}"
    
    # 根据环境变量配置决定是否显示二维码
    SHOW_QRCODE=$(source "$ENV_FILE" && echo "${SHOWQRCODE:-false}")
    if [[ "$SHOW_QRCODE" == "true" ]]; then
        echo "🔲 二维码:"
        echo "$SS_URL" | qrencode -t UTF8
    fi
    echo "-------------------------------------------"
}