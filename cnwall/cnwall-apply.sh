#!/bin/bash
# cnwall-apply.sh
# 修复：移除 shell 重定向，使用 nft 原生语法
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
NFT_TABLE="cnwall"
LOG="$DIR/cnwall.log"
YQ="$DIR/yq"
IPSET_CHINA="cnwall_china"
IPSET_WHITE="cnwall_whitelist"
IPSET_BLACK="cnwall_blacklist"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [APPLY] $*" | tee -a "$LOG"; }

if [[ ! -x "$YQ" ]]; then
    if command -v yq >/dev/null 2>&1; then
        YQ="$(command -v yq)"
    else
        log "错误: 未找到 yq，请先运行 setup 安装或手动提供"
        exit 1
    fi
fi

ENABLED=$("$YQ" e '.enable_china_restriction' "$CONFIG")
[[ "$ENABLED" != "true" ]] && { log "中国限制已禁用"; exit 0; }

log "应用防火墙规则..."

# 临时文件
tmp=$(mktemp)

# 1. 如果旧表存在则删除（避免 nft -f 在脚本里因不存在而报错）
if nft list table ip "$NFT_TABLE" >/dev/null 2>&1; then
    nft delete table ip "$NFT_TABLE" || true
fi

# 2. 构造 nft 脚本（纯 nft 语法）
cat > "$tmp" <<'EOF'
# 创建新表（主版本）
add table ip cnwall;

add set ip cnwall china { type ipv4_addr; flags interval; }
add set ip cnwall whitelist { type ipv4_addr; }
add set ip cnwall blacklist { type ipv4_addr; }

add chain ip cnwall host_input { type filter hook input priority 0; policy accept; }

# 基础规则（input）
add rule ip cnwall host_input iifname "lo" accept
add rule ip cnwall host_input ip saddr 127.0.0.1 accept
add rule ip cnwall host_input ip saddr @whitelist accept
add rule ip cnwall host_input ip saddr @blacklist limit rate 20/second log prefix "cnwall: drop blacklist (input) " level warning counter drop
EOF

if command -v ipset >/dev/null 2>&1; then
    china_entries=$(ipset save "$IPSET_CHINA" 2>/dev/null | awk '$1=="add"{print $3}')
    china_count=$(printf '%s\n' "$china_entries" | grep -c . || true)
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element ip cnwall china { $entry }" >> "$tmp"
    done <<< "$china_entries"

    white_entries=$(ipset save "$IPSET_WHITE" 2>/dev/null | awk '$1=="add"{print $3}')
    white_count=$(printf '%s\n' "$white_entries" | grep -c . || true)
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element ip cnwall whitelist { $entry }" >> "$tmp"
    done <<< "$white_entries"

    black_entries=$(ipset save "$IPSET_BLACK" 2>/dev/null | awk '$1=="add"{print $3}')
    black_count=$(printf '%s\n' "$black_entries" | grep -c . || true)
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element ip cnwall blacklist { $entry }" >> "$tmp"
    done <<< "$black_entries"
    log "同步 ipset: china=${china_count:-0} whitelist=${white_count:-0} blacklist=${black_count:-0}"
else
    log "未检测到 ipset，nft 集合为空"
fi

# 2. 动态添加服务规则
services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue

    allow_lan=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")

    ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
    port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
    for ((i=0; i<port_count; i++)); do
        port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
        proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
        echo "add rule ip cnwall host_input ip saddr @china $proto dport $port limit rate 20/second log prefix \"cnwall: allow CN $svc $proto $port (input) \" level info counter accept" >> "$tmp"
        if [[ "$allow_lan" == "true" ]]; then
            echo "add rule ip cnwall host_input ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10 } $proto dport $port limit rate 20/second log prefix \"cnwall: allow LAN $svc $proto $port (input) \" level info counter accept" >> "$tmp"
        fi
        echo "add rule ip cnwall host_input ip saddr 100.64.0.0/10 $proto dport $port limit rate 20/second log prefix \"cnwall: allow TS $svc $proto $port (input) \" level info counter accept" >> "$tmp"
        echo "add rule ip cnwall host_input $proto dport $port limit rate 10/second log prefix \"cnwall: drop non-match $svc $proto $port (input) \" level warning counter drop" >> "$tmp"
    done
done <<< "$services"

# 3. 结尾（默认策略为 accept，无需额外 drop）
echo "add rule ip cnwall host_input counter accept" >> "$tmp"

# 通过 DOCKER-USER 链增强与 UFW-Docker 的端口拦截兼容
DOCKER_FAMILY=""
if nft list chain inet filter DOCKER-USER >/dev/null 2>&1; then
    DOCKER_FAMILY="inet"
elif nft list chain ip filter DOCKER-USER >/dev/null 2>&1; then
    DOCKER_FAMILY="ip"
fi

if [[ -n "$DOCKER_FAMILY" ]]; then
    if nft list set "$DOCKER_FAMILY" filter china >/dev/null 2>&1; then
        echo "flush set $DOCKER_FAMILY filter china" >> "$tmp"
    else
        echo "add set $DOCKER_FAMILY filter china { type ipv4_addr; flags interval; }" >> "$tmp"
    fi
    if nft list set "$DOCKER_FAMILY" filter whitelist >/dev/null 2>&1; then
        echo "flush set $DOCKER_FAMILY filter whitelist" >> "$tmp"
    else
        echo "add set $DOCKER_FAMILY filter whitelist { type ipv4_addr; }" >> "$tmp"
    fi
    if nft list set "$DOCKER_FAMILY" filter blacklist >/dev/null 2>&1; then
        echo "flush set $DOCKER_FAMILY filter blacklist" >> "$tmp"
    else
        echo "add set $DOCKER_FAMILY filter blacklist { type ipv4_addr; }" >> "$tmp"
    fi

    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter china { $entry }" >> "$tmp"
    done <<< "$china_entries"
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter whitelist { $entry }" >> "$tmp"
    done <<< "$white_entries"
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter blacklist { $entry }" >> "$tmp"
    done <<< "$black_entries"

    CNWALL_DOCKER_CHAIN="cnwall_docker_user"
    if nft list chain "$DOCKER_FAMILY" filter "$CNWALL_DOCKER_CHAIN" >/dev/null 2>&1; then
        echo "flush chain $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN" >> "$tmp"
    else
        echo "add chain $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN { policy accept; }" >> "$tmp"
    fi
    if ! nft list chain "$DOCKER_FAMILY" filter DOCKER-USER | grep -q "jump $CNWALL_DOCKER_CHAIN"; then
        echo "insert rule $DOCKER_FAMILY filter DOCKER-USER index 0 jump $CNWALL_DOCKER_CHAIN comment \"cnwall hook\"" >> "$tmp"
    fi
    echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @whitelist comment \"cnwall\" accept" >> "$tmp"
    echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @blacklist comment \"cnwall\" drop" >> "$tmp"

    services_docker=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        allow_lan=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")
        ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
        port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
        for ((i=0; i<port_count; i++)); do
            port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
            proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
            echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @china $proto dport $port comment \"cnwall\" accept" >> "$tmp"
            if [[ "$allow_lan" == "true" ]]; then
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 127.0.0.0/8, 100.64.0.0/10 } $proto dport $port comment \"cnwall\" accept" >> "$tmp"
            fi
            echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr 100.64.0.0/10 $proto dport $port comment \"cnwall\" accept" >> "$tmp"
            echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN $proto dport $port comment \"cnwall\" drop" >> "$tmp"
        done
    done <<< "$services_docker"
fi

# 4. 执行（失败时回退到无日志/限速版本，兼容老内核）
if ! output=$(nft -f "$tmp" 2>&1); then
    echo "$output" | tee -a "$LOG" 1>/dev/null
    echo "------ 失败的 nft 脚本 ------" >> "$LOG"
    sed -n '1,200p' "$tmp" >> "$LOG"
    echo "------ 结束 ------" >> "$LOG"
    log "尝试使用兼容版本（移除 log/limit/auto-merge）..."

    # 兼容版本
    tmp2=$(mktemp)
    cat > "$tmp2" <<'EOF'
# 创建新表（兼容版）
add table ip cnwall;

add set ip cnwall china { type ipv4_addr; flags interval; }
add set ip cnwall whitelist { type ipv4_addr; }
add set ip cnwall blacklist { type ipv4_addr; }

add chain ip cnwall host_input { type filter hook input priority 0; policy accept; }

# 基础规则（input）
add rule ip cnwall host_input iifname "lo" accept
add rule ip cnwall host_input ip saddr 127.0.0.1 accept
add rule ip cnwall host_input ip saddr @whitelist accept
add rule ip cnwall host_input ip saddr @blacklist drop
EOF

    if command -v ipset >/dev/null 2>&1; then
        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element ip cnwall china { $entry }" >> "$tmp2"
        done <<< "$china_entries"
        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element ip cnwall whitelist { $entry }" >> "$tmp2"
        done <<< "$white_entries"
        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element ip cnwall blacklist { $entry }" >> "$tmp2"
        done <<< "$black_entries"
    fi

    services=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        allow_lan=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")
        ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
        port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
        for ((i=0; i<port_count; i++)); do
            port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
            proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
            echo "add rule ip cnwall host_input ip saddr @china $proto dport $port accept" >> "$tmp2"
            if [[ "$allow_lan" == "true" ]]; then
                echo "add rule ip cnwall host_input ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10 } $proto dport $port accept" >> "$tmp2"
            fi
            echo "add rule ip cnwall host_input ip saddr 100.64.0.0/10 $proto dport $port accept" >> "$tmp2"
            echo "add rule ip cnwall host_input $proto dport $port drop" >> "$tmp2"
        done
    done <<< "$services"

    DOCKER_FAMILY=""
    if nft list chain inet filter DOCKER-USER >/dev/null 2>&1; then
        DOCKER_FAMILY="inet"
    elif nft list chain ip filter DOCKER-USER >/dev/null 2>&1; then
        DOCKER_FAMILY="ip"
    fi

    if [[ -n "$DOCKER_FAMILY" ]]; then
        if nft list set "$DOCKER_FAMILY" filter china >/dev/null 2>&1; then
            echo "flush set $DOCKER_FAMILY filter china" >> "$tmp2"
        else
            echo "add set $DOCKER_FAMILY filter china { type ipv4_addr; flags interval; }" >> "$tmp2"
        fi
        if nft list set "$DOCKER_FAMILY" filter whitelist >/dev/null 2>&1; then
            echo "flush set $DOCKER_FAMILY filter whitelist" >> "$tmp2"
        else
            echo "add set $DOCKER_FAMILY filter whitelist { type ipv4_addr; }" >> "$tmp2"
        fi
        if nft list set "$DOCKER_FAMILY" filter blacklist >/dev/null 2>&1; then
            echo "flush set $DOCKER_FAMILY filter blacklist" >> "$tmp2"
        else
            echo "add set $DOCKER_FAMILY filter blacklist { type ipv4_addr; }" >> "$tmp2"
        fi

        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter china { $entry }" >> "$tmp2"
        done <<< "$china_entries"
        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter whitelist { $entry }" >> "$tmp2"
        done <<< "$white_entries"
        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter blacklist { $entry }" >> "$tmp2"
        done <<< "$black_entries"

        CNWALL_DOCKER_CHAIN="cnwall_docker_user"
        if nft list chain "$DOCKER_FAMILY" filter "$CNWALL_DOCKER_CHAIN" >/dev/null 2>&1; then
            echo "flush chain $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN" >> "$tmp2"
        else
            echo "add chain $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN { policy accept; }" >> "$tmp2"
        fi
        if ! nft list chain "$DOCKER_FAMILY" filter DOCKER-USER | grep -q "jump $CNWALL_DOCKER_CHAIN"; then
            echo "insert rule $DOCKER_FAMILY filter DOCKER-USER index 0 jump $CNWALL_DOCKER_CHAIN comment \"cnwall hook\"" >> "$tmp2"
        fi
        echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @whitelist comment \"cnwall\" accept" >> "$tmp2"
        echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @blacklist comment \"cnwall\" drop" >> "$tmp2"

        services_docker=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            allow_lan=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")
            ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
            port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
            for ((i=0; i<port_count; i++)); do
                port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
                proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
                echo "add rule $DOCKER_FAMILY filter DOCKER-USER ip saddr @china $proto dport $port comment \"cnwall\" accept" >> "$tmp2"
                if [[ "$allow_lan" == "true" ]]; then
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 127.0.0.0/8, 100.64.0.0/10 } $proto dport $port comment \"cnwall\" accept" >> "$tmp2"
                fi
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr 100.64.0.0/10 $proto dport $port comment \"cnwall\" accept" >> "$tmp2"
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN $proto dport $port comment \"cnwall\" drop" >> "$tmp2"
            done
        done <<< "$services_docker"
    fi

    echo "add rule ip cnwall host_input counter accept" >> "$tmp2"

    if ! output2=$(nft -f "$tmp2" 2>&1); then
        echo "$output2" | tee -a "$LOG" 1>/dev/null
        echo "------ 兼容版失败脚本 ------" >> "$LOG"
        sed -n '1,200p' "$tmp2" >> "$LOG"
        echo "------ 结束 ------" >> "$LOG"
        log "nft 应用失败"
        rm -f "$tmp" "$tmp2"
        exit 1
    fi
    rm -f "$tmp2"
fi

rm "$tmp"
china_nft_count=$(nft list set ip cnwall china 2>/dev/null | sed -n '/elements/,$p' | sed '1d' | tr -d ' \n' | sed 's/,$//' | tr ',' '\n' | wc -l | tr -d ' ')
white_nft_count=$(nft list set ip cnwall whitelist 2>/dev/null | sed -n '/elements/,$p' | sed '1d' | tr -d ' \n' | sed 's/,$//' | tr ',' '\n' | wc -l | tr -d ' ')
black_nft_count=$(nft list set ip cnwall blacklist 2>/dev/null | sed -n '/elements/,$p' | sed '1d' | tr -d ' \n' | sed 's/,$//' | tr ',' '\n' | wc -l | tr -d ' ')
log "nft 集合: china=${china_nft_count:-0} whitelist=${white_nft_count:-0} blacklist=${black_nft_count:-0}"
log "规则应用成功"