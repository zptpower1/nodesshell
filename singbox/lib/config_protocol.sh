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
            source "$(dirname "${BASH_SOURCE[0]}")/ss2022/setup.sh"
            setup_protocoler
            ;;
        vless_vision_reality)
            # source "$(dirname "${BASH_SOURCE[0]}")/vless/setup.sh"
            # setup_vless_service
            ;;
        *)
            echo "❌ 未知的协议类型: $protocol"
            return 1
            ;;
    esac

    check_service
}