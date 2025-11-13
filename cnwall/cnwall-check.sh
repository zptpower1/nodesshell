#!/bin/bash
# cnwall-check.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
LOG="$DIR/cnwall.log"
YQ="$DIR/yq"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK] $*" | tee -a "$LOG"; }

check() {
    local port=$1 proto=$2
    local conflicts=()

    ss -tuln | grep -q ":$port .* $proto" && conflicts+=("系统服务")
    docker ps --format '{{.Ports}}' | grep -q "->$port/$proto" && conflicts+=("Docker")
    ufw status verbose 2>/dev/null | grep -q "$port/$proto" && conflicts+=("UFW")
    nft list ruleset 2>/dev/null | grep -q "dport $port.*$proto" && conflicts+=("nftables")

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log "冲突 → $port/$proto: ${conflicts[*]}"
        return 1
    else
        log "安全 ← $port/$proto"
        return 0
    fi
}

main() {
    log "端口冲突检查开始..."

    # 安全读取 services
    local services
    services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
    [[ -z "$services" ]] && { log "无服务配置，跳过检查"; return; }

    local has_conflict=0
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue

        # 读取 ports 数组
        local ports_json
        ports_json=$("$YQ" e -j ".services.\"$svc\".ports" "$CONFIG" 2>/dev/null || echo '[]')
        local port_count
        port_count=$(echo "$ports_json" | "$YQ" e 'length' -)

        for ((i=0; i<port_count; i++)); do
            local port proto
            port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
            proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
            check "$port" "$proto" || has_conflict=1
        done
    done <<< "$services"

    log "检查完成"
    [[ $has_conflict -eq 0 ]]
}

main