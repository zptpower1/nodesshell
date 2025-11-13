#!/bin/bash
# cnwall-check.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
LOG="$DIR/cnwall.log"
YQ="$DIR/yq"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK] $*" | tee -a "$LOG"; }

# 检查是否外网监听（0.0.0.0 或 :::port）
is_public_listen() {
    local port=$1 proto=$2
    local proto_flag=""
    [[ "$proto" == "udp" ]] && proto_flag="-u" || proto_flag="-t"

    ss -lpn $proto_flag 2>/dev/null | grep -q "0\.0\.0\.0:$port\|:::$port"
}

# 检查 Docker 外网映射
docker_port_occupied() {
    local port=$1 proto=$2
    local target="0\.0\.0\.0:$port->.*$proto"
    docker ps --format '{{.Ports}}' 2>/dev/null | grep -Eq "$target"
}

check() {
    local port=$1 proto=$2
    local conflicts=()

    # 1. 系统服务（外网监听）
    if is_public_listen "$port" "$proto"; then
        conflicts+=("系统服务(外网)")
    fi

    # 2. Docker 容器（外网映射）
    if docker_port_occupied "$port" "$proto"; then
        conflicts+=("Docker(外网映射)")
    fi

    # 3. UFW 规则
    if command -v ufw >/dev/null 2>&1 && ufw status verbose 2>/dev/null | grep -q " $port/$proto .*ALLOW"; then
        conflicts+=("UFW(已放行)")
    fi

    # 4. nftables 已有规则
    if nft list ruleset 2>/dev/null | grep -q "dport $port.*$proto"; then
        conflicts+=("nftables(已配置)")
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
    services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || echo "")
    [[ -z "$services" ]] && { log "无服务配置，跳过检查"; return; }

    local has_conflict=0
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue

        local ports_json
        ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
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