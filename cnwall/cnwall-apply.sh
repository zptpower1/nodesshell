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

# 1. 构造 nft 脚本（纯 nft 语法）
cat > "$tmp" <<'EOF'
#!/usr/sbin/nft -f

# 安全删除旧表（如果存在）
delete table inet cnwall;

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

# 4. 执行（忽略 delete 错误）
if ! nft -f "$tmp"; then
    # 如果是 "table does not exist"，忽略
    if nft -f "$tmp" 2>&1 | grep -q "No such file or directory"; then
        log "旧表不存在elf不存在，已忽略"
        # 重新创建
        sed -i '/delete table/d' "$tmp"
        nft -f "$tmp"
    else
        log "nft 应用失败"
        rm "$tmp"
        exit 1
    fi
fi

rm "$tmp"
log "规则应用成功"