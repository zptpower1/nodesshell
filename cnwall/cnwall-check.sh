#!/bin/bash
# cnwall-check.sh
# 专为多防火墙共存设计：检查 nftables 管理的端口是否被 iptables/UFW/Docker 管理
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
LOG="$DIR/cnwall.log"
YQ="$DIR/yq"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK] $*" | tee -a "$LOG"; }

# 检查 iptables / iptables-legacy 是否有规则
iptables_has_rule() {
    local port=$1 proto=$2
    local chain=${3:-INPUT}
    local table=${4:-filter}

    # 尝试 iptables-legacy
    if command -v iptables-legacy >/dev/null 2>&1; then
        if iptables-legacy -t "$table" -S "$chain" 2>/dev/null | grep -q -- "-p $proto .* dport $port "; then
            return 0
        fi
    fi

    # 尝试 nft 模式下的 iptables
    if command -v iptables-nft >/dev/null 2>&1; then
        if iptables-nft -t "$table" -S "$chain" 2>/dev/null | grep -q -- "-p $proto .* dport $port "; then
            return 0
        fi
    fi

    return 1
}

# 检查 UFW 是否放行该端口
ufw_has_allow() {
    local port=$1 proto=$2
    ufw status verbose 2>/dev/null | grep -q " $port/$proto .*ALLOW"
}

# 检查 Docker 是否通过 iptables 放行（Docker 默认用 iptables）
docker_iptables_has_rule() {
    local port=$1 proto=$2
    iptables_has_rule "$port" "$proto" "DOCKER-USER" "filter" && return 0
    iptables_has_rule "$port" "$proto" "DOCKER" "filter" && return 0
    return 1
}

check() {
    local port=$1 proto=$2
    local conflicts=()

    # 1. iptables / iptables-legacy
    if iptables_has_rule "$port" "$proto"; then
        conflicts+=("iptables")
    fi

    # 2. UFW（基于 iptables）
    if ufw_has_allow "$port" "$proto"; then
        conflicts+=("UFW")
    fi

    # 3. Docker iptables 规则
    if docker_iptables_has_rule "$port" "$proto"; then
        conflicts+=("Docker-iptables")
    fi

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log "冲突 → $port/$proto 被 ${conflicts[*]} 管理（可能与 nftables 冲突）"
        return 1
    else
        log "安全 ← $port/$proto 未被其他工具管理"
        return 0
    fi
}

main() {
    log "多防火墙共存检查开始（仅检查 iptables/UFW/Docker 是否管理）..."

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