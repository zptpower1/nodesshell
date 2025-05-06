#!/bin/bash
set -e

CONFIG_PATH="/usr/local/etc/shadowsocks/config.json"
BACKUP_DIR="/usr/local/etc/shadowsocks/backup"
LOG_DIR="/var/log/shadowsocks"
SS_BIN="/usr/bin/ss-server"
SERVICE_NAME="shadowsocks"
SERVICE_FILE="/etc/systemd/system/shadowsocks.service"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ENV_FILE="$SCRIPT_DIR/.env"

function check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本需要以 root 权限运行，请使用 sudo 或切换到 root 用户。"
    exit 1
  fi
}

function ensure_ss_user() {
  if ! getent group shadowsocks >/dev/null; then
    echo "📌 创建 shadowsocks 组..."
    groupadd -r shadowsocks || {
      echo "⚠️ 无法创建 shadowsocks 组，使用 nobody 组作为回退。"
      return 1
    }
  fi
  if ! id shadowsocks >/dev/null 2>&1; then
    echo "📌 创建 shadowsocks 用户..."
    useradd -r -g shadowsocks -s /sbin/nologin -M shadowsocks || {
      echo "⚠️ 无法创建 shadowsocks 用户，使用 nobody 用户作为回退。"
      return 1
    }
  fi
  echo "✅ shadowsocks 用户和组已准备就绪。"
}

function load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    if [[ -n "$NODENAME" ]]; then
      echo "📌 从 .env 文件读取节点名称: $NODENAME"
    fi
    if [[ -n "$NODEDOMAIN" ]]; then
      echo "📌 从 .env 文件读取节点域名: $NODEDOMAIN"
    fi
  fi
  if [[ -z "$NODENAME" ]]; then
    echo "⚠️ 未找到 NODENAME 设置。"
    while true; do
      read -p "请输入节点名称（不能为空）: " NODENAME
      if [[ -n "$NODENAME" ]]; then
        echo "📌 设置节点名称: $NODENAME"
        if [[ -n "$NODEDOMAIN" ]]; then
          echo "NODENAME=$NODENAME" > "$ENV_FILE"
          echo "NODEDOMAIN=$NODEDOMAIN" >> "$ENV_FILE"
        else
          echo "NODENAME=$NODENAME" > "$ENV_FILE"
        fi
        break
      else
        echo "❌ 节点名称不能为空，请重新输入。"
      fi
    done
  fi
}

function validate_config() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 配置文件 $CONFIG_PATH 不存在，请先运行 './ss.sh install' 创建配置。"
    exit 1
  fi
  if ! jq -e '.password' "$CONFIG_PATH" >/dev/null 2>&1; then
    echo "⚠️ 配置文件格式无效，缺少 password 字段。"
    exit 1
  fi
}

function print_client_info() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 未找到配置文件，无法生成客户端信息。"
    return
  fi

  SERVER_PORT=$(jq '.server_port' "$CONFIG_PATH")
  METHOD=$(jq -r '.method' "$CONFIG_PATH")
  PASSWORD=$(jq -r '.password' "$CONFIG_PATH")
  NODENAME=$(source "$ENV_FILE" && echo "$NODENAME")
  NODEDOMAIN=$(source "$ENV_FILE" && echo "$NODEDOMAIN")
  if [[ -n "$NODEDOMAIN" ]]; then
    ADD="$NODEDOMAIN"
    echo "📌 使用节点域名: $ADD"
  else
    ADD=$(curl -s ipv4.ip.sb || echo "your.server.com")
    echo "📌 使用服务器 IP: $ADD"
  fi

  echo "✅ 客户端配置信息："
  echo "-------------------------------------------"
  echo "协议     : Shadowsocks"
  echo "地址     : $ADD"
  echo "端口     : $SERVER_PORT"
  echo "加密方法 : $METHOD"
  echo "密码     : $PASSWORD"
  echo "节点名   : $NODENAME"
  echo "-------------------------------------------"

  SS_URI=$(echo -n "$METHOD:$PASSWORD@$ADD:$SERVER_PORT" | base64 -w 0)
  SS_LINK="ss://$SS_URI#$NODENAME"

  echo "📱 Clash 配置示例："
  echo "proxies:"
  echo "  - name: $NODENAME"
  echo "    type: ss"
  echo "    server: $ADD"
  echo "    port: $SERVER_PORT"
  echo "    cipher: $METHOD"
  echo "    password: \"$PASSWORD\""

  echo "SS 链接: "
  echo "$SS_LINK"
  echo "-------------------------------------------"
  if command -v qrencode >/dev/null 2>&1; then
    echo "📷 二维码："
    echo "$SS_LINK" | qrencode -t ANSIUTF8
  else
    echo "（未安装 qrencode，跳过二维码）"
  fi
}

function backup_config() {
  if [[ -f "$CONFIG_PATH" ]]; then
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp "$CONFIG_PATH" "$BACKUP_DIR/config_$TIMESTAMP.json"
    echo "🗂️ 原配置已备份到: $BACKUP_DIR/config_$TIMESTAMP.json"
  fi
}

function start_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在启动 Shadowsocks 服务..."
  systemctl start "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已启动。" || {
    echo "❌ 启动 Shadowsocks 服务失败，请检查日志：$LOG_DIR/ss-server.log 或 journalctl -u shadowsocks.service"
    exit 1
  }
}

function stop_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在停止 Shadowsocks 服务..."
  systemctl stop "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已停止。" || {
    echo "❌ 停止 Shadowsocks 服务失败，请检查日志：$LOG_DIR/ss-server.log 或 journalctl -u shadowsocks.service"
    exit 1
  }
}

function restart_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在重启 Shadowsocks 服务..."
  systemctl restart "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已重启。" || {
    echo "❌ 重启 Shadowsocks 服务失败，请检查日志：$LOG_DIR/ss-server.log 或 journalctl -u shadowsocks.service"
    exit 1
  }
}

function enable_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在启用 Shadowsocks 服务开机自启动..."
  systemctl enable "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已设置为开机自启动。" || {
    echo "❌ 启用自启动失败，请检查 systemctl 配置。"
    exit 1
  }
}

function disable_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📌 正在禁用 Shadowsocks 服务开机自启动..."
  systemctl disable "$SERVICE_NAME" && echo "✅ Shadowsocks 服务已移除开机自启动。" || {
    echo "❌ 禁用自启动失败，请检查 systemctl 配置。"
    exit 1
  }
}

function status_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📋 Shadowsocks 服务状态："
  systemctl status "$SERVICE_NAME" --no-pager || {
    echo "⚠️ 获取服务状态失败，请检查 systemctl 配置。"
    exit 1
  }
}

function logs_service() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "⚠️ Shadowsocks 服务未安装，请先运行 './ss.sh install'。"
    exit 1
  fi
  echo "📜 查看 Shadowsocks 服务日志："
  LOG_FILE="$LOG_DIR/ss-server.log"
  if [[ -f "$LOG_FILE" ]]; then
    echo "📄 日志文件: $LOG_FILE"
    tail -n 20 "$LOG_FILE" || {
      echo "⚠️ 无法读取日志文件: $LOG_FILE"
    }
    echo "-------------------------------------------"
  else
    echo "⚠️ 日志文件 $LOG_FILE 不存在。"
  fi
  echo "📄 Systemd 日志 (journalctl)："
  journalctl -u shadowsocks.service -n 20 --no-pager || {
    echo "⚠️ 无法读取 journalctl 日志。"
  }
}

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

function upgrade_shadowsocks() {
  check_root
  echo "🔄 正在升级 Shadowsocks 核心版本（配置文件将保留）..."
  apt-get update >/dev/null 2>&1
  apt-get install -y shadowsocks-libev >/dev/null 2>&1
  echo "✅ 升级完成。"

  print_client_info
}

function list_users() {
  validate_config

  echo "📋 当前用户："
  echo "-------------------------------------------"
  PASSWORD=$(jq -r '.password' "$CONFIG_PATH")
  if [[ -z "$PASSWORD" ]]; then
    echo "无用户（密码未设置）。"
    return
  fi
  echo "密码: $PASSWORD"
  echo "-------------------------------------------"
}

function add_user() {
  check_root
  validate_config

  PASSWORD=$(cat /proc/sys/kernel/random/uuid)
  echo "📌 自动生成密码: $PASSWORD"

  backup_config

  TEMP_FILE=$(mktemp)
  jq ".password = \"$PASSWORD\"" "$CONFIG_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CONFIG_PATH"
  chown root:shadowsocks "$CONFIG_PATH" || true
  chmod 644 "$CONFIG_PATH"

  restart_service

  echo "✅ 新用户密码设置完成！"
  print_client_info
}

function delete_user() {
  check_root
  validate_config

  list_users
  echo "是否删除当前用户密码（将禁用服务）？"
  read -p "确认 (y/N): " CONFIRM
  case "$CONFIRM" in
    [yY]) ;;
    *) echo "❌ 已取消删除操作。"; return ;;
  esac

  backup_config

  TEMP_FILE=$(mktemp)
  jq '.password = ""' "$CONFIG_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CONFIG_PATH"
  chown root:shadowsocks "$CONFIG_PATH" || true
  chmod 644 "$CONFIG_PATH"

  restart_service

  echo "✅ 用户密码已删除！"
  list_users
}

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

  read -p "请输入 Shadowsocks 服务端口 [默认: 8388]: " SERVER_PORT
  SERVER_PORT=${SERVER_PORT:-8388}
  echo "📌 使用服务端口: $SERVER_PORT"

  read -p "请输入 Shadowsocks 本地端口 [默认: 2080]: " LOCAL_PORT
  LOCAL_PORT=${LOCAL_PORT:-2080}
  echo "📌 使用本地端口: $LOCAL_PORT"

  echo "可用加密方法: aes-256-gcm, chacha20-ietf-poly1305, aes-128-gcm"
  read -p "请输入加密方法 [默认: chacha20-ietf-poly1305]: " METHOD
  METHOD=${METHOD:-chacha20-ietf-poly1305}
  echo "📌 加密方法: $METHOD"

  PASSWORD=$(cat /proc/sys/kernel/random/uuid)
  echo "📌 自动生成密码: $PASSWORD"

  load_env

  echo "🧩 写入配置文件..."
  cat > "$CONFIG_PATH" <<EOF
{
    "server": ["::", "0.0.0.0"],
    "mode": "tcp_and_udp",
    "server_port": $SERVER_PORT,
    "local_port": $LOCAL_PORT,
    "password": "$PASSWORD",
    "timeout": 300,
    "method": "$METHOD"
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
  print_client_info
}

# 参数分发入口
case "$1" in
  install)
    install_shadowsocks
    ;;
  upgrade)
    upgrade_shadowsocks
    ;;
  uninstall)
    uninstall_shadowsocks
    ;;
  adduser)
    add_user
    ;;
  deluser)
    delete_user
    ;;
  listusers)
    list_users
    ;;
  start)
    start_service
    ;;
  stop)
    stop_service
    ;;
  restart)
    restart_service
    ;;
  enable)
    enable_service
    ;;
  disable)
    disable_service
    ;;
  status)
    status_service
    ;;
  logs)
    logs_service
    ;;
  *)
    echo "❌ 参数错误！可用命令：install / upgrade / uninstall / adduser / deluser / listusers / start / stop / restart / enable / disable / status / logs"
    echo "使用示例："
    echo "  ./ss.sh install     # 安装并覆盖配置"
    echo "  ./ss.sh upgrade     # 升级核心，保留配置"
    echo "  ./ss.sh uninstall   # 卸载"
    echo "  ./ss.sh adduser     # 设置新用户密码"
    echo "  ./ss.sh deluser     # 删除用户密码"
    echo "  ./ss.sh listusers   # 列出当前用户"
    echo "  ./ss.sh start       # 启动服务"
    echo "  ./ss.sh stop        # 停止服务"
    echo "  ./ss.sh restart     # 重启服务"
    echo "  ./ss.sh enable      # 启用开机自启动"
    echo "  ./ss.sh disable     # 禁用开机自启动"
    echo "  ./ss.sh status      # 查看服务状态"
    echo "  ./ss.sh logs        # 查看服务日志"
    exit 1
    ;;
esac
