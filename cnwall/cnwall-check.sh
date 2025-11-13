#!/bin/bash
# cnwall-check.sh
# 完美兼容 UFW 无协议格式（如 "53 ALLOW"）和有协议格式（如 "80/tcp ALLOW"）
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
LOG="$DIR/cnwall.log"
YQ="$DIR/yq"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK] $*" | tee -a "$LOG"; }

# 1. iptables 直接检查（最可靠）
iptables_has_rule() {
    local port=$1 proto=$2
    local chain=${3:-INPUT}
    local table=${4:-filter}

    if command -v iptables-legacy >/dev/null 2>&1; then
        iptables-legacy -t "$table" -S "$chain" 2>/dev/null | grep -Eq -- "-p $proto .*--dport $port( |$)"
        return $?
    fi
    if command -v iptables-nft >/dev/null 2>&1; then
        iptables-nft -t "$table" -S "$chain" 2>/dev/null | grep -Eq -- "-p $proto .*--dport $port( |$)"
        return $?
    fi
    return 1
}

# 2. UFW 检查：兼容 "80/tcp ALLOW" 和 "53 ALLOW"
ufw_has_allow() {
    local port=$1 proto=$2
    local status
    status=$(ufw status verbose 2>/dev/null || echo "")

    # 匹配模式：
    # - 80/tcp ALLOW IN Anywhere
    # - 53     ALLOW IN Anywhere
    # - 53 (v6) ALLOW IN Anywhere (v6)
    echo "$status" | grep -Ei "(^|\s)$port(/$proto)?(\s|\().*ALLOW" >/dev/null
}

# 3. Docker iptables
docker_iptables_has_rule() {
    local port=$1 proto=$2
    iptables_has_rule "$port" "$proto" "DOCKER-USER" "filter" && return 0
    iptables_has_rule "$port" "$proto" "DOCKER" "filter" && return 0
    iptables_has_rule "$port" "$proto" "PREROUTING" "nat" && return 0
    return 1
}

check() {
    local port=$1 proto=$2
    local conflicts=()

    if iptables_has_rule "$port" "$proto"; then
        conflicts+=("iptables")
    fi

    if ufw_has_allow "$port" "$proto"; then
        conflicts+=("UFW")
    fi

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
    log "多防火墙共存检查开始（完美兼容 UFW 无协议格式）..."

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