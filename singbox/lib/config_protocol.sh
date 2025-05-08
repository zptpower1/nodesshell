#!/bin/bash

function config_protocol_setup() {
    local protocol
    
    # 如果没有提供协议参数，则让用户选择
    if [ -z "$protocol" ]; then
        echo "请选择要安装的协议类型:"
        echo "1) Shadowsocks"
        echo "2) VLESS+Vision+REALITY"
        read -p "请输入选择 [1-2]: " protocol_choice
        
        case $protocol_choice in
            1) protocol="ss";;
            2) protocol="vless_vision_reality";;
            *) echo "❌ 无效的选择"; return 1;;
        esac
    fi
    
    # 根据协议选择不同的安装脚本
    case "$protocol" in
        ss)
            source "$(dirname "${BASH_SOURCE[0]}")/ss/setup.sh"
            setup_protocoler
            ;;
        vless_vision_reality)
            source "$(dirname "${BASH_SOURCE[0]}")/vless_vision_reality/setup.sh"
            setup_protocoler
            # echo "⚠️ 程序猿即将吐血，请耐心等待: $protocol"
            # return 1
            ;;
        *)
            echo "❌ 未知的协议类型: $protocol"
            return 1
            ;;
    esac

    # 同步配置
    config_sync
    # 配置防火墙
    allow_firewall
    #重启服务
    service_restart
    # 检查服务状态
    service_check
}

# 列出已安装的协议
function config_protocol_list() {
    # 检查配置文件是否存在
    if [ ! -f "${BASE_CONFIG_PATH}" ]; then
        echo "❌ 基础配置文件不存在：${BASE_CONFIG_PATH}"
        return 1
    fi
    
    # 获取所有已安装的 inbound 信息
    local inbounds_info=$(jq -r '.inbounds[] | "\(.tag)|\(.type)|\(.listen_port)"' "${BASE_CONFIG_PATH}")
    if [ -z "$inbounds_info" ]; then
        echo "❌ 当前没有已安装的协议服务"
        return 1
    fi
    
    # 显示所有已安装的协议
    echo "已安装的协议服务列表:"
    echo "----------------------------------------"
    echo "序号  标签名(Tag)           类型(Type)           端口(Port)"
    echo "----------------------------------------"
    
    local index=1
    while IFS='|' read -r tag type port; do
        printf "%-6s%-20s%-20s%-6s\n" "$index)" "$tag" "$type" "$port"
        ((index++))
    done <<< "$inbounds_info"
    export config_protocol_list_last_count=$((index-1))
    
    echo "----------------------------------------"
}

# 卸载协议
function config_protocol_remove() {
    config_protocol_list  # 调用 list 函数展示已安装协议

    read -p "请选择要卸载的协议 [1-$(config_protocol_list_last_count)]: " choice
    
    # 验证输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge "$index" ]; then
        echo "❌ 无效的选择"
        return 1
    fi
    
    # 获取选择的标签
    local selected_tag="${tag_list[$((choice-1))]}"
    
    # 获取要删除的端口号（用于后续移除防火墙规则）
    local port_to_remove=$(jq -r ".inbounds[] | select(.tag == \"$selected_tag\") | .listen_port" "${BASE_CONFIG_PATH}")
    
    # 从配置中移除选中的 inbound
    echo "🗑️ 正在移除协议服务: $selected_tag"
    jq "del(.inbounds[] | select(.tag == \"$selected_tag\"))" "${BASE_CONFIG_PATH}" > "${BASE_CONFIG_PATH}.tmp" && \
    mv "${BASE_CONFIG_PATH}.tmp" "${BASE_CONFIG_PATH}"
    
    # 移除对应的防火墙规则
    if [ -n "$port_to_remove" ]; then
        delete_firewall_port "$port_to_remove"
    fi
    
    # 同步配置
    config_sync
    # 重启服务
    service_restart
    # 检查服务状态
    service_check
    
    echo "✅ 协议服务已成功移除"
}