#!/bin/bash

# 加载工具库
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/user.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/service.sh"

case "$1" in
    add)
        user_add
        service_restart
        ;;
    del|delete|remove)
        user_del "$2"
        service_restart
        ;;
    list|ls)
        user_list
        ;;
    query|show)
        user_query
        ;;
    reset)
        user_reset "$2"
        service_restart
        ;;
    enable)
        user_set_actived "$2" "true"
        service_restart
        ;;
    disable)
        user_set_actived "$2" "false"
        service_restart
        ;;
    migrate)
        shift  # 移除第一个参数
        user_migrate "$@"  # 传递剩余的所有参数
        ;;
    *)
        echo "用户管理命令用法: $0 <subcommand> [args]"
        echo "可用的子命令:"
        echo "  add              添加用户"
        echo "  list             列出所有用户"
        echo "  query            查询用户配置"
        echo "  reset <username> 重置用户(密码)"
        echo "  enable <username>    启用用户"
        echo "  disable <username>   停用用户"
        echo "  del <username>   删除用户"
        echo "  migrate <field> [value] [type]  迁移用户数据"
        echo "    示例:"
        echo "      migrate actived true boolean  # 添加布尔类型字段"
        echo "      migrate email \"\" string      # 添加字符串类型字段"
        echo "      migrate score 0 number       # 添加数字类型字段"
        ;;
esac