#!/bin/bash
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")/utils.sh"

# 生成 Shadowsocks URL
generate_url() {
    local method="$1"
    local server_key="$2"
    local realpwd="$3"
    local server_ip="$4"
    local port="$5"
    local node_name="$6"
    local name="$7"

    local config="${method}:${server_key}%3A${realpwd}@${server_ip}:${port}"
    local ss_url="ss://${config}#${node_name:-$name}"
    local config_base64=$(echo -n "${config}" | base64 -w 0)
    local ss_url_base64="ss://${config_base64}#${node_name:-$name}"

    echo "Shadowsocks URL: ${ss_url}"
    echo "Shadowsocks URL (Base64): ${ss_url_base64}"
}