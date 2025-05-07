#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 从二进制包安装
install_from_binary() {
    local temp_dir="/tmp/ssrust"
    local download_url=$(get_download_url)
    
    mkdir -p "${temp_dir}"
    echo "📥 下载预编译包..."
    wget "${download_url}" -O "${temp_dir}/ss.tar.xz"
    
    echo "📦 解压安装..."
    tar -xf "${temp_dir}/ss.tar.xz" -C "/usr/local/bin/"
    chmod +x "${SS_BIN}"
}

# 安装服务
install() {
    check_root
    echo "📦 开始安装 SS2022..."
    
    if command -v apt-get &> /dev/null; then
        echo "ℹ️ 尝试通过 apt 安装 shadowsocks-rust..."
        apt-get update
        if apt-get install -y shadowsocks-rust; then
            echo "✅ 通过apt安装成功"
        else
            echo "📌 apt安装失败，尝试使用预编译二进制包安装..."
            install_from_binary
        fi
    else
        echo "ℹ️ 使用预编译二进制包安装..."
        install_from_binary
    fi
    
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
    
    rm -f "${SCRIPT_DIR}/ss2022_config" "${SCRIPT_DIR}/ss2022_logs"
    
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