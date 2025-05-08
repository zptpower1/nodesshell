#!/bin/bash
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")/utils.sh"

# 生成 VLESS URL
generate_url() {
    local uuid="$1"
    local server_ip="$2"
    local port="$3"
    local node_name="$4"
    local name="$5"
    local host="$6"
    local pbk="$7"
    local sid="$8"

    local vless_url="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&host=${host}&fp=chrome&pbk=${pbk}&sid=${sid}&udp=true#${node_name:-$name}"
    local vless_url_base64=$(echo -n "${vless_url}" | base64 -w 0)

    echo "VLESS URL: ${vless_url}"
    echo "VLESS URL (Base64): ${vless_url_base64}"
}