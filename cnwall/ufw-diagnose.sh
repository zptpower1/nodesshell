#!/bin/bash
echo "=== UFW 防火墙诊断 ==="
echo "[1] UFW 状态"
ufw status verbose | head -10

echo -e "\n[2] iptables INPUT 链"
iptables -L INPUT -v -n | head -10

echo -e "\n[3] Docker iptables 状态"
grep -i iptables /etc/docker/daemon.json 2>/dev/null || echo "未配置"

echo -e "\n[4] 监听端口"
ss -tuln | grep -E ":22|:80|:53|:443"

echo -e "\n建议："
echo "   sudo ufw reload"
echo "   sudo systemctl restart ufw"