#!/bin/bash
# cnwall-apply.sh
# 修复：flush 前先检查 table 是否存在
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

# 1. 构造 nft 脚本（容错版）
cat > "$tmp" <<'EOF'
#!/usr/sbin/nft -f

# 删除旧表（如果存在）
delete table inet cnwall 2>/dev/null || true

# 创建新表
table inet cnwall {
    set china { type ipv4_addr; flags interval; auto-merge; }
    set whitelist { type ipv4_addr; }
    set blacklist { type ipv4_addr; }

    chain docker_user {
        type filter hook input priority -200; policy drop;

        iifname "lo" accept
        ip saddr @whitelist accept
        ip saddr @blacklist counter drop
EOF

# 2. 动态添加服务规则
services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue

    allow_lan=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")
    [[ "$allow_lan" == "true" ]] && \
        echo "        ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 } accept" >> "$tmp"

    ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
    port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
    for ((i=0; i<port_count; i++)); do
        port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
        proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
        echo "        ip saddr @china $proto dport $port accept" >> "$tmp"
    done
done <<< "$services"

# 3. 结尾
cat >> "$tmp" <<'EOF'
        counter drop
    }
}
EOF

# 4. 执行
nft -f "$tmp"
rm "$tmp"

log "规则应用成功"