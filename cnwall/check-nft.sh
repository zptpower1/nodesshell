#!/bin/bash
# 文件名: check-nft.sh
# 用法:
#   sudo ./check-nft.sh 53     # 查询端口 53
#   sudo ./check-nft.sh        # 查看 Docker 表

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

print_header() {
    echo -e "${YELLOW}=== $1 ===${NC}"
}

# 修复：支持任意空格、端口集、注释中的端口
search_port() {
    local port="$1"
    local found=0

    print_header "查询端口 $port 规则（所有表）"

    for family in ip ip6 inet bridge arp; do
        tables=$(nft -a list tables $family 2>/dev/null | awk '{print $2}' | sort -u || true)
        for table in $tables; do
            # 提取整表内容
            rules=$(nft list table $family $table 2>/dev/null || continue)

            # 匹配：dport/sport 前后任意空格、端口集、注释
            if echo "$rules" | grep -Eq "(dport|sport)[[:space:]]+[^[:space:]]*$port[^[:space:]]|(dport|sport)[[:space:]]*\{[^}]*\b$port\b[^}]*\}|comment.*\b$port\b"; then
                echo -e "${GREEN}表 $family $table${NC} 包含端口 $port："
                echo "$rules" | \
                    grep -E --color=always "(dport|sport)[[:space:]]+[^[:space:]]*$port[^[:space:]]|(dport|sport)[[:space:]]*\{[^}]*\b$port\b[^}]*\}|comment.*\b$port\b" | \
                    nl | sed 's/^/    /'
                found=1
            fi
        done
    done

    [ $found -eq 0 ] && echo -e "${RED}未在任何表中找到端口 $port 规则${NC}"
}

show_docker_tables() {
    print_header "Docker 相关 nftables 表"
    local found=0
    for family in ip ip6 inet nat filter; do
        tables=$(nft list tables $family 2>/dev/null | awk '{print $2}' | sort -u || true)
        for table in $tables; do
            if echo "$table" | grep -qiE "docker|nat-.*docker"; then
                echo -e "${GREEN}表 $family $table${NC}："
                nft list table $family $table | sed 's/^/    /'
                found=1
                echo
            fi
        done
    done
    [ $found -eq 0 ] && echo -e "${RED}未检测到 Docker 相关表${NC}"
}

# 主逻辑
if [ $# -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    search_port "$1"
elif [ $# -eq 0 ]; then
    show_docker_tables
else
    echo "用法:"
    echo "  sudo $0 <端口>    # 查询端口"
    echo "  sudo $0           # 查看 Docker 表"
    exit 1
fi