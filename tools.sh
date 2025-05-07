#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 检查端口占用
check_port() {
    local port="$1"
    if [ -z "${port}" ]; then
        echo "📊 当前所有端口占用情况："
        lsof -i -P -n | grep LISTEN
    else
        echo "📊 端口 ${port} 占用情况："
        lsof -i:${port}
    fi
}

# 检查系统资源使用情况
check_system() {
    echo "💻 系统资源使用情况："
    echo
    echo "📈 CPU 使用率："
    top -l 1 | grep "CPU usage"
    echo
    echo "📊 内存使用情况："
    top -l 1 -s 0 | grep PhysMem
    echo
    echo "💾 磁盘使用情况："
    df -h
}

# 检查网络连接
check_network() {
    echo "🌐 网络连接状态："
    echo
    echo "📡 网络接口信息："
    ifconfig
    echo
    echo "🔌 网络连接统计："
    netstat -an | grep ESTABLISHED | wc -l | xargs echo "当前活动连接数："
}

# 检查服务状态
check_service() {
    echo "🔍 SS2022 服务状态："
    if pgrep -x "ssserver" > /dev/null; then
        echo "✅ 服务正在运行"
        echo
        echo "📊 进程信息："
        ps aux | grep ssserver | grep -v grep
        echo
        echo "🔌 监听端口："
        lsof -i -P -n | grep ssserver
    else
        echo "❌ 服务未运行"
    fi
}

# 显示系统信息
show_info() {
    echo "📱 系统信息："
    echo
    echo "💻 操作系统："
    uname -a
    echo
    echo "🕒 系统运行时间："
    uptime
    echo
    echo "🌡️ 负载情况："
    uptime | awk -F'load averages:' '{print $2}'
}

# 检查网络端口监听状态
check_listen() {
    local port="$1"
    echo "📡 网络端口监听状态："
    if [ -z "${port}" ]; then
        netstat -lnpt 2>/dev/null || netstat -lnp 2>/dev/null || netstat -ln
    else
        echo "查看端口 ${port} 的监听状态："
        netstat -lnpt 2>/dev/null | grep ":${port}" || \
        netstat -lnp 2>/dev/null | grep ":${port}" || \
        netstat -ln | grep ":${port}"
    fi
}

main() {
    case "$1" in
        # 工具命令
        port)
            check_port "$2"
            ;;
        system)
            check_system
            ;;
        network)
            check_network
            ;;
        service)
            check_service
            ;;
        info)
            show_info
            ;;
        listen)
            check_listen "$2"
            ;;
        
        *)
            echo "用法: $0 <command> [args]"
            echo
            echo "工具命令:"
            echo "  port [端口]   查看端口占用情况"
            echo "  listen [端口] 查看网络端口监听状态"
            echo "  system       查看系统资源使用情况"
            echo "  network      查看网络连接状态"
            echo "  service      查看服务运行状态"
            echo "  info         查看系统信息"
            ;;
    esac
}

# 调用主函数
main "$@"