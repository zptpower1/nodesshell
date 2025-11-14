#!/bin/bash
# cnwall-setup.sh
# 通用中国 IP 防火墙框架 - 一键安装 + 配置 + 检查 + 应用
# 用法: sudo ./cnwall-setup.sh
# 修改 cnwall.yaml 后再次运行即可生效

set -euo pipefail

# === 自动定位当前目录 ===
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DIR/cnwall.yaml"
LOG="$DIR/cnwall.log"
UPDATE_SCRIPT="$DIR/cnwall-update.sh"
APPLY_SCRIPT="$DIR/cnwall-apply.sh"
CHECK_SCRIPT="$DIR/cnwall-check.sh"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SETUP] $*" | tee -a "$LOG"
}

# 确保模块脚本存在
for script in "$UPDATE_SCRIPT" "$APPLY_SCRIPT" "$CHECK_SCRIPT"; do
    [[ -f "$script" ]] || { log "错误: 缺失 $script"; exit 1; }
    [[ -x "$script" ]] || chmod +x "$script"
done

# === 自动安装 ipset ===
install_ipset() {
    if command -v ipset >/dev/null 2>&1; then
        log "ipset 已安装"
        return 0
    fi

    log "ipset 未安装，正在自动安装..."

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y ipset
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ipset
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ipset
    else
        log "错误: 不支持的包管理器，无法安装 ipset"
        exit 1
    fi

    systemctl enable --now ipset 2>/dev/null || true
    log "ipset 安装并启用成功"
}

install_nftables() {
    if command -v nft >/dev/null 2>&1; then
        log "nftables 已安装"
        return 0
    fi

    log "nftables 未安装，正在自动安装..."

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y nftables
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nftables
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y nftables
    else
        log "错误: 不支持的包管理器"
        exit 1
    fi

    systemctl enable --now nftables 2>/dev/null || true
    log "nftables 安装并启用成功"
}

# === 安装 yq（本地）===
install_yq() {
    if [[ ! -f "$DIR/yq" ]]; then
        log "安装 yq 到当前目录..."
        wget -qO "$DIR/yq" https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        chmod +x "$DIR/yq"
    fi
    YQ="$DIR/yq"
    export YQ
}

install_cron() {
    if command -v crontab >/dev/null 2>&1; then
        log "crontab 已可用"
        return 0
    fi
    log "未检测到 crontab，尝试安装..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y cron
        systemctl enable --now cron 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y cronie
        systemctl enable --now crond 2>/dev/null || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y cronie
        systemctl enable --now crond 2>/dev/null || true
    else
        log "无法安装 crontab（无包管理器），将使用 systemd 定时器"
        return 1
    fi
    command -v crontab >/dev/null 2>&1 && return 0 || return 1
}

setup_auto_update() {
    CRON_JOB="30 3 * * * cd '$DIR' && bash '$UPDATE_SCRIPT' && bash '$APPLY_SCRIPT' >> '$LOG' 2>&1"
    if command -v crontab >/dev/null 2>&1; then
        if ! (crontab -l 2>/dev/null | grep -F "$CRON_JOB"); then
            log "添加每日自动更新任务..."
            (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        else
            log "cron 任务已存在"
        fi
        return
    fi
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_FILE="/etc/systemd/system/cnwall-update.service"
        TIMER_FILE="/etc/systemd/system/cnwall-update.timer"
        if [[ ! -f "$SERVICE_FILE" ]]; then
            log "创建 systemd service: cnwall-update.service"
            cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=cnwall update and apply

[Service]
Type=oneshot
WorkingDirectory=$DIR
ExecStart=/bin/bash $UPDATE_SCRIPT
ExecStart=/bin/bash $APPLY_SCRIPT
EOF
        fi
        if [[ ! -f "$TIMER_FILE" ]]; then
            log "创建 systemd timer: cnwall-update.timer"
            cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Daily cnwall update

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
        fi
        systemctl daemon-reload
        systemctl enable --now cnwall-update.timer 2>/dev/null || true
        log "systemd 定时器已启用"
    else
        log "未检测到 systemctl，无法配置自动更新"
    fi
}

# === 创建默认配置文件（仅首次）===
create_default_config() {
    if [[ ! -f "$CONFIG" ]]; then
        log "创建默认 cnwall.yaml..."
        cat > "$CONFIG" <<'EOF'
# 是否启用中国 IP 限制
enable_china_restriction: true

# 白名单：优先放行（即使在国外）
whitelist:
  # - "1.1.1.1"
  # - "8.8.8.8"

# 黑名单：强制拒绝（即使在中国）
blacklist:
  # - "5.5.5.5"
  # - "10.0.0.0/8"

# 服务列表：可无限扩展
services:
  ssh:
    ports:
      - { port: 22,  protocol: tcp }
      - { port: 22,  protocol: udp }
      - { port: 9122,  protocol: tcp }
      - { port: 9122,  protocol: udp }
    allow_lan: true
EOF
    fi
}

# === 确保 ipset 主集合存在（关键修复）===
ensure_ipset_exists() {
    local name="$1" type="${2:-hash:net}"
    if ! ipset list "$name" >/dev/null 2>&1; then
        log "创建 ipset 集合: $name ($type)"
        ipset create "$name" "$type" 2>/dev/null || true
    fi
}

# === 主流程 ===
main() {
    log "=== cnwall 防火墙框架启动 ==="

    # 1. 安装依赖
    install_ipset
    install_nftables
    install_yq
    export YQ
    create_default_config
    install_cron || true

    # 2. 确保 ipset 集合存在（修复 swap 错误）
    ensure_ipset_exists "cnwall_china" hash:net
    ensure_ipset_exists "cnwall_whitelist" hash:ip
    ensure_ipset_exists "cnwall_blacklist" hash:ip

    # 3. 端口冲突检查
    log "检查端口冲突..."
    if bash "$CHECK_SCRIPT"; then
        log "端口检查通过"
    else
        log "警告: 存在端口冲突，建议检查"
    fi

    # 4. 更新中国 IP + 白/黑名单
    log "更新中国 IP + 白/黑名单..."
    bash "$UPDATE_SCRIPT"

    # 5. 应用 nftables 规则
    log "应用防火墙规则..."
    bash "$APPLY_SCRIPT"

    setup_auto_update

    log "=== 安装完成 ==="
    log "配置文件: $CONFIG"
    log "日志: tail -f '$LOG'"
    log "修改 cnwall.yaml 后再次运行即可生效"
}

[[ $EUID -eq 0 ]] || { log "请用 sudo 运行"; exit 1; }
main