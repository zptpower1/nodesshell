#!/bin/bash
#服务管理模块

source "$(dirname "$0")/utils.sh"

# 启动服务
function start_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在启动 Shadowsocks 服务..."
  systemctl start "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已启动。" || {
    echo "❌ 启动 Shadowsocks 服务失败，请检查日志：$LOG_DIR/ss-server.log 或 journalctl -u shadowsocks.service"
    exit 1
  }
}

# 停止服务
function stop_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在停止 Shadowsocks 服务..."
  systemctl stop "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已停止。" || {
    echo "❌ 停止 Shadowsocks 服务失败，请检查日志：$LOG_DIR/ss-server.log 或 journalctl -u shadowsocks.service"
    exit 1
  }
}

# 重启服务
function restart_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在重启 Shadowsocks 服务..."
  systemctl restart "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已重启。" || {
    echo "❌ 重启 Shadowsocks 服务失败，请检查日志：$LOG_DIR/ss-server.log 或 journalctl -u shadowsocks.service"
    exit 1
  }
}

# 启用服务
function enable_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在启用 Shadowsocks 服务开机自启动..."
  systemctl enable "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已设置为开机自启动。" || {
    echo "❌ 启用自启动失败，请检查 systemctl 配置。"
    exit 1
  }
}

# 禁用服务
function disable_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在禁用 Shadowsocks 服务开机自启动..."
  systemctl disable "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已移除开机自启动。" || {
    echo "❌ 禁用自启动失败，请检查 systemctl 配置。"
    exit 1
  }
}

# 查看服务状态
function status_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📋 Shadowsocks 服务状态："
  systemctl status "$SERVICE_NAME" --no-pager || {
    echo "⚠️ 获取服务状态失败，请检查 systemctl 配置。"
    exit 1
  }
}

# 查看服务日志
function logs_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📜 查看 Shadowsocks 服务日志："
  LOG_FILE="$LOG_DIR/ss-server.log"
  if [[ -f "$LOG_FILE" ]]; then
    echo "📄 日志文件: $LOG_FILE"
    tail -n 20 "$LOG_FILE" || {
      echo "⚠️ 无法读取日志文件: $LOG_FILE"
    }
    echo "-------------------------------------------"
  else
    echo "⚠️ 日志文件 $LOG_FILE 不存在。"
  fi
  echo "📄 Systemd 日志 (journalctl)："
  journalctl -u shadowsocks.service -n 20 --no-pager || {
    echo "⚠️ 无法读取 journalctl 日志。"
  }
}