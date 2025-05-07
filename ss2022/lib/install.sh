#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 获取最新版本号
function get_latest_version() {
    local version
    version=$(curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        echo "v1.15.3"
        return 1
    fi
    echo "$version"
    return 0
}

# 获取下载URL
function get_download_url() {
    local version=$(get_latest_version)
    local status=$?
    local download_url
    
    if [ $status -ne 0 ]; then
        echo >&2 "⚠️ 获取版本号失败，使用默认版本：${version}"
    else
        echo >&2 "✅ 获取到最新版本：${version}"
    fi
    
    download_url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/shadowsocks-${version}.x86_64-unknown-linux-gnu.tar.xz"
    echo "${download_url}"
}

# 从二进制包安装
install_from_binary() {
    local temp_dir="/tmp/ssrust"
    local download_url
    
    # 获取下载地址并将状态信息重定向到stderr
    download_url=$(get_download_url)
    
    echo "🔗 下载地址：${download_url}"
    
    mkdir -p "${temp_dir}"
    echo "📥 开始下载预编译包..."
    
    if ! wget -q "$download_url" -O "${temp_dir}/ss.tar.xz"; then
        echo "❌ 下载失败，请检查："
        echo "  1. 网络连接是否正常"
        echo "  2. 是否可以访问 GitHub"
        echo "  3. 下载地址是否有效"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    if [ ! -s "${temp_dir}/ss.tar.xz" ]; then
        echo "❌ 下载的文件为空"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    echo "📦 解压安装..."
    if ! tar -xf "${temp_dir}/ss.tar.xz" -C "/usr/local/bin/" 2>/dev/null; then
        echo "❌ 解压失败，可能原因："
        echo "  1. 下载的文件可能损坏"
        echo "  2. 文件格式不正确"
        echo "  3. 目标目录无写入权限"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    if [ ! -f "${SS_BIN}" ]; then
        echo "❌ 未找到可执行文件：${SS_BIN}"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    chmod +x "${SS_BIN}"
    rm -rf "${temp_dir}"
    return 0
}

# 安装服务
install() {
    check_root
    echo "📦 开始安装 SS2022..."
    
    if [[ -f "$CONFIG_PATH" ]]; then
        echo "⚠️ 检测到已有配置文件：$CONFIG_PATH"
        read -p "是否覆盖已有配置并继续安装？(y/N): " CONFIRM
        case "$CONFIRM" in
            [yY]) backup_config ;;
            *) echo "❌ 已取消安装操作。"; exit 1 ;;
        esac
    fi
    
    echo "ℹ️ 使用预编译二进制包安装..."
    if ! install_from_binary; then
        echo "❌ 安装失败"
        exit 1
    fi
    
    if ! setup_config; then
        echo "❌ 配置文件创建失败"
        exit 1
    fi
    
    if ! setup_service; then
        echo "❌ 服务配置失败"
        exit 1
    fi
    
    # 配置防火墙规则
    echo "🛡️ 配置防火墙规则..."
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${SERVER_PORT}"/tcp
        ufw allow "${SERVER_PORT}"/udp
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport "${SERVER_PORT}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "${SERVER_PORT}" -j ACCEPT
        iptables -C INPUT -p udp --dport "${SERVER_PORT}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport "${SERVER_PORT}" -j ACCEPT
    fi
    
    create_symlinks
    
    # 同步配置文件
    if ! sync_config; then
        echo "⚠️ 配置同步失败，但不影响安装"
    fi
    
    echo "✅ 安装完成！"
    show_config
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
    echo "✅ 升级完成"
}

