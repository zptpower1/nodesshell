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
    sudo apt update

    # 获取当前安装的版本
    current_version=$(cloudflared --version 2>/dev/null | awk '{print $2}')
    # 获取可用的版本
    available_version=$(apt-cache policy cloudflared | grep Candidate | awk '{print $2}')

    if [ "$current_version" == "$available_version" ]; then
        echo "Cloudflare Tunnel 已是最新版本，跳过安装。"
        return
    fi

    echo "安装或更新Cloudflare Tunnel..."
    sudo apt install -y cloudflared

    # 验证安装
    if ! command -v cloudflared &> /dev/null; then
        echo "❌ Cloudflare Tunnel 安装失败"
        exit 1
    fi

    echo "✅ Cloudflare Tunnel 安装成功"
}

# 卸载Cloudflare Tunnel
uninstall_cloudflared() {
    echo "卸载Cloudflare Tunnel..."
    sudo apt remove --purge -y cloudflared

    if command -v cloudflared &> /dev/null; then
        echo "❌ Cloudflare Tunnel 卸载失败"
        exit 1
    fi

    echo "✅ Cloudflare Tunnel 已成功卸载"
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

case "$1" in
    install)
        install_cloudflared
        if [ -z "$2" ]; then
            echo "请输入Cloudflare Tunnel的token："
            read token
            if [ -z "$token" ]; then
                echo "❌ 未提供有效的token。"
                exit 1
            fi
        else
            token="$2"
        fi
        join_existing_tunnel "$token"
        ;;
    uninstall)
        uninstall_cloudflared
        ;;
    *)
        echo "❌ 无效的命令。使用 'install' 或 'uninstall'。"
        exit 1
        ;;
esac