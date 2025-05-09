#!/bin/bash

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 此脚本需要以 root 权限运行"
        exit 1
    fi
}

# 更新包管理器并安装Cloudflare WARP
install_warp() {
    echo "设置Cloudflare WARP的公钥和APT仓库..."
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list

    echo "更新系统包并安装Cloudflare WARP..."
    sudo apt update && sudo apt install cloudflare-warp

    echo "启用IP转发..."
    sudo sysctl -w net.ipv4.ip_forward=1

    echo "Cloudflare WARP 安装成功"
}

# 卸载Cloudflare WARP
uninstall_warp() {
    echo "卸载Cloudflare WARP..."
    sudo apt remove --purge -y cloudflare-warp

    echo "✅ Cloudflare WARP 已成功卸载"
}

# 安装Cloudflare Tunnel
install_tunnel() {
    echo "安装Cloudflare Tunnel..."
    sudo apt install -y cloudflared

    if ! command -v cloudflared &> /dev/null; then
        echo "❌ Cloudflare Tunnel 安装失败"
        exit 1
    fi

    echo "✅ Cloudflare Tunnel 安装成功"
}

# 卸载Cloudflare Tunnel
uninstall_tunnel() {
    echo "卸载Cloudflare Tunnel..."
    sudo apt remove --purge -y cloudflared

    if command -v cloudflared &> /dev/null; then
        echo "❌ Cloudflare Tunnel 卸载失败"
        exit 1
    fi

    echo "✅ Cloudflare Tunnel 已成功卸载"
}

# 使用令牌运行WARP Connector
run_warp_connector() {
    local token="$1"
    echo "使用提供的token运行WARP Connector..."
    warp-cli connector new "$token"
    warp-cli connect
    echo "Cloudflare WARP 已成功连接。"
}

# 主函数调用
check_root

case "$1" in
    install_warp)
        install_warp
        if [ -z "$2" ]; then
            echo "请输入Cloudflare WARP的token："
            read token
            if [ -z "$token" ]; then
                echo "❌ 未提供有效的token。"
                exit 1
            fi
        else
            token="$2"
        fi
        run_warp_connector "$token"
        ;;
    uninstall_warp)
        uninstall_warp
        ;;
    install_tunnel)
        install_tunnel
        ;;
    uninstall_tunnel)
        uninstall_tunnel
        ;;
    *)
        echo "❌ 无效的命令。使用 'install_warp'、'uninstall_warp'、'install_tunnel' 或 'uninstall_tunnel'。"
        exit 1
        ;;
esac