#!/bin/bash
# vps本地环境的检测和优化

# 更新包
update_packages() {
    echo "更新系统包..."
    sudo apt update && sudo apt upgrade -y
}

# 检测当前swap状态
check_swap() {
    echo "检测当前swap状态..."
    current_swap=$(swapon --show | awk 'NR==2 {print $3}')
    if [ -n "$current_swap" ]; then
        echo "当前swap大小为: $current_swap"
        read -p "是否调整swap大小？(y/n): " adjust_swap
        if [ "$adjust_swap" != "y" ]; then
            echo "保持当前swap设置。"
            return 1
        fi
    fi
    return 0
}

# 开启swap
enable_swap() {
    if check_swap; then
        read -p "请输入swap大小(默认4G): " swap_size
        swap_size=${swap_size:-4G}
        
        # 检查是否已经存在swap文件
        if [ -f /swapfile ]; then
            echo "检测到现有的swap文件。"
            read -p "是否覆盖现有的swap文件？(y/n): " overwrite_swap
            if [ "$overwrite_swap" != "y" ]; then
                echo "保持当前swap设置。"
                return
            fi
            sudo swapoff /swapfile
            sudo rm /swapfile
        fi

        echo "开启swap大小为: $swap_size"
        sudo fallocate -l $swap_size /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
}

# 开启BBR
enable_bbr() {
    echo "开启BBR..."
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    fi
    sudo sysctl -p
}

# 主函数调用
update_packages
enable_swap
enable_bbr

echo "优化完成！"

