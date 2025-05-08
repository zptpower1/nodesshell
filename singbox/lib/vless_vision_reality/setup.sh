#!/bin/bash
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")/utils.sh"

function setup_protocoler() {
    local default_port=$(generate_random_port 2>/dev/null)
    local port
    
    # 设置默认值并通过用户选择获取端口号
    read -p "请输入端口号 [默认: ${default_port}]: " port
    port=${port:-${default_port}}
    
    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "❌ 无效的端口号: ${port}"
        return 1
    fi
    
    source "$(dirname "${BASH_SOURCE[0]}")/protocol.sh"
    # 初始化配置
    add_protocol "$port"
    
    # 显示安装信息
    echo
    echo "✅ 协议安装完成！"
    echo "-------------------------------------------"
    echo "端口: ${port}"
    echo "加密方式: vision+reality"
    echo "-------------------------------------------"
}