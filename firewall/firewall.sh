#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR/.."
PYTHON_BIN="${PYTHON:-python3}"

show_menu() {
  echo "1) 状态"
  echo "2) 查看配置"
  echo "3) 重置配置"
  echo "4) 更新China IP"
  echo "5) 应用规则"
  echo "6) 重置规则(nft表)"
  echo "7) 设置定时任务"
  echo "8) 移除定时任务"
  echo "9) 一键: 重置→更新→应用"
  echo "10) 一键: 更新→应用"
  echo "0) 退出"
}

while true; do
  show_menu
  read -r -p "选择: " choice
  case "$choice" in
    1) "$PYTHON_BIN" -m firewall.main status ;;
    2) "$PYTHON_BIN" -m firewall.main config_show ;;
    3) "$PYTHON_BIN" -m firewall.main config_reset ;;
    4) "$PYTHON_BIN" -m firewall.main china_update ;;
    5) "$PYTHON_BIN" -m firewall.main apply ;;
    6) "$PYTHON_BIN" -m firewall.main reset ;;
    7) "$PYTHON_BIN" -m firewall.main schedule_set ;;
    8) "$PYTHON_BIN" -m firewall.main schedule_remove ;;
    9) "$PYTHON_BIN" -m firewall.main reset && "$PYTHON_BIN" -m firewall.main china_update && "$PYTHON_BIN" -m firewall.main apply ;;
    10) "$PYTHON_BIN" -m firewall.main china_update && "$PYTHON_BIN" -m firewall.main apply ;;
    0) exit 0 ;;
    *) echo "无效选择" ;;
  esac
done

