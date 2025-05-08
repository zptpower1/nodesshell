#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 生成客户端配置
generate_client_config() {
    local name="$1"
    
    echo "📱 ${name} 的客户端配置："
    echo "-------------------------------------------"
    
    # 从 CONFIG_PATH 获取服务器配置
    echo "🔧 协议配置信息 (来自 ${CONFIG_PATH})："
    local inbounds=$(jq -c '.inbounds[]' "${CONFIG_PATH}")
    local server_ip=$(get_server_ip)
    local node_domain=$(source "$ENV_FILE" && echo "$NODEDOMAIN")
    local node_name=$(source "$ENV_FILE" && echo "$NODENAME")
    
    if [[ -n "$node_domain" ]]; then
        server_ip="$node_domain"
    fi
    
    local found_user=false
    
    for inbound in $inbounds; do
        local protocol=$(echo "$inbound" | jq -r '.type')
        local port=$(echo "$inbound" | jq -r '.listen_port')
        local server_ip=$(get_server_ip)
        local node_domain=$(source "$ENV_FILE" && echo "$NODEDOMAIN")
        local node_name=$(source "$ENV_FILE" && echo "$NODENAME")
    
        if [[ -n "$node_domain" ]]; then
            server_ip="$node_domain"
        fi
    
        found_user=false
    
        case "$protocol" in
            "shadowsocks")
                local method=$(echo "$inbound" | jq -r '.method')
                local server_key=$(echo "$inbound" | jq -r '.password')
                local realpwd=$(echo "$inbound" | jq -r ".users[] | select(.name == \"${name}\") | .password")
    
                if [ -z "${realpwd}" ] || [ "${realpwd}" = "null" ]; then
                    continue
                fi
    
                found_user=true
    
                if [ -z "${port}" ] || [ "${port}" = "null" ] || [ -z "${method}" ] || [ "${method}" = "null" ]; then
                    echo "❌ 服务器配置读取失败"
                    continue
                fi
    
                echo "协议: ${protocol}"
                echo "服务器: ${server_ip}"
                echo "端口: ${port}"
                echo "加密方法: ${method}"
                echo "服务密钥: ${server_key}"
                echo "用户密码: ${realpwd}"
                echo
    
                source "$(dirname "${BASH_SOURCE[0]}")/ss/info.sh"
                generate_url "$method" "$server_key" "$realpwd" "$server_ip" "$port" "$node_name" "$name"
                ;;
            "vless")
                local uuid=$(echo "$inbound" | jq -r ".users[] | select(.name == \"${name}\") | .uuid")
                local host=$(echo "$inbound" | jq -r '.tls.reality.handshake.server')
                local tag=$(echo "$inbound" | jq -r '.tag')  # 获取当前 inbound 的 tag
                local pbk=$(jq -r ".inbounds[] | select(.tag == \"${tag}\") | .tls.reality.public_key" "${BASE_CONFIG_PATH}")
                local sid=$(echo "$inbound" | jq -r '.tls.reality.short_id[]')
    
                if [ -z "${uuid}" ] || [ "${uuid}" = "null" ]; then
                    continue
                fi
    
                found_user=true
    
                if [ -z "${port}" ] || [ "${port}" = "null" ]; then
                    echo "❌ 服务器配置读取失败"
                    continue
                fi
    
                echo "协议: ${protocol}"
                echo "服务器: ${server_ip}"
                echo "端口: ${port}"
                echo "UUID: ${uuid}"
                echo "Host: ${host}"
                echo "Public Key: ${pbk}"
                echo "Short ID: ${sid}"
                echo
    
                source "$(dirname "${BASH_SOURCE[0]}")/vless/info.sh"
                generate_url "$uuid" "$server_ip" "$port" "$node_name" "$name" "$host" "$pbk" "$sid"
                ;;
            *)
                echo "⚠️ 未知协议: ${protocol}"
                ;;
        esac
        echo "-------------------------------------------"
    done

    if [ "$found_user" = false ]; then
        echo "❌ 未找到用户 ${name}"
        return 1
    fi

    # # 根据环境变量配置决定是否显示二维码
    # SHOW_QRCODE=$(source "$ENV_FILE" && echo "${SHOWQRCODE:-false}")
    # if [[ "$SHOW_QRCODE" == "true" ]]; then
    #     echo "🔲 二维码:"
    #     echo "$ss_url_base64" | qrencode -t UTF8
    # fi
    # echo "-------------------------------------------"
}