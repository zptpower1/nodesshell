#!/bin/bash

# 脚本功能：安装 Sing-box 并配置 Shadowsocks2022 多用户服务
# 支持系统：Ubuntu, Debian, CentOS, Alpine, Fedora, Arch Linux
# 依赖：wget, curl, jq

# 设置默认参数
PORT=7388
METHOD="2022-blake3-aes-256-gcm"
SERVER_IP=$(curl -s https://api.ipify.org || ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
UUID=$(cat /proc/sys/kernel/random/uuid)
SUBSCRIBE_URL="https://sub.example.com"  # 可替换为你的订阅服务地址

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "此脚本需要以 root 权限运行，请使用 sudo 或切换到 root 用户"
   exit 1
fi

# 检查依赖
for cmd in wget curl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "安装依赖 $cmd..."
        apt-get update && apt-get install -y $cmd || yum install -y $cmd || apk add $cmd || pacman -S $cmd
    fi
done

# 安装 Sing-box
echo "正在安装 Sing-box..."
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/v//')
wget -O /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
tar -xzf /tmp/sing-box.tar.gz -C /tmp
mv /tmp/sing-box-${LATEST_VERSION}-linux-${ARCH}/sing-box /usr/local/bin/
rm -rf /tmp/sing-box*

# 创建 Sing-box 配置文件目录
mkdir -p /etc/sing-box
cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${PORT},
      "method": "${METHOD}",
      "users": [
        {
          "name": "user1",
          "password": "$(openssl rand -base64 16)"
        },
        {
          "name": "user2",
          "password": "$(openssl rand -base64 16)"
        },
        {
          "name": "user3",
          "password": "$(openssl rand -base64 16)"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

# 创建 systemd 服务
cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=Sing-box Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

# 启动 Sing-box 服务
systemctl daemon-reload
systemctl enable sing-box
systemctl start sing-box

# 检查服务状态
if systemctl is-active --quiet sing-box; then
    echo "Sing-box 服务已成功启动"
else
    echo "Sing-box 服务启动失败，请检查 /etc/sing-box/config.json 或日志"
    exit 1
fi

# 生成客户端配置和订阅链接
echo "生成客户端配置..."
CONFIG_DIR="/tmp/ss2022_configs"
mkdir -p $CONFIG_DIR
USERS=$(jq -r '.inbounds[0].users[] | .name + ":" + .password' /etc/sing-box/config.json)
while IFS=: read -r username password; do
    SS_URL="ss://${METHOD}:${password}@${SERVER_IP}:${PORT}#${username}"
    echo $SS_URL >> $CONFIG_DIR/subscription.txt
    echo "用户: ${username}" >> $CONFIG_DIR/client_configs.txt
    echo "Shadowsocks URL: ${SS_URL}" >> $CONFIG_DIR/client_configs.txt
    echo "-------------------" >> $CONFIG_DIR/client_configs.txt
done <<< "$USERS"

# 输出订阅链接
SUBSCRIPTION=$(base64 -w 0 $CONFIG_DIR/subscription.txt)
echo "订阅链接: ${SUBSCRIBE_URL}?sub=${SUBSCRIPTION}"
echo "客户端配置文件已保存至: $CONFIG_DIR/client_configs.txt"

# 清理临时文件
rm -rf $CONFIG_DIR/subscription.txt

echo "安装完成！请检查 $CONFIG_DIR/client_configs.txt 获取客户端配置。"