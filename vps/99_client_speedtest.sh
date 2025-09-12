#!/bin/bash

# 检查是否安装了 speedtest-cli
check_speedtest() {
    if ! command -v speedtest-cli &> /dev/null; then
        echo "❌ speedtest-cli 未安装"
        read -p "是否要安装 speedtest-cli？(y/n): " install_choice
        
        if [ "$install_choice" != "y" ]; then
            echo "已取消安装"
            exit 1
        fi

        # 检测操作系统类型
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            echo "在 macOS 上使用以下命令安装 speedtest-cli:"
            echo "brew install speedtest-cli"
            read -p "按回车键继续安装..." 
            brew tap teamookla/speedtest
            brew update
            brew install speedtest --force
        elif command -v apt &> /dev/null; then
            # Ubuntu/Debian
            echo "在 Ubuntu/Debian 上使用以下命令安装 speedtest-cli:"
            echo "sudo apt install speedtest-cli"
            read -p "按回车键继续安装..." 
            sudo apt update && sudo apt install -y speedtest-cli
        else
            # 其他系统使用 pip3
            echo "使用 pip3 安装 speedtest-cli:"
            echo "pip3 install speedtest-cli"
            read -p "按回车键继续安装..." 
            pip3 install speedtest-cli
        fi

        if [ $? -ne 0 ]; then
            echo "❌ speedtest-cli 安装失败"
            exit 1
        fi
        echo "✅ speedtest-cli 安装成功"
    fi
}

# 获取并显示可用的测速服务器
list_servers() {
    echo "正在获取测速服务器列表..."
    servers=$(speedtest-cli --list | grep -v "^Retrieving" | head -n 20)
    echo "可用的测速服务器（前20个）："
    echo "$servers"
    echo "================================"
}

# 选择测速服务器
select_server() {
    list_servers
    read -p "请输入服务器ID (直接回车使用自动选择): " server_id
    if [ -z "$server_id" ]; then
        echo "使用自动选择的最佳服务器"
        echo ""
    else
        echo "已选择服务器 ID: $server_id"
        echo "$server_id"
    fi
}

# 执行速度测试
run_speedtest() {
    echo "开始网速测试..."
    local server_id="$1"
    
    # 显示测试进度
    echo "1. 正在检测最佳测试服务器..."
    if [ -n "$server_id" ]; then
        echo "使用指定服务器 ID: $server_id"
        result=$(speedtest-cli --no-upload --server "$server_id")
    else
        echo "自动选择最佳服务器"
        result=$(speedtest-cli --no-upload)
    fi
    
    if [ $? -ne 0 ]; then
        echo "❌ 测速失败"
        exit 1
    fi
    
    # 解析并格式化显示结果
    echo "================================"
    echo "📊 测试完成！详细结果："
    echo "$result"
    
    # 提取测试结果
    ping=$(echo "$result" | grep "Ping:" | awk '{print $2}')
    download=$(echo "$result" | grep "Download:" | awk '{print $2}')
    upload=$(echo "$result" | grep "Upload:" | awk '{print $2}')
    server_info=$(echo "$result" | grep "Hosted by" | sed 's/Hosted by /服务器: /')
    
    echo "🏢 $server_info"
    echo "🔄 延迟: $ping ms"
    echo "⬇️ 下载速度: $download Mbit/s"
    echo "⬆️ 上传速度: $upload Mbit/s"
    echo "================================"
}

# 主函数
main() {
    check_speedtest
    
    # 询问是否要查看和选择服务器
    read -p "是否要查看可用的测速服务器？(y/n): " show_servers
    
    if [ "$show_servers" = "y" ]; then
        server_id=$(select_server)
        run_speedtest "$server_id"
    else
        run_speedtest
    fi
}

# 执行主函数
main