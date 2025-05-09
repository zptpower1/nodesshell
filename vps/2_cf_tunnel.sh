#!/bin/bash

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 此脚本需要以 root 权限运行"
        exit 1
    fi
}

# 更新包管理器并安装Cloudflare Tunnel
install_cloudflared() {
    echo "更新系统包..."
    sudo apt update && sudo apt install -y cloudflared

    # 验证安装
    if ! command -v cloudflared &> /dev/null; then
        echo "❌ Cloudflare Tunnel 安装失败"
        exit 1
    fi

    echo "✅ Cloudflare Tunnel 安装成功"
}

# 加入已有的Cloudflare Tunnel
join_existing_tunnel() {
    local token="$1"
    echo "使用提供的token加入Cloudflare Tunnel..."
    sudo cloudflared service install "$token"
    echo "Cloudflare Tunnel 已成功连接。"
}

# 主函数调用
check_root
install_cloudflared

# 检查是否提供了token参数
if [ -z "$1" ]; then
    echo "❌ 请提供Cloudflare Tunnel的token作为参数。"
    exit 1
fi

# 使用命令行参数传递token
join_existing_tunnel "$1"