#!/bin/bash
# cnwall-apply.sh
# 修复：移除 shell 重定向，使用 nft 原生语法
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
NFT_TABLE="cnwall"
LOG="$DIR/cnwall.log"
YQ="$DIR/yq"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [APPLY] $*" | tee -a "$LOG"; }

ENABLED=$("$YQ" e '.enable_china_restriction' "$CONFIG")
[[ "$ENABLED" != "true" ]] && { log "中国限制已禁用"; exit 0; }

log "应用防火墙规则..."

# 临时文件
tmp=$(mktemp)

# 1. 如果旧表存在则删除（避免 nft -f 在脚本里因不存在而报错）
if nft list table inet "$NFT_TABLE" >/dev/null 2>&1; then
    nft delete table inet "$NFT_TABLE" || true
fi

# 2. 构造 nft 脚本（纯 nft 语法）
cat > "$tmp" <<'EOF'
# 创建新表
add table inet cnwall;

add set inet cnwall china { type ipv4_addr; flags interval; auto-merge; }
add set inet cnwall whitelist { type ipv4_addr; }
add set inet cnwall blacklist { type ipv4_addr; }

add chain inet cnwall docker_user { type filter hook input priority -200; policy drop; }

# 基础规则
add rule inet cnwall docker_user iifname "lo" accept
add rule inet cnwall docker_user ip saddr @whitelist accept
add rule inet cnwall docker_user ip saddr @blacklist counter drop
EOF

# 2. 动态添加服务规则
services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue

    allow_lan=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")
    [[ "$allow_lan" == "true" ]] && \
        echo "add rule inet cnwall docker_user ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 } accept" >> "$tmp"

    ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
    port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
    for ((i=0; i<port_count; i++)); do
        port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
        proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
        echo "add rule inet cnwall docker_user ip saddr @china $proto dport $port accept" >> "$tmp"
    done
done <<< "$services"

# 3. 结尾
echo "add rule inet cnwall docker_user counter drop" >> "$tmp"

# 4. 执行
if ! output=$(nft -f "$tmp" 2>&1); then
    echo "$output" | tee -a "$LOG" 1>/dev/null
    log "nft 应用失败"
    rm -f "$tmp"
    exit 1
fi

rm "$tmp"
log "规则应用成功"