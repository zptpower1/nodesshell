#!/bin/bash
# cnwall-update.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
IPSET_CHINA="cnwall_china"
IPSET_WHITE="cnwall_whitelist"
IPSET_BLACK="cnwall_blacklist"
APNIC_URL="https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"
LOG="$DIR/cnwall.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [UPDATE] $*" | tee -a "$LOG"; }

log "更新中国 IP + 白/黑名单..."

# 中国 IP
tmp="/tmp/cnwall_china_$$.txt"
wget -qO- "$APNIC_URL" | grep 'apnic|CN|ipv4|' | \
  awk -F'|' '{printf "%s/%d\n", $4, 32-log($5)/log(2)}' > "$tmp"

new_set="${IPSET_CHINA}_new"
ipset create "$new_set" hash:net -exist || ipset flush "$new_set"
while read cidr; do ipset add "$new_set" "$cidr" -exist; done < "$tmp"
ipset swap "$new_set" "$IPSET_CHINA" || true
ipset destroy "$new_set" || true
rm "$tmp"

# 白名单
ipset create "$IPSET_WHITE" hash:ip -exist || ipset flush "$IPSET_WHITE"
yq e '.whitelist[]' "$CONFIG" 2>/dev/null | while read ip; do
  [[ -n "$ip" ]] && ipset add "$IPSET_WHITE" "$ip" -exist
done || true

# 黑名单
ipset create "$IPSET_BLACK" hash:ip -exist || ipset flush "$IPSET_BLACK"
yq e '.blacklist[]' "$CONFIG" 2>/dev/null | while read ip; do
  [[ -n "$ip" ]] && ipset add "$IPSET_BLACK" "$ip" -exist
done || true

log "更新完成"