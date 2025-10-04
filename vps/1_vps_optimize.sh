#!/bin/bash
# vps本地环境的检测和优化

# 更稳健的系统检测（兼容 Ubuntu/Debian）
detect_os() {
    # 读取 /etc/os-release 获取系统信息
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        OS_ID=${ID}
        OS_CODENAME=${VERSION_CODENAME}
    fi

    # 兜底：若未取得 codename，尝试 lsb_release
    if [ -z "${OS_CODENAME}" ] && command -v lsb_release >/dev/null 2>&1; then
        OS_CODENAME=$(lsb_release -cs)
    fi

    # 进一步兜底：从 /etc/debian_version 推断（仅 Debian）
    if [ -z "${OS_CODENAME}" ] && [ "${OS_ID}" = "debian" ] && [ -r /etc/debian_version ]; then
        # 简单映射：12->bookworm，13->trixie
        DEB_VER=$(sed 's/\..*$//' /etc/debian_version)
        case "${DEB_VER}" in
            12) OS_CODENAME="bookworm" ;;
            13) OS_CODENAME="trixie" ;;
        esac
    fi

    echo "检测到系统: ID=${OS_ID:-unknown}, CODENAME=${OS_CODENAME:-unknown}"
}

# 优化APT源
optimize_apt_sources() {
    echo "优化APT源..."
    detect_os

    local codename="${OS_CODENAME}"
    local sources_list="/etc/apt/sources.list"

    if [ "${OS_ID}" = "ubuntu" ]; then
        case "${codename}" in
            noble) # Ubuntu 24.04：采用 .sources 写法，保留官方签名
                local new_sources_list="/etc/apt/sources.list.d/ubuntu.sources"
                sudo cp -f ${new_sources_list} ${new_sources_list}.bak 2>/dev/null || true
                sudo tee ${new_sources_list} >/dev/null <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
                ;;
            jammy|focal|bionic)
                sudo cp -f ${sources_list} ${sources_list}.bak 2>/dev/null || true
                sudo tee ${sources_list} >/dev/null <<EOF
deb http://archive.ubuntu.com/ubuntu/ ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ ${codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ ${codename}-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
                ;;
            *)
                echo "未识别的 Ubuntu 版本：${codename}，保持现有源。"
                ;;
        esac
    elif [ "${OS_ID}" = "debian" ]; then
        case "${codename}" in
            bookworm|trixie)
                sudo cp -f ${sources_list} ${sources_list}.bak 2>/dev/null || true
                # Debian 12/13 推荐包含 non-free-firmware
                sudo tee ${sources_list} >/dev/null <<EOF
deb http://deb.debian.org/debian ${codename} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-backports main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
                ;;
            *)
                echo "未识别的 Debian 版本：${codename}，保持现有源。"
                ;;
        esac
    else
        echo "未识别的系统 ID：${OS_ID:-unknown}，保持现有源。"
    fi
}

# 更新包
update_packages() {
    echo "更新系统包..."
    sudo apt update && sudo apt -y upgrade
    sudo apt -y autoremove

    # 安装常用工具
    echo "安装常用工具..."
    sudo apt -y install curl wget git htop unzip uuid-runtime vim
    sudo apt -y install net-tools #网络工具
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
    # 避免覆盖系统主配置，改为写入 sysctl.d
    local sysctl_dropin="/etc/sysctl.d/99-net-optimization.conf"
    echo "$sysctl_config" | sudo tee "$sysctl_dropin" >/dev/null
    sudo sysctl -p "$sysctl_dropin" || sudo sysctl --system
}

# 优化DNS设置
optimize_dns() {
    echo "优化DNS设置..."
    # 优先通过 systemd-resolved 管理（Ubuntu/Debian默认启用），否则退回直接写 resolv.conf
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved; then
        local resolved_conf="/etc/systemd/resolved.conf"
        sudo cp -f "$resolved_conf" "${resolved_conf}.bak" 2>/dev/null || true
        sudo tee "$resolved_conf" >/dev/null <<'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=8.8.8.8 1.1.1.1
EOF
        sudo systemctl restart systemd-resolved
        # 确保 resolv.conf 指向 stub（若非符号链接则提示）
        if [ ! -L /etc/resolv.conf ]; then
            sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        fi
        echo "DNS已通过 systemd-resolved 配置为 Cloudflare。"
    else
        local resolv_conf="/etc/resolv.conf"
        sudo cp -f "$resolv_conf" "${resolv_conf}.bak" 2>/dev/null || true
        echo "nameserver 1.1.1.1" | sudo tee "$resolv_conf" >/dev/null
        echo "nameserver 1.0.0.1" | sudo tee -a "$resolv_conf" >/dev/null
        echo "DNS设置已优化为使用Cloudflare的DNS服务器。"
    fi
}

# 主函数调用
optimize_dns
optimize_apt_sources
network_optimization
update_packages
enable_swap

echo "优化完成！"

