#!/bin/bash
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/protocol.sh"

function setup_protocoler() {
    local default_port=$(generate_random_port 2>/dev/null)
    local default_method="2022-blake3-aes-128-gcm"
    local port
    local method
    
    # 设置默认值并通过用户选择获取端口号
    read -p "请输入端口号 [默认: ${default_port}]: " port
    port=${port:-${default_port}}
    
    # 通过用户选择获取加密方式
    echo "可用的加密方式:"
    echo "1) 2022-blake3-aes-128-gcm (默认)"
    echo "2) 2022-blake3-aes-256-gcm"
    echo "3) 2022-blake3-chacha20-poly1305"
    read -p "请选择加密方式 [1-3]: " method_choice
    
    case $method_choice in
        1) method="2022-blake3-aes-128-gcm";;
        2) method="2022-blake3-aes-256-gcm";;
        3) method="2022-blake3-chacha20-poly1305";;
        *) method="${default_method}";;
    esac
    
    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "❌ 无效的端口号: ${port}"
        return 1
    fi
    
    # 初始化配置
    add_protocol "$port" "$method"
    
    # 显示安装信息
    echo
    echo "✅ 协议安装完成！"
    echo "-------------------------------------------"
    echo "端口: ${port}"
    echo "加密方式: ${method}"
    echo "-------------------------------------------"
}