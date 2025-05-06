#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 加载所有模块
source "$SCRIPT_DIR/lib/utils.sh"

# 检查环境文件
load_env

# 加载其他模块
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/service.sh"
source "$SCRIPT_DIR/lib/user.sh"
source "$SCRIPT_DIR/lib/install.sh"

# 参数分发入口
case "$1" in
  install)
    install_shadowsocks
    ;;
  upgrade)
    upgrade_shadowsocks
    ;;
  uninstall)
    uninstall_shadowsocks
    ;;
  adduser)
    add_user
    ;;
  deluser)
    delete_user
    ;;
  query)
    list_users
    ;;
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
    echo "❌ 参数错误！可用命令：install / upgrade / uninstall / adduser / deluser / listusers / start / stop / restart / enable / disable / status / logs"
    echo "使用示例："
    echo "  ./ss.sh install     # 安装并覆盖配置"
    echo "  ./ss.sh upgrade     # 升级核心，保留配置"
    echo "  ./ss.sh uninstall   # 卸载"
    echo "  ./ss.sh adduser     # 设置新用户密码"
    echo "  ./ss.sh deluser     # 删除用户密码"
    echo "  ./ss.sh listusers   # 列出当前用户"
    echo "  ./ss.sh start       # 启动服务"
    echo "  ./ss.sh stop        # 停止服务"
    echo "  ./ss.sh restart     # 重启服务"
    echo "  ./ss.sh enable      # 启用开机自启动"
    echo "  ./ss.sh disable     # 禁用开机自启动"
    echo "  ./ss.sh status      # 查看服务状态"
    echo "  ./ss.sh logs        # 查看服务日志"
    exit 1
    ;;
esac