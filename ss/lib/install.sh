#!/bin/bash
#安装管理模块

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/service.sh"

# 安装 Shadowsocks
function install_shadowsocks() {
  check_root
  echo "📦 开始全新安装 Shadowsocks..."

  if [[ -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 检测到已有配置文件：$CONFIG_PATH"
    read -p "是否覆盖已有配置并继续安装？(y/N): " CONFIRM
    case "$CONFIRM" in
      [yY]) backup_config ;;
      *) echo "❌ 已取消安装操作。"; exit 1 ;;
    esac
  fi

  echo "📌 安装 Shadowsocks 和依赖..."
  apt-get update >/dev/null 2>&1
  apt-get install -y shadowsocks-libev jq qrencode logrotate >/dev/null 2>&1

  mkdir -p /usr/local/etc/shadowsocks
  mkdir -p "$LOG_DIR"
  ensure_ss_user
  chown shadowsocks:shadowsocks "$LOG_DIR" || true
  chmod 755 "$LOG_DIR"

  SERVER_PORT=${SERVER_PORT:-8388}
  echo "📌 使用端口: $SERVER_PORT"

  LOCAL_PORT=${LOCAL_PORT:-2080}
  echo "📌 使用本地端口: $LOCAL_PORT"

  echo "可用加密方法: aes-256-gcm, chacha20-ietf-poly1305, aes-128-gcm"
  METHOD=${METHOD:-chacha20-ietf-poly1305}
  echo "📌 加密方法: $METHOD"

  PASSWORD=$(cat /proc/sys/kernel/random/uuid)
  echo "📌 密码: $PASSWORD"

  echo "请选择 IP 协议支持："
  echo "1) 仅 IPv4"
  echo "2) 仅 IPv6"
  echo "3) 同时支持 IPv4 和 IPv6 [默认]"
  read -p "请输入选项 [1-3]: " IP_VERSION
  case "$IP_VERSION" in
    1) SERVER_IP="\"0.0.0.0\""; echo "📌 仅支持 IPv4" ;;
    2) SERVER_IP="\"::\""; echo "📌 仅支持 IPv6" ;;
    *) SERVER_IP="[\"::\", \"0.0.0.0\"]"; echo "📌 同时支持 IPv4 和 IPv6" ;;
  esac

  load_env

  echo "🧩 写入配置文件..."
  cat > "$CONFIG_PATH" <<EOF
{
    "server": $SERVER_IP,
    "server_port": $SERVER_PORT,
    "local_port": $LOCAL_PORT,
    "password": "$PASSWORD",
    "timeout": 300,
    "method": "$METHOD",
    "mode": "tcp_and_udp"
}
EOF
  chown root:shadowsocks "$CONFIG_PATH" || true
  chmod 644 "$CONFIG_PATH"

  echo "📌 创建 systemd 服务..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "/usr/bin/ss-server -c $CONFIG_PATH -v > $LOG_DIR/ss-server.log 2>&1"
Restart=on-failure
User=shadowsocks
Group=shadowsocks

[Install]
WantedBy=multi-user.target
EOF

  echo "📌 配置日志轮替..."
  cat > /etc/logrotate.d/shadowsocks <<EOF
$LOG_DIR/ss-server.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 shadowsocks shadowsocks
    postrotate
        systemctl restart shadowsocks >/dev/null 2>&1 || true
    endscript
}
EOF

  echo "🛡️ 配置防火墙规则..."
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$SERVER_PORT"/tcp
    ufw allow "$SERVER_PORT"/udp
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport "$SERVER_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$SERVER_PORT" -j ACCEPT
    iptables -C INPUT -p udp --dport "$SERVER_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$SERVER_PORT" -j ACCEPT
  fi

  echo "🚀 启动 Shadowsocks 服务..."
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl start "$SERVICE_NAME"

  echo "✅ 安装完成！以下是连接信息："
  print_client_info "admin"

  # 创建软链接方便调试
  echo "📌 创建配置和日志软链接..."
  if [[ ! -d "configs" ]]; then
    ln -s "$SSBASE_PATH" ./configs && echo "✅ 配置目录软链接创建成功。" || echo "⚠️ 配置目录软链接创建失败。"
  else
    echo "⚠️ 当前目录已存在 configs 目录，跳过创建软链接。"
  fi

  if [[ ! -d "logs" ]]; then
    ln -s "$LOG_DIR" ./logs && echo "✅ 日志目录软链接创建成功。" || echo "⚠️ 日志目录软链接创建失败。"
  else
    echo "⚠️ 当前目录已存在 logs 目录，跳过创建软链接。"
  fi

  if [[ ! -f "$ENV_FILE" ]]; then
    echo "⚠️ 提示：当前目录缺少 .env 文件，建议创建并配置 NODENAME 和 NODEDOMAIN（可选）。"
    echo "示例："
    echo "NODENAME=my-ss-server"
    echo "NODEDOMAIN=example.com"
  fi
}

# 卸载 Shadowsocks
function uninstall_shadowsocks() {
  check_root
  echo "⚠️ 即将卸载 Shadowsocks，并删除其所有配置文件和程序。"
  read -p "确认要继续卸载吗？(y/N): " CONFIRM
  case "$CONFIRM" in
    [yY]) echo "✅ 继续卸载..." ;;
    *) echo "❌ 已取消卸载操作。"; exit 1 ;;
  esac

  stop_service
  disable_service
  rm -f "$SERVICE_FILE"
  rm -f /etc/logrotate.d/shadowsocks
  rm -rf /usr/local/etc/shadowsocks
  rm -rf "$LOG_DIR"
  apt-get purge -y shadowsocks-libev || true
  apt-get autoremove -y || true
  systemctl daemon-reload

  echo "✅ 卸载完成。"
}

# 升级 Shadowsocks
function upgrade_shadowsocks() {
  check_root
  echo "🔄 正在升级 Shadowsocks 核心版本（配置文件将保留）..."
  apt-get update >/dev/null 2>&1
  apt-get install -y shadowsocks-libev >/dev/null 2>&1
  echo "✅ 升级完成。"
}