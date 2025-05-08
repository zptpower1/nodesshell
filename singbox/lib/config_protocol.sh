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