#!/bin/bash
# 用法: ./ufw-block-ssh.sh 1.2.3.4 5.6.7.8 ...
# 功能: 允许指定 IP 的 22 出口流量，禁止其他所有 22 出口流量

if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行"
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "用法: $0 ip1 ip2 ..."
  exit 1
fi

echo "[*] 删除旧的全局 22 出口封禁规则（如果存在）..."
ufw delete deny out to any port 22 proto tcp 2>/dev/null

echo "[*] 添加白名单..."
for ip in "$@"; do
  echo "  - 允许 $ip 的 22 出口"
  ufw allow out to $ip port 22 proto tcp
done

echo "[*] 添加全局 22 出口封禁..."
ufw deny out to any port 22 proto tcp

echo "[*] 完成！当前规则："
ufw status numbered