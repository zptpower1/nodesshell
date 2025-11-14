#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
LOG="$DIR/cnwall.log"
TABLE="cnwall"
CHAIN="docker_user"
YQ="$DIR/yq"
IPSET_CHINA="cnwall_china"
IPSET_WHITE="cnwall_whitelist"
IPSET_BLACK="cnwall_blacklist"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [NFTCHECK] $*" | tee -a "$LOG"; }

command -v nft >/dev/null 2>&1 || { log "未检测到 nft"; exit 1; }

if ! nft list table inet "$TABLE" >/dev/null 2>&1; then
  log "未检测到表 $TABLE"
  exit 0
fi

policy_line=$(nft list chain inet "$TABLE" "$CHAIN" 2>/dev/null | grep -m1 'policy' || true)
log "链策略: ${policy_line:-未知}"

chain_dump=$(nft list chain inet "$TABLE" "$CHAIN" 2>/dev/null || echo "")

for setname in china whitelist blacklist; do
  if nft list set inet "$TABLE" "$setname" >/dev/null 2>&1; then
    if nft list set inet "$TABLE" "$setname" | grep -q 'elements'; then
      elems=$(nft list set inet "$TABLE" "$setname" | sed -n '/elements/,$p' | sed '1d' | tr -d ' \n' | sed 's/,$//' | tr ',' '\n' | wc -l | tr -d ' ')
      log "集合 $setname: $elems 条目"
    else
      log "集合 $setname: 空"
    fi
  else
    log "缺少集合 $setname"
  fi
done

if command -v ipset >/dev/null 2>&1; then
  cc=$(ipset list "$IPSET_CHINA" 2>/dev/null | sed -n 's/^Number of entries: \([0-9]\+\)$/\1/p' | head -1)
  cw=$(ipset list "$IPSET_WHITE" 2>/dev/null | sed -n 's/^Number of entries: \([0-9]\+\)$/\1/p' | head -1)
  cb=$(ipset list "$IPSET_BLACK" 2>/dev/null | sed -n 's/^Number of entries: \([0-9]\+\)$/\1/p' | head -1)
  log "ipset 统计: china=${cc:-0} whitelist=${cw:-0} blacklist=${cb:-0}"
fi

if echo "$chain_dump" | grep -q 'ct state established,related'; then
  log "基础规则: established,related 存在"
else
  log "基础规则: established,related 缺失"
fi

if [[ -x "$YQ" ]] || command -v yq >/dev/null 2>&1; then
  [[ -x "$YQ" ]] || YQ="$(command -v yq)"
  services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || echo "")
  if [[ -n "$services" ]]; then
    while IFS= read -r svc; do
      [[ -z "$svc" ]] && continue
      ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
      port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
      for ((i=0; i<port_count; i++)); do
        port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
        proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
        has_china=$(echo "$chain_dump" | grep -q "ip saddr @china $proto dport $port" && echo yes || echo no)
        has_lan=$(echo "$chain_dump" | grep -q "\{ 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 \} $proto dport $port" && echo yes || echo no)
        log "服务 $svc 端口 $port/$proto: china规则=$has_china lan规则=$has_lan"
      done
    done <<< "$services"
  else
    log "无服务配置"
  fi
else
  log "未检测到 yq，跳过服务规则检查"
fi

# 检查多余规则（不在预期集合内的规则）
mapfile -t rules < <(echo "$chain_dump" | sed -n '/{/,/}/p' | sed '1d;$d' | grep -v -E 'type .* hook|policy ' | sed 's/^\s*//')

allowed_re=(
  '^iifname "lo" accept$'
  '^ct state established,related accept$'
  '^ip saddr @whitelist accept$'
  '^ip saddr @blacklist (counter )?drop$'
  '^counter accept$'
  '^tcp dport 22 accept$'
)

extra_count=0
if [[ -x "$YQ" ]] || command -v yq >/dev/null 2>&1; then
  [[ -x "$YQ" ]] || YQ="$(command -v yq)"
  services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || echo "")
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
    port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
    for ((i=0; i<port_count; i++)); do
      port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
      proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
      allowed_re+=("^ip saddr @china $proto dport $port accept$")
      allowed_re+=("^ip saddr \{ 192\.168\.0\.0/16, 10\.0\.0\.0/8, 172\.16\.0\.0/12 \} $proto dport $port accept$")
    done
  done <<< "$services"
fi

for r in "${rules[@]}"; do
  ok=no
  for re in "${allowed_re[@]}"; do
    if echo "$r" | grep -Eq "$re"; then
      ok=yes
      break
    fi
  done
  if [[ "$ok" == no ]]; then
    log "多余规则: $r"
    extra_count=$((extra_count+1))
  fi
done

log "多余规则计数: $extra_count"

log "诊断完成"