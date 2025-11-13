#!/bin/bash
# 端口管理冲突检查
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
LOG="$DIR/cnwall.log"

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
    else
        log "安全 ← $port/$proto"
    fi
}

main() {
    log "端口冲突检查开始..."
    services=$(yq e '.services | keys | .[]' "$CONFIG")
    for svc in $services; do
        ports=$(yq e ".services.$svc.ports[]" "$CONFIG")
        for p in $ports; do
            port=$(echo "$p" | yq e '.port' -)
            proto=$(echo "$p" | yq e '.protocol' -)
            check "$port" "$proto"
        done
    done
    log "检查完成"
}

main