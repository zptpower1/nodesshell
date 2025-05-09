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
# 网络优化
network_optimization() {
    echo "应用网络优化配置..."
    sysctl_config="
    fs.file-max = 6815744
    net.ipv4.tcp_no_metrics_save=1
    net.ipv4.tcp_ecn=0
    net.ipv4.tcp_frto=0
    net.ipv4.tcp_mtu_probing=0
    net.ipv4.tcp_rfc1337=0
    net.ipv4.tcp_sack=1
    net.ipv4.tcp_fack=1
    net.ipv4.tcp_window_scaling=1
    net.ipv4.tcp_adv_win_scale=1
    net.ipv4.tcp_moderate_rcvbuf=1
    net.core.rmem_max=33554432
    net.core.wmem_max=33554432
    net.ipv4.tcp_rmem=4096 87380 33554432
    net.ipv4.tcp_wmem=4096 16384 33554432
    net.ipv4.udp_rmem_min=8192
    net.ipv4.udp_wmem_min=8192
    net.ipv4.ip_forward=1
    net.ipv4.conf.all.route_localnet=1
    net.ipv4.conf.all.forwarding=1
    net.ipv4.conf.default.forwarding=1
    net.core.default_qdisc=fq
    net.ipv4.tcp_congestion_control=bbr
    net.ipv6.conf.all.forwarding=1
    net.ipv6.conf.default.forwarding=1
    "
    echo "$sysctl_config" | sudo tee /etc/sysctl.conf
    sudo sysctl -p
}

# 主函数调用
update_packages
enable_swap
network_optimization

echo "优化完成！"

