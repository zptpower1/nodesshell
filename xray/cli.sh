#!/bin/bash
set -e

SERVICE_NAME="xray"
SERVICE_FILE="/etc/systemd/system/xray.service"
LOG_DIR="/var/log/xray"
LOG_FILES=("$LOG_DIR/access.log" "$LOG_DIR/error.log")

function check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本需要以 root 权限运行，请使用 sudo 或切换到 root 用户。"
    exit 1
  fi
}

function check_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Xray 服务未安装，请先运行 './xray.sh install' 安装 Xray。"
    exit 1
  fi
}

function start_service() {
  check_service
  echo "📌 正在启动 Xray 服务..."
  systemctl start "$SERVICE_NAME" && echo "✅ Xray 服务已启动。" || {
    echo "❌ 启动 Xray 服务失败，请检查日志：$LOG_DIR/error.log"
    exit 1
  }
}

function stop_service() {
  check_service
  echo "📌 正在停止 Xray 服务..."
  systemctl stop "$SERVICE_NAME" && echo "✅ Xray 服务已停止。" || {
    echo "❌ 停止 Xray 服务失败，请检查日志：$LOG_DIR/error.log"
    exit 1
  }
}

function restart_service() {
  check_service
  echo "📌 正在重启 Xray 服务..."
  systemctl restart "$SERVICE_NAME" && echo "✅ Xray 服务已重启。" || {
    echo "❌ 重启 Xray 服务失败，请检查日志：$LOG_DIR/error.log"
    exit 1
  }
}

function enable_service() {
  check_service
  echo "📌 正在启用 Xray 服务开机自启动..."
  systemctl enable "$SERVICE_NAME" && echo "✅ Xray 服务已设置为开机自启动。" || {
    echo "❌ 启用自启动失败，请检查 systemctl 配置。"
    exit 1
  }
}

function disable_service() {
  check_service
  echo "📌 正在禁用 Xray 服务开机自启动..."
  systemctl disable "$SERVICE_NAME" && echo "✅ Xray 服务已移除开机自启动。" || {
    echo "❌ 禁用自启动失败，请检查 systemctl 配置。"
    exit 1
  }
}

function status_service() {
  check_service
  echo "📋 Xray 服务状态："
  systemctl status "$SERVICE_NAME" --no-pager || {
    echo "⚠️ 获取服务状态失败，请检查 systemctl 配置。"
    exit 1
  }
}

function logs_service() {
  check_service
  echo "📜 查看 Xray 服务日志："
  for LOG_FILE in "${LOG_FILES[@]}"; do
    if [[ -f "$LOG_FILE" ]]; then
      echo "📄 日志文件: $LOG_FILE"
      tail -n 20 "$LOG_FILE" || {
        echo "⚠️ 无法读取日志文件: $LOG_FILE"
      }
      echo "-------------------------------------------"
    else
      echo "⚠️ 日志文件 $LOG_FILE 不存在。"
    fi
  done
}

function usage() {
  echo "用法: $0 {start|stop|restart|enable|disable|status|logs}"
  echo "命令说明："
  echo "  start        启动 Xray 服务"
  echo "  stop         停止 Xray 服务"
  echo "  restart      重启 Xray 服务"
  echo "  enable       启用 Xray 服务开机自启动"
  echo "  disable      禁用 Xray 服务开机自启动"
  echo "  status       查看 Xray 服务状态"
  echo "  logs         查看 Xray 日志（access.log 和 error.log）"
  exit 1
}

# 检查 root 权限
check_root

# 参数处理
case "$1" in
  start)
    start_service
    ;;
  stop)
    stop_service
    ;;
  restart)
    restart_service
    ;;
  enable)
    enable_service
    ;;
  disable)
    disable_service
    ;;
  status)
    status_service
    ;;
  logs)
    logs_service
    ;;
  *)
    usage
    ;;
esac
