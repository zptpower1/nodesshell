#!/bin/bash
# vps本地环境的检测和优化

# 优化APT源
optimize_apt_sources() {
    echo "优化APT源..."
    local codename=$(lsb_release -cs)

    # 根据系统版本设置新的APT源
    case "$codename" in
        focal|bionic)
            local sources_list="/etc/apt/sources.list"
            sudo cp $sources_list ${sources_list}.bak
            echo "deb http://archive.ubuntu.com/ubuntu/ $codename main restricted universe multiverse" | sudo tee $sources_list
            echo "deb http://archive.ubuntu.com/ubuntu/ $codename-updates main restricted universe multiverse" | sudo tee -a $sources_list
            echo "deb http://archive.ubuntu.com/ubuntu/ $codename-backports main restricted universe multiverse" | sudo tee -a $sources_list
            echo "deb http://security.ubuntu.com/ubuntu $codename-security main restricted universe multiverse" | sudo tee -a $sources_list
            ;;
        noble)
            local new_sources_list="/etc/apt/sources.list.d/ubuntu.sources"
            echo "Types: deb" | sudo tee $new_sources_list
            echo "URIs: http://mirror.fsmg.org/ubuntu/" | sudo tee -a $new_sources_list
            echo "Suites: noble noble-updates noble-backports noble-security" | sudo tee -a $new_sources_list
            echo "Components: main restricted universe multiverse" | sudo tee -a $new_sources_list
            echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" | sudo tee -a $new_sources_list

            echo "Types: deb" | sudo tee -a $new_sources_list
            echo "URIs: http://archive.ubuntu.com/ubuntu/" | sudo tee -a $new_sources_list
            echo "Suites: noble noble-updates noble-backports" | sudo tee -a $new_sources_list
            echo "Components: main restricted universe multiverse" | sudo tee -a $new_sources_list
            echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" | sudo tee -a $new_sources_list

            echo "Types: deb" | sudo tee -a $new_sources_list
            echo "URIs: http://security.ubuntu.com/ubuntu/" | sudo tee -a $new_sources_list
            echo "Suites: noble-security" | sudo tee -a $new_sources_list
            echo "Components: main restricted universe multiverse" | sudo tee -a $new_sources_list
            echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" | sudo tee -a $new_sources_list
            ;;
        *)
            echo "未识别的系统版本：$codename，使用默认源。"
            ;;
    esac
}

# 更新包
update_packages() {
    echo "更新系统包..."
    sudo apt update && sudo apt upgrade
    sudo apt autoremove

    # 安装常用工具
    echo "安装常用工具..."
    sudo apt install curl wget git htop unzip
    sudo apt install net-tools #网络工具
    # sudo apt install iftop #查看实时网络流量
    # sudo apt install nethogs  #定位占用带宽的进程
    # sudo apt install vnstat #历史流量统计
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
    net.ipv4.tcp_mtu_probing=1
    net.ipv4.tcp_rfc1337=0
    net.ipv4.tcp_sack=1
    net.ipv4.tcp_fack=1
    net.ipv4.tcp_window_scaling=1
    net.ipv4.tcp_adv_win_scale=1
    net.ipv4.tcp_moderate_rcvbuf=1
    net.core.rmem_max=33554432
    net.core.wmem_max=33554432
    net.ipv4.tcp_rmem=4096 1048576 33554432
    net.ipv4.tcp_wmem=4096 1048576 33554432
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

# 优化DNS设置
optimize_dns() {
    echo "优化DNS设置..."
    # 使用Cloudflare的DNS服务器
    local resolv_conf="/etc/resolv.conf"
    sudo cp $resolv_conf ${resolv_conf}.bak
    echo "nameserver 1.1.1.1" | sudo tee $resolv_conf
    echo "nameserver 1.0.0.1" | sudo tee -a $resolv_conf
    echo "DNS设置已优化为使用Cloudflare的DNS服务器。"
}

# 主函数调用
optimize_dns
optimize_apt_sources
network_optimization
update_packages
enable_swap

echo "优化完成！"

