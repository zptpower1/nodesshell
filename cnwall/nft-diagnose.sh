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
mapfile -t rules < <(echo "$chain_dump" | awk '{gsub(/^[[:space:]]+/, "", $0); if(NR==1) next; if($0 ~ /^}$/) next; if($0 ~ /^chain /) next; if($0 ~ /^type .* hook/) next; if($0 ~ /^policy /) next; print}')

table_dump=$(nft list table inet "$TABLE" 2>/dev/null || echo "")

# 优先使用 JSON 解析集合元素数量（更可靠）；无法使用时回退到文本解析
json_dump=$(nft -j list table inet "$TABLE" 2>/dev/null || echo "")
use_json=no
if [[ -n "$json_dump" ]]; then
  if [[ -x "$YQ" ]] || command -v yq >/dev/null 2>&1; then
    [[ -x "$YQ" ]] || YQ="$(command -v yq)"
    use_json=yes
  fi
fi

for setname in china whitelist blacklist; do
  if [[ "$use_json" == yes ]]; then
    elems=$("$YQ" e '.nftables[] | select(has("set")) | .set | select(.name=="'"$setname"'") | (.elements // []) | length' - <<< "$json_dump" 2>/dev/null | tail -n1)
    if [[ -z "$elems" ]]; then
      log "缺少集合 $setname"
    else
      log "集合 $setname: $elems 条目"
    fi
  else
    set_block=$(echo "$table_dump" | awk "/set $setname \{/,/\}/")
    if echo "$set_block" | grep -q "set $setname {"; then
      if echo "$set_block" | grep -q "elements"; then
        joined=$(echo "$set_block" | sed -n '/elements/,$p' | tr -d '\n')
        inner=$(echo "$joined" | sed -E 's/.*elements[[:space:]]*=\{([^}]*)\}.*/\1/')
        elems=$(echo "$inner" | tr -d ' ' | awk -F',' '{ if (length($0)==0 || $0 ~ /^[[:space:]]*$/) print 0; else print NF }')
        log "集合 $setname: $elems 条目"
      else
        log "集合 $setname: 空"
      fi
    else
      log "缺少集合 $setname"
    fi
  fi
done

if command -v ipset >/dev/null 2>&1; then
  cc=$(ipset list "$IPSET_CHINA" 2>/dev/null | sed -n 's/^Number of entries: \([0-9]\+\)$/\1/p' | head -1)
  cw=$(ipset list "$IPSET_WHITE" 2>/dev/null | sed -n 's/^Number of entries: \([0-9]\+\)$/\1/p' | head -1)
  cb=$(ipset list "$IPSET_BLACK" 2>/dev/null | sed -n 's/^Number of entries: \([0-9]\+\)$/\1/p' | head -1)
  log "ipset 统计: china=${cc:-0} whitelist=${cw:-0} blacklist=${cb:-0}"
  for setname in china whitelist blacklist; do
    if [[ "$use_json" == yes ]]; then
      nft_count=$("$YQ" e '.nftables[] | select(has("set")) | .set | select(.name=="'"$setname"'") | (.elements // []) | length' - <<< "$json_dump" 2>/dev/null | tail -n1)
      [[ -z "$nft_count" ]] && nft_count=0
    else
      set_block=$(echo "$table_dump" | awk "/set $setname \{/,/\}/")
      joined=$(echo "$set_block" | sed -n '/elements/,$p' | tr -d '\n')
      inner=$(echo "$joined" | sed -E 's/.*elements[[:space:]]*=\{([^}]*)\}.*/\1/')
      nft_count=$(echo "$inner" | tr -d ' ' | awk -F',' '{ if (length($0)==0 || $0 ~ /^[[:space:]]*$/) print 0; else print NF }')
    fi
    ipset_count_var="cc"
    [[ "$setname" == "whitelist" ]] && ipset_count_var="cw"
    [[ "$setname" == "blacklist" ]] && ipset_count_var="cb"
    ipset_count=$(eval echo "\${$ipset_count_var}")
    if [[ "${ipset_count:-0}" -gt 0 && "${nft_count:-0}" -eq 0 ]]; then
      log "警告: 集合 $setname 未同步（ipset>0, nft=0）"
    fi
  done
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
        has_china=$(printf '%s\n' "${rules[@]}" | grep -Eq "ip saddr @china .*${proto} dport ${port} .*accept" && echo yes || echo no)
        has_lan=no
        for rl in "${rules[@]}"; do
          echo "$rl" | grep -Eq "${proto} dport ${port}" || continue
          echo "$rl" | grep -q "ip saddr {" || continue
          echo "$rl" | grep -q "192.168.0.0/16" || continue
          echo "$rl" | grep -q "10.0.0.0/8" || continue
          echo "$rl" | grep -q "172.16.0.0/12" || continue
          echo "$rl" | grep -q "accept" || continue
          has_lan=yes; break
        done
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

allowed_re=(
  '^iifname "lo" .*accept$'
  '^ct state established,related .*accept$'
  '^ip saddr @whitelist .*accept$'
  '^ip saddr @blacklist .*drop$'
  '^counter .*accept$'
  '^tcp dport 22 .*accept$'
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
      allowed_re+=("^ip saddr @china .*${proto} dport ${port} .*accept$")
      # LAN 放行规则通过逐行匹配三段网段来识别，不加入固定顺序的正则
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
    # 允许 LAN 放行规则（不固定网段顺序），按服务端口/协议识别
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
          echo "$r" | grep -Eq "${proto} dport ${port}" || continue
          echo "$r" | grep -q "ip saddr {" || continue
          echo "$r" | grep -q "192.168.0.0/16" || continue
          echo "$r" | grep -q "10.0.0.0/8" || continue
          echo "$r" | grep -q "172.16.0.0/12" || continue
          echo "$r" | grep -q "accept" || continue
          ok=yes; break 2
        done
      done <<< "$services"
    fi
  fi
  if [[ "$ok" == no ]]; then
    log "多余规则: $r"
    extra_count=$((extra_count+1))
  fi
done

log "多余规则计数: $extra_count"

log "诊断完成"