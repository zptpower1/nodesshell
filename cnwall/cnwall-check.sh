#!/bin/bash
# cnwall-check.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
LOG="$DIR/cnwall.log"
YQ="$DIR/yq"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK] $*" | tee -a "$LOG"; }

# 精确检查 Docker 端口占用
docker_port_occupied() {
    local port=$1 proto=$2
    local target=":$port->$port/$proto"
    docker ps --format '{{.Names}}' | while read container; do
        if docker inspect "$container" 2>/dev/null | grep -q "\"$target\""; then
            return 0
        fi
    done
    return 1
}

check() {
    local port=$1 proto=$2
    local conflicts=()

    # 1. 系统服务
    if ss -tuln | awk '{print $5}' | grep -q ":$port$"; then
        conflicts+=("系统服务")
    fi

    # 2. Docker 容器（精确匹配）
    if docker_port_occupied "$port" "$proto"; then
        conflicts+=("Docker")
    fi

    # 3. UFW
    if ufw status verbose 2>/dev/null | grep -q " $port/$proto "; then
        conflicts+=("UFW")
    fi

    // 4. nftables
    if nft list ruleset 2>/dev/null | grep -q "dport $port.*$proto"; then
        conflicts+=("nftables")
    fi

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

    local services
    services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
    [[ -z "$services" ]] && { log "无服务配置，跳过检查"; return; }

    local has_conflict=0
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue

        local ports_json
        ports_json=$("$YQ" e -j ".services.\"$svc\".ports" "$CONFIG"

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