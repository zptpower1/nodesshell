#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 获取最新版本号
get_latest_version() {
    curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v1.15.3"
}

# 获取下载URL
get_download_url() {
    local version=$(get_latest_version)
    if [ -z "$version" ]; then
        echo "❌ 获取版本号失败，使用默认版本 v1.15.3"
        version="v1.15.3"
    fi
    echo "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/shadowsocks-${version}.x86_64-unknown-linux-gnu.tar.xz"
}

# 从二进制包安装
install_from_binary() {
    local temp_dir="/tmp/ssrust"
    local download_url=$(get_download_url)
    
    if [ -z "$download_url" ]; then
        echo "❌ 获取下载链接失败"
        return 1
    fi
    
    mkdir -p "${temp_dir}"
    echo "📥 下载预编译包..."
    if ! wget -q "$download_url" -O "${temp_dir}/ss.tar.xz"; then
        echo "❌ 下载失败"
        return 1
    fi
    
    echo "📦 解压安装..."
    if ! tar -xf "${temp_dir}/ss.tar.xz" -C "/usr/local/bin/"; then
        echo "❌ 解压失败"
        return 1
    fi
    
    chmod +x "${SS_BIN}"
    rm -rf "${temp_dir}"
}

# 安装服务
install() {
    check_root
    echo "📦 开始安装 SS2022..."
    
    echo "ℹ️ 使用预编译二进制包安装..."
    install_from_binary
    
    setup_service
    setup_config
    create_symlinks
    echo "✅ 安装完成！"
}

# 卸载服务
uninstall() {
    check_root
    echo "⚠️ 即将卸载 SS2022，并删除其所有配置文件和程序。"
    
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    
    rm -f "${SERVICE_FILE}" "${CONFIG_PATH}" "${USERS_PATH}" "${SS_BIN}"
    rm -rf "${SS_BASE_PATH}" "${LOG_DIR}"
    
    rm -f "${SCRIPT_DIR}/configs" "${SCRIPT_DIR}/logs"
    
    echo "✅ 卸载完成。"
}

# 升级服务
upgrade_shadowsocks() {
    check_root
    echo "🔄 正在检查更新..."
    local current_version=$(${SS_BIN} --version 2>/dev/null | awk '{print $2}')
    local latest_version=$(get_latest_version)
    
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
    
    install_from_binary
    restart_service
    echo "✅ 升级完成"
}