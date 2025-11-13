#!/bin/bash
# cnwall-apply.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
NFT_TABLE="cnwall"
LOG="$DIR/cnwall.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [APPLY] $*" | tee -a "$LOG"; }

ENABLED=$(yq e '.enable_china_restriction' "$CONFIG")
[[ "$ENABLED" != "true" ]] && { log "中国限制已禁用"; exit 0; }

log "应用防火墙规则..."

NFT_RULES=$(
cat <<'EOF'
#!/usr/sbin/nft -f
flush table inet cnwall

table inet cnwall {
    set china { type ipv4_addr; flags interval; auto-merge; }
    set whitelist { type ipv4_addr; }
    set blacklist { type ipv4_addr; }

    chain docker_user {
        type filter hook input priority -200; policy accept;
        iifname "lo" accept
        ip saddr @whitelist accept
        ip saddr @blacklist counter drop
EOF
)

services=$(yq e '.services | keys | .[]' "$CONFIG")
for svc in $services; do
    [[ "$(yq e ".services.$svc.allow_lan" "$CONFIG")" == "true" ]] && \
        NFT_RULES+=$'\n        ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 } accept'
    ports=$(yq e ".services.$svc.ports[]" "$CONFIG")
    for p in $ports; do
        port=$(echo "$p" | yq e '.port' -)
        proto=$(echo "$p" | yq e '.protocol' -)
        NFT_RULES+=$'\n        ip saddr @china '"$proto"' dport '"$port"' accept'
    done
done

NFT_RULES+=$'\n        counter drop\n    }\n}'

tmp=$(mktemp)
echo "$NFT_RULES" > "$tmp"
nft -f "$tmp"
rm "$tmp"

log "规则应用成功"