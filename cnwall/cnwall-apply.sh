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

add chain ip cnwall host_input { type filter hook input priority 0; }

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
    if ! nft list table "$DOCKER_FAMILY" filter >/dev/null 2>&1; then
        echo "add table $DOCKER_FAMILY filter;" >> "$tmp"
    fi
    if nft list set "$DOCKER_FAMILY" filter cnwall_china >/dev/null 2>&1; then
        echo "flush set $DOCKER_FAMILY filter cnwall_china" >> "$tmp"
    else
        echo "add set $DOCKER_FAMILY filter cnwall_china { type ipv4_addr; flags interval; }" >> "$tmp"
    fi
    if nft list set "$DOCKER_FAMILY" filter cnwall_whitelist >/dev/null 2>&1; then
        echo "flush set $DOCKER_FAMILY filter cnwall_whitelist" >> "$tmp"
    else
        echo "add set $DOCKER_FAMILY filter cnwall_whitelist { type ipv4_addr; }" >> "$tmp"
    fi
    if nft list set "$DOCKER_FAMILY" filter cnwall_blacklist >/dev/null 2>&1; then
        echo "flush set $DOCKER_FAMILY filter cnwall_blacklist" >> "$tmp"
    else
        echo "add set $DOCKER_FAMILY filter cnwall_blacklist { type ipv4_addr; }" >> "$tmp"
    fi

    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter cnwall_china { $entry }" >> "$tmp"
    done <<< "$china_entries"
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter cnwall_whitelist { $entry }" >> "$tmp"
    done <<< "$white_entries"
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter cnwall_blacklist { $entry }" >> "$tmp"
    done <<< "$black_entries"

    CNWALL_DOCKER_CHAIN="cnwall_docker_user"
    if nft list chain "$DOCKER_FAMILY" filter "$CNWALL_DOCKER_CHAIN" >/dev/null 2>&1; then
        echo "flush chain $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN" >> "$tmp"
    else
        echo "add chain $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN" >> "$tmp"
    fi
    # 跳转挂载改为应用后执行，避免批处理内因版本差异失败
    echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @cnwall_whitelist accept comment \"cnwall\"" >> "$tmp"
    echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @cnwall_blacklist drop comment \"cnwall\"" >> "$tmp"

    services_docker=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        allow_lan=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")
        ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
        port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
        for ((i=0; i<port_count; i++)); do
            port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
            proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
            echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @cnwall_china $proto dport $port accept comment \"cnwall\"" >> "$tmp"
            if [[ "$allow_lan" == "true" ]]; then
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 127.0.0.0/8, 100.64.0.0/10 } $proto dport $port accept comment \"cnwall\"" >> "$tmp"
            fi
            echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr 100.64.0.0/10 $proto dport $port accept comment \"cnwall\"" >> "$tmp"
            echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN $proto dport $port drop comment \"cnwall\"" >> "$tmp"
        done
    done <<< "$services_docker"
fi

# 4. 执行（失败时回退到无日志/限速版本，兼容老内核）
if ! output=$(nft -f "$tmp" 2>&1); then
    echo "$output" | tee -a "$LOG" 1>/dev/null
    err_line=$(echo "$output" | sed -n 's/.*line \([0-9][0-9]*\).*/\1/p' | head -1)
    if [[ -n "$err_line" ]]; then
        start=$((err_line>10 ? err_line-10 : 1))
        end=$((err_line+10))
        echo "------ 失败位置上下文 (第${err_line}行) ------" >> "$LOG"
        sed -n "${start},${end}p" "$tmp" | nl -ba >> "$LOG"
    fi
    echo "------ 失败的 nft 脚本 (前100行) ------" >> "$LOG"
    sed -n '1,100p' "$tmp" >> "$LOG"
    echo "------ 失败的 nft 脚本 (后100行) ------" >> "$LOG"
    tail -n 100 "$tmp" >> "$LOG"
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

add chain ip cnwall host_input { type filter hook input priority 0; }

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
        if ! nft list table "$DOCKER_FAMILY" filter >/dev/null 2>&1; then
            echo "add table $DOCKER_FAMILY filter;" >> "$tmp2"
        fi
        if nft list set "$DOCKER_FAMILY" filter cnwall_china >/dev/null 2>&1; then
            echo "flush set $DOCKER_FAMILY filter cnwall_china" >> "$tmp2"
        else
            echo "add set $DOCKER_FAMILY filter cnwall_china { type ipv4_addr; flags interval; }" >> "$tmp2"
        fi
        if nft list set "$DOCKER_FAMILY" filter cnwall_whitelist >/dev/null 2>&1; then
            echo "flush set $DOCKER_FAMILY filter cnwall_whitelist" >> "$tmp2"
        else
            echo "add set $DOCKER_FAMILY filter cnwall_whitelist { type ipv4_addr; }" >> "$tmp2"
        fi
        if nft list set "$DOCKER_FAMILY" filter cnwall_blacklist >/dev/null 2>&1; then
            echo "flush set $DOCKER_FAMILY filter cnwall_blacklist" >> "$tmp2"
        else
            echo "add set $DOCKER_FAMILY filter cnwall_blacklist { type ipv4_addr; }" >> "$tmp2"
        fi

        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter cnwall_china { $entry }" >> "$tmp2"
        done <<< "$china_entries"
        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter cnwall_whitelist { $entry }" >> "$tmp2"
        done <<< "$white_entries"
        while IFS= read -r entry; do
            [[ -n "$entry" ]] && echo "add element $DOCKER_FAMILY filter cnwall_blacklist { $entry }" >> "$tmp2"
        done <<< "$black_entries"

        CNWALL_DOCKER_CHAIN="cnwall_docker_user"
        if nft list chain "$DOCKER_FAMILY" filter "$CNWALL_DOCKER_CHAIN" >/dev/null 2>&1; then
            echo "flush chain $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN" >> "$tmp2"
        else
            echo "add chain $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN" >> "$tmp2"
        fi
        # 跳转挂载改为应用后执行，避免批处理内因版本差异失败
        echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @cnwall_whitelist accept comment \"cnwall\"" >> "$tmp2"
        echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @cnwall_blacklist drop comment \"cnwall\"" >> "$tmp2"

        services_docker=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            allow_lan=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")
            ports_json=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
            port_count=$(echo "$ports_json" | "$YQ" e 'length' -)
            for ((i=0; i<port_count; i++)); do
                port=$(echo "$ports_json" | "$YQ" e ".[$i].port" -)
                proto=$(echo "$ports_json" | "$YQ" e ".[$i].protocol" -)
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr @cnwall_china $proto dport $port accept comment \"cnwall\"" >> "$tmp2"
                if [[ "$allow_lan" == "true" ]]; then
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 127.0.0.0/8, 100.64.0.0/10 } $proto dport $port accept comment \"cnwall\"" >> "$tmp2"
                fi
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN ip saddr 100.64.0.0/10 $proto dport $port accept comment \"cnwall\"" >> "$tmp2"
                echo "add rule $DOCKER_FAMILY filter $CNWALL_DOCKER_CHAIN $proto dport $port drop comment \"cnwall\"" >> "$tmp2"
            done
        done <<< "$services_docker"
    fi

    echo "add rule ip cnwall host_input counter accept" >> "$tmp2"

    if ! output2=$(nft -f "$tmp2" 2>&1); then
        echo "$output2" | tee -a "$LOG" 1>/dev/null
        echo "------ 兼容版失败脚本 (前100行) ------" >> "$LOG"
        sed -n '1,100p' "$tmp2" >> "$LOG"
        echo "------ 兼容版失败脚本 (后100行) ------" >> "$LOG"
        tail -n 100 "$tmp2" >> "$LOG"
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

# 在应用完成后，挂载 DOCKER-USER 跳转（失败仅记录日志，不影响主流程）
DOCKER_FAMILY_POST=""
if nft list chain inet filter DOCKER-USER >/dev/null 2>&1; then
    DOCKER_FAMILY_POST="inet"
elif nft list chain ip filter DOCKER-USER >/dev/null 2>&1; then
    DOCKER_FAMILY_POST="ip"
fi

if [[ -n "$DOCKER_FAMILY_POST" ]]; then
    CNWALL_DOCKER_CHAIN_POST="cnwall_docker_user"
    if nft list chain "$DOCKER_FAMILY_POST" filter "$CNWALL_DOCKER_CHAIN_POST" >/dev/null 2>&1; then
        :
    else
        if ! nft add chain "$DOCKER_FAMILY_POST" filter "$CNWALL_DOCKER_CHAIN_POST" 2>/dev/null; then
            log "无法创建 $DOCKER_FAMILY_POST filter $CNWALL_DOCKER_CHAIN_POST"
        fi
    fi
    if nft list chain "$DOCKER_FAMILY_POST" filter DOCKER-USER | grep -q "jump $CNWALL_DOCKER_CHAIN_POST"; then
        log "DOCKER-USER 已挂载 cnwall 钩子"
    else
        old_handles=$(nft -a list chain "$DOCKER_FAMILY_POST" filter DOCKER-USER 2>/dev/null | awk '/cnwall hook|jump cnwall_docker_user/{for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1)}}}')
        for h in $old_handles; do
            nft delete rule "$DOCKER_FAMILY_POST" filter DOCKER-USER handle "$h" 2>/dev/null || true
        done
        if output_force_pos0=$(nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER position 0 jump "$CNWALL_DOCKER_CHAIN_POST" comment "cnwall hook" 2>&1); then
            log "已成功强制插入 DOCKER-USER 最前面 → $CNWALL_DOCKER_CHAIN_POST"
        elif output_ins_idx=$(nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER index 0 jump "$CNWALL_DOCKER_CHAIN_POST" comment "cnwall hook" 2>&1); then
            log "已插入 DOCKER-USER 跳转(index 0)"
        elif output_ins_pos=$(nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER position 0 jump "$CNWALL_DOCKER_CHAIN_POST" comment "cnwall hook" 2>&1); then
            log "已插入 DOCKER-USER 跳转(position 0)"
        elif output_add=$(nft add rule "$DOCKER_FAMILY_POST" filter DOCKER-USER jump "$CNWALL_DOCKER_CHAIN_POST" comment "cnwall hook" 2>&1); then
            log "已追加 DOCKER-USER 跳转(末尾)"
        else
            log "插入 DOCKER-USER 跳转失败"
            echo "$output_force_pos0" >> "$LOG" 2>/dev/null || true
            echo "$output_ins_idx" >> "$LOG" 2>/dev/null || true
            echo "$output_ins_pos" >> "$LOG" 2>/dev/null || true
            echo "$output_add" >> "$LOG" 2>/dev/null || true

            # 回退：直接在 DOCKER-USER 内联应用规则（nft-only）
            # 1) 确保 DOCKER-USER 家族下的集合存在并填充
            if ! nft list table "$DOCKER_FAMILY_POST" filter >/dev/null 2>&1; then
                nft add table "$DOCKER_FAMILY_POST" filter 2>/dev/null || true
            fi
            if nft list set "$DOCKER_FAMILY_POST" filter cnwall_china >/dev/null 2>&1; then
                :
            else
                nft add set "$DOCKER_FAMILY_POST" filter cnwall_china \{ type ipv4_addr\; flags interval\; \} 2>/dev/null || true
                while IFS= read -r entry; do
                    [[ -n "$entry" ]] && nft add element "$DOCKER_FAMILY_POST" filter cnwall_china { "$entry" } 2>/dev/null || true
                done <<< "$china_entries"
            fi
            if nft list set "$DOCKER_FAMILY_POST" filter cnwall_whitelist >/dev/null 2>&1; then
                :
            else
                nft add set "$DOCKER_FAMILY_POST" filter cnwall_whitelist \{ type ipv4_addr\; \} 2>/dev/null || true
                while IFS= read -r entry; do
                    [[ -n "$entry" ]] && nft add element "$DOCKER_FAMILY_POST" filter cnwall_whitelist { "$entry" } 2>/dev/null || true
                done <<< "$white_entries"
            fi
            if nft list set "$DOCKER_FAMILY_POST" filter cnwall_blacklist >/dev/null 2>&1; then
                :
            else
                nft add set "$DOCKER_FAMILY_POST" filter cnwall_blacklist \{ type ipv4_addr\; \} 2>/dev/null || true
                while IFS= read -r entry; do
                    [[ -n "$entry" ]] && nft add element "$DOCKER_FAMILY_POST" filter cnwall_blacklist { "$entry" } 2>/dev/null || true
                done <<< "$black_entries"
            fi

            # 2) 内联基础规则（优先级：白名单放行 > 黑名单丢弃）
            if ! nft list chain "$DOCKER_FAMILY_POST" filter DOCKER-USER | grep -q 'ip saddr @cnwall_whitelist .*accept comment "cnwall"'; then
                nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER position 0 ip saddr @cnwall_whitelist accept comment "cnwall" 2>/dev/null || true
            fi
            if ! nft list chain "$DOCKER_FAMILY_POST" filter DOCKER-USER | grep -q 'ip saddr @cnwall_blacklist .*drop comment "cnwall"'; then
                nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER position 0 ip saddr @cnwall_blacklist drop comment "cnwall" 2>/dev/null || true
            fi

            # 3) 按服务内联端口规则（中国/LAN/TS 放行，默认丢弃）
            services_inline=$("$YQ" e '.services | keys | .[]' "$CONFIG" 2>/dev/null || true)
            while IFS= read -r svc; do
                [[ -z "$svc" ]] && continue
                allow_lan_inline=$("$YQ" e ".services.\"$svc\".allow_lan" "$CONFIG")
                ports_json_inline=$("$YQ" e -o=json ".services.\"$svc\".ports // []" "$CONFIG")
                port_count_inline=$(echo "$ports_json_inline" | "$YQ" e 'length' -)
                for ((ii=0; ii<port_count_inline; ii++)); do
                    port_inline=$(echo "$ports_json_inline" | "$YQ" e ".[$ii].port" -)
                    proto_inline=$(echo "$ports_json_inline" | "$YQ" e ".[$ii].protocol" -)
                    # 中国 IP 放行
                    nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER position 0 ip saddr @cnwall_china "$proto_inline" dport "$port_inline" accept comment "cnwall" 2>/dev/null || true
                    # LAN 放行
                    if [[ "$allow_lan_inline" == "true" ]]; then
                        for lan_inline in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 127.0.0.0/8 100.64.0.0/10; do
                            nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER position 0 ip saddr "$lan_inline" "$proto_inline" dport "$port_inline" accept comment "cnwall" 2>/dev/null || true
                        done
                    fi
                    # TS 放行
                    nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER position 0 ip saddr 100.64.0.0/10 "$proto_inline" dport "$port_inline" accept comment "cnwall" 2>/dev/null || true
                    # 默认丢弃（置顶插入，保障优先匹配）
                    nft insert rule "$DOCKER_FAMILY_POST" filter DOCKER-USER position 0 "$proto_inline" dport "$port_inline" drop comment "cnwall" 2>/dev/null || true
                done
            done <<< "$services_inline"

            log "已在 DOCKER-USER 直接内联应用 cnwall 规则"
        fi
    fi
fi
