#!/bin/bash
# 文件名: check-nft.sh
# 用法:
#   1. 查询具体端口:   sudo ./check-nft.sh 5244
#   2. 查看 Docker 相关表: sudo ./check-nft.sh

set -euo pipefail

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m' # No Color

# 函数：打印标题
print_header() {
    echo -e "${YELLOW}=== $1 ===${NC}"
}

# 函数：搜索端口规则（dport/sport）
search_port() {
    local port="$1"
    local found=0

    print_header "查询端口 $port 规则（所有表）"

    for family in ip ip6 inet bridge arp; do
        tables=$(nft -a list tables $family 2>/dev/null | awk '{print $2}' | sort -u || true)
        for table in $tables; do
            if nft list table $family $table 2>/dev/null | \
               grep -E "(dport|sport)[[:space:]]*$port|dport[[:space:]]*{[^}]*$port|sport[[:space:]]*{[^}]*$port" | \
               grep -v "Warning:.*iptables-nft" > /dev/null; then

                echo -e "${GREEN}表 $family $table${NC} 包含端口 $port："
                nft list table $family $table | \
                    grep -E "(dport|sport)[[:space:]]*$port|dport[[:space:]]*{[^}]*$port|sport[[:space:]]*{[^}]*$port" | \
                    nl | sed 's/^/    /'
                found=1
            fi
        done
    done

    [ $found -eq 0 ] && echo -e "${RED}未在任何表中找到端口 $port 规则${NC}"
}

# 函数：显示 Docker 相关表
show_docker_tables() {
    print_header "Docker 相关 nftables 表（含链和规则）"

    local docker_tables=("DOCKER" "DOCKER-USER" "DOCKER-ISOLATION" "docker")
    local found=0

    for family in ip ip6 inet nat filter; do
        tables=$(nft list tables $family 2>/dev/null | awk '{print $2}' | sort -u || true)
        for table in $tables; do
            if [[ " ${docker_tables[@]} " =~ " $table " ]] || \
               echo "$table" | grep -qiE "docker|nat-.*docker"; then
                echo -e "${GREEN}表 $family $table${NC}："
                nft list table $family $table | sed 's/^/    /'
                found=1
                echo
            fi
        done
    done

    [ $found -eq 0 ] && echo -e "${RED}未检测到任何 Docker 相关表（说明已成功关闭 --iptables=false）${NC}"
}

# 主逻辑
if [ $# -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    search_port "$1"
elif [ $# -eq 0 ]; then
    show_docker_tables
else
    echo "用法:"
    echo "  sudo $0 <端口号>    # 查询指定端口在所有表中的规则"
    echo "  sudo $0             # 显示 Docker 相关 nftables 表"
    exit 1
fi