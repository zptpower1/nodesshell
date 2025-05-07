#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

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
    local inbounds=$(jq -c '.inbounds[]' "${CONFIG_PATH}")
    local server_ip=$(get_server_ip)
    local node_domain=$(source "$ENV_FILE" && echo "$NODEDOMAIN")
    local node_name=$(source "$ENV_FILE" && echo "$NODENAME")
    
    if [[ -n "$node_domain" ]]; then
        server_ip="$node_domain"
    fi
    
    for inbound in $inbounds; do
        local protocol=$(echo "$inbound" | jq -r '.type')
        local port=$(echo "$inbound" | jq -r '.listen_port')
        local method=$(echo "$inbound" | jq -r '.method')
        local server_key=$(echo "$inbound" | jq -r '.password')
        local realpwd=$(echo "$inbound" | jq -r ".users[] | select(.name == \"${name}\") | .password")
        
        if [ -z "${port}" ] || [ "${port}" = "null" ] || [ -z "${method}" ] || [ "${method}" = "null" ]; then
            echo "❌ 服务器配置读取失败"
            continue
        fi
        
        echo "协议: ${protocol}"
        echo "服务器: ${server_ip}"
        echo "端口: ${port}"
        echo "加密方法: ${method}"
        echo "用户密码: ${realpwd}"
        echo "服务密码: ${server_key}"
        echo
        
        # 根据协议生成不同的 URL
        case "$protocol" in
            "shadowsocks")
                source "$(dirname "${BASH_SOURCE[0]}")/ss2022/info.sh"
                generate_url "$method" "$server_key" "$realpwd" "$server_ip" "$port" "$node_name" "$name"
                ;;
            # 可以在这里添加其他协议的处理逻辑
            *)
                echo "⚠️ 未知协议: ${protocol}"
                ;;
        esac
        echo "-------------------------------------------"
    done

    # # 根据环境变量配置决定是否显示二维码
    # SHOW_QRCODE=$(source "$ENV_FILE" && echo "${SHOWQRCODE:-false}")
    # if [[ "$SHOW_QRCODE" == "true" ]]; then
    #     echo "🔲 二维码:"
    #     echo "$ss_url_base64" | qrencode -t UTF8
    # fi
    # echo "-------------------------------------------"
}