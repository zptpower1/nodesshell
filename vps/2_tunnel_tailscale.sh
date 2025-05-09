#!/bin/bash

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 此脚本需要以 root 权限运行"
        exit 1
    fi
}

# 安装Tailscale
install_tailscale() {
    # 检查是否已经安装Tailscale
    if command -v tailscale &> /dev/null; then
        echo "Tailscale 已经安装。"
        read -p "是否要覆盖安装？(y/n): " overwrite
        if [ "$overwrite" != "y" ]; then
            echo "保持当前安装。"
            return
        fi
        # 如果选择覆盖安装，先卸载
        uninstall_tailscale
    fi

    echo "安装Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh

    # 交互式输入授权密钥
    read -p "请输入Tailscale授权密钥: " auth_key
    if [ -z "$auth_key" ]; then
        echo "❌ 未提供有效的授权密钥。"
        exit 1
    fi

    # 使用授权密钥启动Tailscale
    sudo tailscale up --auth-key="$auth_key"

    # 验证安装
    if ! command -v tailscale &> /dev/null; then
        echo "❌ Tailscale 安装失败"
        exit 1
    fi

    echo "✅ Tailscale 安装成功"
}

# 启动Tailscale并加入网络
start_tailscale() {
    echo "启动Tailscale并加入网络..."
    sudo tailscale up

    if [ $? -ne 0 ]; then
        echo "❌ Tailscale 启动失败"
        exit 1
    fi

    echo "✅ Tailscale 已成功启动并加入网络"
}

# 停止Tailscale
stop_tailscale() {
    echo "停止Tailscale..."
    sudo tailscale down

    if [ $? -ne 0 ]; then
        echo "❌ Tailscale 停止失败"
        exit 1
    fi

    echo "✅ Tailscale 已成功停止"
}

# 卸载Tailscale
uninstall_tailscale() {
    echo "停止Tailscale..."
    sudo tailscale down

    if [ $? -ne 0 ]; then
        echo "❌ Tailscale 停止失败"
        exit 1
    fi

    echo "卸载Tailscale..."
    sudo apt remove --purge -y tailscale

    if command -v tailscale &> /dev/null; then
        echo "❌ Tailscale 卸载失败"
        exit 1
    fi

    echo "✅ Tailscale 已成功卸载"
}

# 主函数调用
check_root

case "$1" in
    install)
        install_tailscale
        ;;
    start)
        start_tailscale
        ;;
    stop)
        stop_tailscale
        ;;
    uninstall)
        uninstall_tailscale
        ;;
    *)
        echo "❌ 无效的命令。使用 'install'、'start'、'stop' 或 'uninstall'。"
        exit 1
        ;;
esac