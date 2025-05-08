#!/bin/bash

# 加载工具库
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/service.sh"

case "$1" in
    start)
        service_start
        ;;
    restart)
        service_restart
        ;;
    stop)
        service_stop
        ;;
    disable)
        service_disable
        ;;
    enable)
        service_enable
        ;;
    install)
        service_install
        ;;
    remove)
        service_remove
        ;;
    status)
        service_status
        ;;
    check)
        service_check
        ;;
    *)
        echo "服务管理命令用法: $0 <subcommand>"
        echo "可用的子命令:"
        echo "  install   安装系统服务"
        echo "  remove    卸载系统服务"
        echo "  start     启动服务"
        echo "  restart   重启服务"
        echo "  stop      停止服务"
        echo "  disable   禁用服务"
        echo "  enable    启用服务"
        echo "  status    查看服务状态"
        echo "  check     检查服务运行状态"
        ;;
esac