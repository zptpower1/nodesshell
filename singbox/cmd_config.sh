#!/bin/bash

# 加载工具库
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

case "$1" in
    sync)
        config_sync
        ;;
    backup)
        config_backup
        ;;
    restore)
        config_restore "$2"
        ;;
    show)
        config_show
        ;;
    check)
        config_check
        ;;
    setup)
        config_protocol_setup
        ;;
    *)
        echo "配置管理命令用法: $0 <subcommand> [args]"
        echo "可用的子命令:"
        echo "  sync           同步配置文件"
        echo "  backup         备份配置"
        echo "  restore <file> 还原配置"
        echo "  show           查看当前配置"
        echo "  check          检查配置文件"
        echo "  setup          安装新的协议配置"
        ;;
esac