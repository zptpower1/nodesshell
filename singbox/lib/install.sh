#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 获取最新版本
get_latest_version() {
    curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | \
    jq -r .tag_name | \
    sed 's/v//'
}

# 下载并安装sing-box
install_sing_box() {
    echo "📥 正在安装 Sing-box..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
    esac

    LATEST_VERSION=$(get_latest_version)
    wget -O /tmp/sing-box.tar.gz \
        "https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
    tar -xzf /tmp/sing-box.tar.gz -C /tmp
    mv /tmp/sing-box-${LATEST_VERSION}-linux-${ARCH}/sing-box /usr/local/bin/
    rm -rf /tmp/sing-box*
}