#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 检查是否提供了URL参数
check_url() {
    if [ -z "$1" ]; then
        return 1
    fi
    return 0
}

# 添加 extract_domain 函数实现
extract_domain() {
    local url="$1"
    # 移除协议部分 (http:// 或 https://)
    domain=$(echo "$url" | sed -E 's#^(https?://)?##')
    # 移除路径部分 (第一个斜杠后的所有内容)
    domain=$(echo "$domain" | cut -d'/' -f1)
    # 移除端口号部分 (如果存在)
    domain=$(echo "$domain" | cut -d':' -f1)
    echo "$domain"
}

# 递归获取环境变量
get_env_var() {
    local var_name="$1"
    local current_dir="$2"
    local value=""
    local env_file="$current_dir/.env"
    
    # 如果到达根目录，则停止递归
    if [ "$current_dir" = "/" ]; then
        printf "%s" "$value"
        return 0
    fi
    
    # 递归获取上级目录的值
    parent_value=$(get_env_var "$var_name" "$(dirname "$current_dir")")
    
    # 检查当前目录的 .env 文件
    if [ -f "$env_file" ]; then
        local current_value=$(grep "^${var_name}=" "$env_file" | cut -d'=' -f2)
        if [ -n "$current_value" ]; then
            value="$current_value"  # 当前目录的值覆盖父目录的值
        elif [ -n "$parent_value" ]; then
            value="$parent_value"   # 如果当前目录没有值，使用父目录的值
        fi
    elif [ -n "$parent_value" ]; then
        value="$parent_value"       # 如果当前目录没有 .env 文件，使用父目录的值
    fi
    
    printf "%s" "$value"
}

# 初始化获取环境变量
init_env_var() {
    local var_name="$1"
    local value=$(get_env_var "$var_name" "$SCRIPT_DIR")
    if [ -n "$value" ]; then
        echo >&2 "✅ 成功获取 $var_name"
    else
        echo >&2 "⚠️ 未找到 $var_name"
    fi
    printf "%s" "$value"
}

# 获取IP信息
get_ip_info() {
    local domain="$1"
    echo "🔍 正在查询域名: $domain"
    echo "================================"
    
    # 尝试获取 ipinfo.io token
    ipinfo_token=$(init_env_var "IPINFO_IO_TOKEN")
    
    # 获取A记录
    echo "📝 DNS A记录:"
    # 使用更兼容的方式存储IP数组
    IFS=$'\n' read -d '' -r -a ips < <(dig +short "$domain" A)
    
    if [ ${#ips[@]} -gt 1 ]; then
        echo "📢 检测到多个IP地址，可能使用了CDN服务"
    fi
    
    # 使用关联数组的替代方案
    shown_as_info=""
    
    for ip in "${ips[@]}"; do
        if [ -n "$ip" ]; then
            echo "IP: $ip"
            
            if [ -n "$ipinfo_token" ]; then
                # 使用 ipinfo.io
                echo "🔄 正在使用 ipinfo.io API 查询..."
                api_url="https://api.ipinfo.io/lite/${ip}?token=${ipinfo_token}"
                
                api_response=$(curl -s "$api_url")
                
                if [ -n "$api_response" ] && echo "$api_response" | jq -e . >/dev/null 2>&1; then
                    as_name=$(echo "$api_response" | jq -r '.as_name // empty')
                    
                    # 检查是否已经显示过该AS的详细信息
                    if [ -n "$as_name" ] && [[ "$shown_as_info" != *"$as_name"* ]]; then
                        shown_as_info="$shown_as_info $as_name"
                        echo "✅ API 返回数据:"
                        echo "$api_response" | jq '.'
                        echo "📊 解析后的信息:"
                        country=$(echo "$api_response" | jq -r '.country // empty')
                        country_code=$(echo "$api_response" | jq -r '.country_code // empty')
                        continent=$(echo "$api_response" | jq -r '.continent // empty')
                        as_domain=$(echo "$api_response" | jq -r '.as_domain // empty')
                        echo "国家: $country ($country_code)"
                        [ -n "$continent" ] && echo "大洲: $continent"
                        echo "网络服务商: $as_name"
                        [ -n "$as_domain" ] && echo "服务商域名: $as_domain"
                    else
                        # 只显示简要信息
                        echo "📍 简要信息: $as_name"
                    fi
                else
                    echo "❌ API 调用失败"
                    echo "错误信息: $api_response"
                fi
            else
                # 使用 ipapi.co 作为备选
                echo "🔄 正在使用 ipapi.co API 查询..."
                location=$(curl -s "https://ipapi.co/$ip/json/")
                if [ -n "$location" ]; then
                    echo "✅ API 返回数据:"
                    echo "$location" | jq '.' 2>/dev/null || echo "$location"
                    echo "📊 解析后的信息:"
                    country=$(echo "$location" | grep -o '"country_name": "[^"]*' | cut -d'"' -f4)
                    region=$(echo "$location" | grep -o '"region": "[^"]*' | cut -d'"' -f4)
                    city=$(echo "$location" | grep -o '"city": "[^"]*' | cut -d'"' -f4)
                    org=$(echo "$location" | grep -o '"org": "[^"]*' | cut -d'"' -f4)
                    echo "国家: $country"
                    echo "地区: $region"
                    echo "城市: $city"
                    echo "组织: $org"
                else
                    echo "❌ API 调用失败或返回空数据"
                fi
            fi
            echo "---"
        fi
    done
    
    # 获取AAAA记录（IPv6）
    echo "📝 DNS AAAA记录 (IPv6):"
    # 使用更兼容的方式存储IPv6数组
    IFS=$'\n' read -d '' -r -a ipv6s < <(dig +short "$domain" AAAA)
    
    if [ ${#ipv6s[@]} -gt 0 ]; then
        echo "发现 ${#ipv6s[@]} 个IPv6地址"
        for ipv6 in "${ipv6s[@]}"; do
            if [ -n "$ipv6" ]; then
                echo "IPv6: $ipv6"
            fi
        done
    else
        echo "未发现IPv6地址"
    fi
    
    echo "================================"
}

# 交互式查询函数
interactive_query() {
    while true; do
        echo ""
        read -p "请输入要查询的域名 (输入 'q' 退出): " input_domain
        
        if [ "$input_domain" = "q" ]; then
            echo "👋 感谢使用，再见！"
            exit 0
        fi
        
        if [ -n "$input_domain" ]; then
            domain=$(extract_domain "$input_domain")
            get_ip_info "$domain"
        else
            echo "❌ 请输入有效的域名"
        fi
    done
}

# 主函数
main() {
    if check_url "$1"; then
        # 如果提供了命令行参数，先处理它
        domain=$(extract_domain "$1")
        get_ip_info "$domain"
        # 然后进入交互式模式
        interactive_query
    else
        # 直接进入交互式模式
        interactive_query
    fi
}

# 执行主函数
main "$1"