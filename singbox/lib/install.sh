#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 获取最新版本
get_latest_version() {
    local version
    version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name 2>/dev/null | sed 's/^v//')
    if [ -z "$version" ] || [ "$version" = "null" ]; then
        version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases | jq -r '.[0].tag_name' 2>/dev/null | sed 's/^v//')
    fi
    echo "$version"
}

# 下载并安装sing-box,制作自启动服务
install_sing_box() {
    echo "📥 正在安装 Sing-box..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
    esac

    LATEST_VERSION=$(get_latest_version)
    if [ -z "$LATEST_VERSION" ]; then
        echo "❌ 无法获取最新版本号，请稍后重试或检查网络/GitHub API 限流。"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/singbox.XXXXXX)
    local tar_file="$tmp_dir/sing-box.tar.gz"
    local url="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"

    echo "🔗 下载地址: ${url}"
    if ! wget -O "$tar_file" "$url"; then
        echo "❌ 下载失败: $url"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! tar -xzf "$tar_file" -C "$tmp_dir"; then
        echo "❌ 解压失败: $tar_file"
        rm -rf "$tmp_dir"
        return 1
    fi

    local bin_path="$tmp_dir/sing-box-${LATEST_VERSION}-linux-${ARCH}/sing-box"
    if [ ! -f "$bin_path" ]; then
        echo "❌ 未找到二进制文件: $bin_path"
        rm -rf "$tmp_dir"
        return 1
    fi

    mv "$bin_path" "$SING_BIN"
    chmod +x "$SING_BIN"
    rm -rf "$tmp_dir"

    # 创建系统服务
    service_install
    # 初始化基础配置文件
    config_create_base
    # 批量配置防火墙规则
    allow_firewall
    
    echo "✅ Sing-box 已安装"
}

# 升级 sing-box
upgrade_sing_box() {
    echo "🔄 检查更新..."
    local current_version=$("${SING_BIN}" version 2>/dev/null | grep 'sing-box version' | awk '{print $3}')
    local latest_version=$(get_latest_version)
    
    if [ -z "$current_version" ]; then
        echo "❌ 未检测到已安装的 sing-box"
        return 1
    fi
    
    if [ "$current_version" = "$latest_version" ]; then
        echo "✅ 当前已是最新版本：${current_version}"
        return 0
    fi
    
    echo "📦 发现新版本：${latest_version}"
    echo "当前版本：${current_version}"
    
    read -p "是否升级？(y/N) " confirm
    if [ "$confirm" != "y" ]; then
        echo "❌ 已取消升级"
        return 1
    fi
    
    # 备份当前配置
    config_backup
    
    # 安装新版本
    install_sing_box
    
    # 重启服务
    service_restart

    echo "✅ 升级完成"
    echo "新版本：$("${SING_BIN}" version | grep 'sing-box version' | awk '{print $3}')"
}

# 卸载 sing-box
uninstall_sing_box() {
    echo "⚠️ 即将卸载 sing-box，此操作将删除所有配置文件。"
    read -p "是否继续？(y/N) " confirm
    if [ "$confirm" != "y" ]; then
        echo "❌ 已取消卸载"
        return 1
    fi
    
    # 停止服务
    if pgrep -x "sing-box" > /dev/null; then
        echo "🛑 停止服务..."
        kill $(pgrep -x "sing-box")
    fi
    
    # 备份配置
    config_backup
    
    # 删除文件
    echo "🗑️ 删除文件..."
    rm -f "${SING_BIN}"

    # 删除服务文件
    service_remove

    #批量删除防火墙规则
    delete_firewall
    
    echo "✅ 卸载完成"
}