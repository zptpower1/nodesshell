#!/bin/bash

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 此脚本需要以 root 权限运行"
        exit 1
    fi
}

# 高延迟+大流量激进专项优化，跨境视频类应用的TCP参数(e.g., 4K streaming over CN2 GIA)
optimize_for_high_latency_video() {
    echo "Optimizing TCP for high-latency video applications..."
    sudo sysctl -w net.inet.tcp.mssdflt=1440
    sudo sysctl -w net.inet.tcp.autosndbufmax=4194304
    sudo sysctl -w net.inet.tcp.sendspace=131072
    sudo sysctl -w net.inet.tcp.autorcvbufmax=20971520
    sudo sysctl -w net.inet.tcp.recvspace=4194304
    sudo sysctl -w net.inet.tcp.delayed_ack=1
    sudo sysctl -w net.inet.tcp.win_scale_factor=8
    sudo sysctl -w net.inet.tcp.aggressive_rcvwnd_inc=2
    sudo sysctl -w kern.ipc.maxsockbuf=33554432
    echo "High-latency video TCP settings applied:"
    sysctl net.inet.tcp.sendspace
    sysctl net.inet.tcp.recvspace
    sysctl net.inet.tcp.autorcvbufmax
    sysctl net.inet.tcp.autosndbufmax
    sysctl net.inet.tcp.mssdflt
    sysctl net.inet.tcp.delayed_ack
    sysctl net.inet.tcp.win_scale_factor
    sysctl net.inet.tcp.aggressive_rcvwnd_inc
    sysctl kern.ipc.maxsockbuf
}

# 适合国内低延迟场景（浏览、游戏、国内视频）功能
optimize_for_domestic_default() {
    echo "Optimizing TCP for domestic default scenario (low latency, browsing, gaming, video)..."
    sudo sysctl -w net.inet.tcp.mssdflt=536
    sudo sysctl -w net.inet.tcp.autosndbufmax=4194304
    sudo sysctl -w net.inet.tcp.sendspace=131072
    sudo sysctl -w net.inet.tcp.autorcvbufmax=4194304
    sudo sysctl -w net.inet.tcp.recvspace=131072
    sudo sysctl -w net.inet.tcp.delayed_ack=3
    sudo sysctl -w net.inet.tcp.win_scale_factor=3
    sudo sysctl -w net.inet.tcp.aggressive_rcvwnd_inc=1
    sudo sysctl -w kern.ipc.maxsockbuf=8388608
    echo "Domestic default TCP settings applied:"
    sysctl net.inet.tcp.sendspace
    sysctl net.inet.tcp.recvspace
    sysctl net.inet.tcp.autorcvbufmax
    sysctl net.inet.tcp.autosndbufmax
    sysctl net.inet.tcp.mssdflt
    sysctl net.inet.tcp.delayed_ack
    sysctl net.inet.tcp.win_scale_factor
    sysctl net.inet.tcp.aggressive_rcvwnd_inc
    sysctl kern.ipc.maxsockbuf
}

# 常规优化高延迟兼顾网页浏览和小视频的功能（例如，通过CN2 GIA观看YouTube 1080p视频）
optimize_for_high_latency_browsing() {
    echo "Optimizing TCP for high-latency browsing and small video..."
    sudo sysctl -w net.inet.tcp.mssdflt=1440
    sudo sysctl -w net.inet.tcp.autosndbufmax=4194304
    sudo sysctl -w net.inet.tcp.sendspace=131072
    sudo sysctl -w net.inet.tcp.autorcvbufmax=20971520
    sudo sysctl -w net.inet.tcp.recvspace=1048576
    sudo sysctl -w net.inet.tcp.delayed_ack=1
    sudo sysctl -w net.inet.tcp.win_scale_factor=4
    sudo sysctl -w net.inet.tcp.aggressive_rcvwnd_inc=1
    sudo sysctl -w kern.ipc.maxsockbuf=33554432
    echo "High-latency browsing and small video TCP settings applied:"
    sysctl net.inet.tcp.sendspace
    sysctl net.inet.tcp.recvspace
    sysctl net.inet.tcp.autorcvbufmax
    sysctl net.inet.tcp.autosndbufmax
    sysctl net.inet.tcp.mssdflt
    sysctl net.inet.tcp.delayed_ack
    sysctl net.inet.tcp.win_scale_factor
    sysctl net.inet.tcp.aggressive_rcvwnd_inc
    sysctl kern.ipc.maxsockbuf
}

# 主函数调用
check_root

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -m, --mode <模式>         设置网络优化模式"
    echo ""
    echo "可用的网络优化模式:"
    echo "  1, high_latency_video   - 高延迟大流量专项激进优化 (跨境4K视频)"
    echo "  2, domestic_default     - 国内默认场景 (游戏/会议/浏览) [默认]"
    echo "  3, high_latency_browse  - 跨境高延迟常规优化 (跨境1080P视频)"
    echo ""
    echo "示例:"
    echo "  $0                      # 使用默认模式 (domestic_default)"
    echo "  $0 -m high_latency_video"
    echo "  $0 --mode 1"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -m|--mode)
            if [ -n "$2" ]; then
                app_type="$2"
                shift 2
            else
                echo "❌ 错误: -m|--mode 选项需要一个参数"
                exit 1
            fi
            ;;
        1)
            app_type="high_latency_video"
            shift
            ;;
        2)
            app_type="domestic_default"
            shift
            ;;
        3)
            app_type="high_latency_browse"
            shift
            ;;
        *)
            app_type="domestic_default"  # 默认模式
            shift
            ;;
    esac
done

# 如果没有指定模式，显示交互式菜单
if [ -z "$app_type" ]; then
    echo "请选择网络优化场景："
    echo "1. high_latency_video   - 高延迟大流量场景 (跨境4K视频)"
    echo "2. domestic_default     - 国内默认场景 (游戏/会议/浏览) [默认]"
    echo "3. high_latency_browse  - 高延迟浏览场景 (跨境1080P视频)"
    read -p "请输入选项 (1-3) [2]: " choice
    case "$choice" in
        1) app_type="high_latency_video" ;;
        3) app_type="high_latency_browse" ;;
        2|"") app_type="domestic_default" ;;  # 空输入使用默认值
        *) 
            echo "⚠️ 无效的选项，使用默认场景"
            app_type="domestic_default"
            ;;
    esac
fi

# 应用选择的优化模式
case "$app_type" in
    high_latency_video)
        optimize_for_high_latency_video
        ;;
    high_latency_browse)
        optimize_for_high_latency_browsing
        ;;
    *)
        # 默认使用国内场景优化
        optimize_for_domestic_default
        ;;
esac