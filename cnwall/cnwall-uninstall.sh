#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$DIR/cnwall.log"
UPDATE_SCRIPT="$DIR/cnwall-update.sh"
APPLY_SCRIPT="$DIR/cnwall-apply.sh"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [UNINSTALL] $*" | tee -a "$LOG"; }

if command -v nft >/dev/null 2>&1; then
  nft delete table ip cnwall 2>/dev/null || true
  nft delete table inet cnwall 2>/dev/null || true
  # 删除 DOCKER-USER 专用链与跳转、过滤表中的 cnwall_* 集合（inet/ip 两种家族）
  for fam in inet ip; do
    nft delete set "$fam" filter cnwall_china 2>/dev/null || true
    nft delete set "$fam" filter cnwall_whitelist 2>/dev/null || true
    nft delete set "$fam" filter cnwall_blacklist 2>/dev/null || true
    nft delete chain "$fam" filter cnwall_docker_user 2>/dev/null || true
    if nft list chain "$fam" filter DOCKER-USER >/dev/null 2>&1; then
      handles=$(nft -a list chain "$fam" filter DOCKER-USER 2>/dev/null | awk '/jump cnwall_docker_user/{for(i=1;i<=NF;i++){if($i=="handle"){print $(i+1)}}}')
      for h in $handles; do
        nft delete rule "$fam" filter DOCKER-USER handle "$h" 2>/dev/null || true
      done
    fi
  done
  log "已清理 nft 表、过滤集合与 DOCKER-USER 跳转"
else
  log "未检测到 nft"
fi

if command -v ipset >/dev/null 2>&1; then
  ipset flush cnwall_china 2>/dev/null || true
  ipset flush cnwall_whitelist 2>/dev/null || true
  ipset flush cnwall_blacklist 2>/dev/null || true
  ipset destroy cnwall_china 2>/dev/null || true
  ipset destroy cnwall_whitelist 2>/dev/null || true
  ipset destroy cnwall_blacklist 2>/dev/null || true
  log "已移除 ipset 集合"
fi

if command -v crontab >/dev/null 2>&1; then
  current_cron=$(crontab -l 2>/dev/null || true)
  if [[ -n "$current_cron" ]]; then
    echo "$current_cron" | grep -v "$UPDATE_SCRIPT" | grep -v "$APPLY_SCRIPT" | crontab -
    log "已移除 crontab 定时任务"
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now cnwall-update.timer 2>/dev/null || true
  systemctl stop cnwall-update.service 2>/dev/null || true
  rm -f /etc/systemd/system/cnwall-update.timer 2>/dev/null || true
  rm -f /etc/systemd/system/cnwall-update.service 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  log "已移除 systemd 定时器与服务"
fi

log "卸载完成"