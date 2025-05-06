#!/bin/bash
set -e

CONFIG_PATH="/usr/local/etc/xray/config.json"
BACKUP_DIR="/usr/local/etc/xray/backup"
XRAY_BIN="/usr/local/bin/xray"
QR_TOOL="qrencode"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ENV_FILE="$SCRIPT_DIR/.env"

function ensure_xray_user() {
  # Check if xray group exists
  if ! getent group xray >/dev/null; then
    echo "📌 创建 xray 组..."
    groupadd -r xray || {
      echo "⚠️ 无法创建 xray 组，使用 nobody 组作为回退。"
      return 1
    }
  fi

  # Check if xray user exists
  if ! id xray >/dev/null 2>&1; then
    echo "📌 创建 xray 用户..."
    useradd -r -g xray -s /sbin/nologin -M xray || {
      echo "⚠️ 无法创建 xray 用户，使用 nobody 用户作为回退。"
      return 1
    }
  fi
  echo "✅ xray 用户和组已准备就绪。"
}

function load_nodename() {
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    if [[ -n "$NODENAME" ]]; then
      echo "📌 从 .env 文件读取节点名称: $NODENAME"
      if [[ -n "$NODEDOMAIN" ]]; then
        echo "📌 从 .env 文件读取节点域名: $NODEDOMAIN"
      fi
      return
    fi
  fi

  echo "⚠️ 未找到 .env 文件或 NODENAME 未设置。"
  while true; do
    read -p "请输入节点名称（不能为空）: " NODENAME
    if [[ -n "$NODENAME" ]]; then
      echo "📌 设置节点名称: $NODENAME"
      read -p "请输入节点域名（可选，直接回车跳过）: " NODEDOMAIN
      if [[ -n "$NODEDOMAIN" ]]; then
        echo "📌 设置节点域名: $NODEDOMAIN"
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
}

function validate_config() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 配置文件 $CONFIG_PATH 不存在，请先运行 './xray.sh install' 创建配置。"
    exit 1
  fi
  if ! jq -e '.inbounds[0].settings.clients' "$CONFIG_PATH" >/dev/null 2>&1; then
    echo "⚠️ 配置文件格式无效，缺少 inbounds[0].settings.clients 数组。"
    exit 1
  fi
}

function print_client_info() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 未找到配置文件，无法生成客户端信息。"
    return
  fi

  PORT=$(jq '.inbounds[0].port' "$CONFIG_PATH")
  SERVER_NAME=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_PATH")
  PUBLIC_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$CONFIG_PATH")
  SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_PATH")
  NODENAME=$(jq -r '.inbounds[0].nodename // "Unknown"' "$CONFIG_PATH")
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    if [[ -n "$NODEDOMAIN" ]]; then
      ADD="$NODEDOMAIN"
      echo "📌 使用节点域名: $ADD"
    else
      ADD=$(curl -s ipv4.ip.sb || echo "your.server.com")
      echo "📌 使用服务器 IP: $ADD"
    fi
  else
    ADD=$(curl -s ipv4.ip.sb || echo "your.server.com")
    echo "📌 使用服务器 IP: $ADD"
  fi

  echo "✅ 客户端配置信息："
  echo "-------------------------------------------"
  echo "协议     : VLESS + Reality"
  echo "地址     : $ADD"
  echo "端口     : $PORT"
  echo "伪装域名 : $SERVER_NAME"
  echo "公钥     : $PUBLIC_KEY"
  echo "short ID : $SHORT_ID"
  echo "节点名   : $NODENAME"
  echo "-------------------------------------------"

  CLIENTS_COUNT=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_PATH")
  for ((i=0; i<CLIENTS_COUNT; i++)); do
    UUID=$(jq -r ".inbounds[0].settings.clients[$i].id" "$CONFIG_PATH")
    USER_NAME=$(jq -r ".inbounds[0].settings.clients[$i].name" "$CONFIG_PATH")

    echo "用户 $((i+1)):"
    echo "用户名称 : $USER_NAME"
    echo "UUID     : $UUID"

    echo "📱 Clash.Meta 配置示例："
    echo "proxies:"
    echo "  - name: $NODENAME"
    echo "    type: vless"
    echo "    server: $ADD"
    echo "    port: $PORT"
    echo "    uuid: $UUID"
    echo "    network: tcp"
    echo "    client-fingerprint: chrome"
    echo "    udp: true"
    echo "    tls: true"
    echo "    servername: $SERVER_NAME"
    echo "    reality-opts:"
    echo "      public-key: $PUBLIC_KEY"
    echo "      short-id: \"$SHORT_ID\""

    VLESS_LINK="vless://$UUID@$ADD:$PORT?encryption=none&flow=&type=tcp&security=reality&host=$SERVER_NAME&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&udp=true#$NODENAME"
    echo "VLESS链接: "
    echo "$VLESS_LINK"
    echo "-------------------------------------------"
    if command -v $QR_TOOL >/dev/null 2>&1; then
      echo "📷 二维码："
      echo "$VLESS_LINK" | $QR_TOOL -t ANSIUTF8
    else
      echo "（未安装 qrencode，跳过二维码）"
    fi
  done
}

function backup_config() {
  if [[ -f "$CONFIG_PATH" ]]; then
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp "$CONFIG_PATH" "$BACKUP_DIR/config_$TIMESTAMP.json"
    echo "🗂️ 原配置已备份到: $BACKUP_DIR/config_$TIMESTAMP.json"
  fi
}

function uninstall_xray() {
  echo "⚠️ 即将卸载 Xray，并删除其所有配置文件和程序。"
  read -p "确认要继续卸载吗？(y/N): " CONFIRM
  case "$CONFIRM" in
    [yY]) echo "✅ 继续卸载..." ;;
    *) echo "❌ 已取消卸载操作。"; exit 1 ;;
  esac

  systemctl stop xray
  systemctl disable xray
  rm -f /etc/systemd/system/xray.service
  rm -rf /usr/local/etc/xray
  rm -f /usr/local/bin/xray
  rm -rf /var/log/xray
  rm -rf /usr/local/share/xray
  rm -f /etc/systemd/system/xray@.service
  systemctl daemon-reload

  echo "✅ 卸载完成。"
}

function upgrade_xray() {
  echo "🔄 正在升级 Xray 核心版本（配置文件将保留）..."
  bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) >/dev/null 2>&1
  echo "✅ 升级完成。"

  print_client_info
}

function list_users() {
  validate_config

  echo "📋 当前用户列表："
  echo "-------------------------------------------"
  CLIENTS_COUNT=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_PATH")
  if [[ $CLIENTS_COUNT -eq 0 ]]; then
    echo "无用户。"
    return
  fi
  for ((i=0; i<CLIENTS_COUNT; i++)); do
    UUID=$(jq -r ".inbounds[0].settings.clients[$i].id" "$CONFIG_PATH")
    USER_NAME=$(jq -r ".inbounds[0].settings.clients[$i].name" "$CONFIG_PATH")
    echo "用户 $((i+1)): 名称: $USER_NAME, UUID: $UUID"
  done
  echo "-------------------------------------------"
}

function add_user() {
  validate_config

  while true; do
    read -p "请输入新用户名称（不能为空）: " USER_NAME
    if [[ -n "$USER_NAME" ]]; then
      echo "📌 新用户名称: $USER_NAME"
      break
    else
      echo "❌ 用户名称不能为空，请重新输入。"
    fi
  done

  UUID=$(cat /proc/sys/kernel/random/uuid)
  echo "🔑 新用户 UUID: $UUID"

  backup_config

  TEMP_FILE=$(mktemp)
  jq ".inbounds[0].settings.clients += [{\"id\": \"$UUID\", \"name\": \"$USER_NAME\", \"flow\": \"\"}]" "$CONFIG_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CONFIG_PATH"
  chown root:xray "$CONFIG_PATH" || true
  chmod 644 "$CONFIG_PATH"

  echo "🚀 重启 Xray 服务..."
  systemctl restart xray

  echo "✅ 新用户添加完成！"
  print_client_info
}

function delete_user() {
  validate_config

  list_users
  echo "请输入要删除的用户的名称或 UUID："
  read -p "选择: " INPUT

  CLIENT_INDEX=""
  if [[ -n "$INPUT" ]]; then
    CLIENT_INDEX=$(jq -r ".inbounds[0].settings.clients | to_entries[] | select(.value.name == \"$INPUT\" or .value.id == \"$INPUT\") | .key" "$CONFIG_PATH")
  fi
  if [[ -z "$CLIENT_INDEX" ]]; then
    echo "⚠️ 未找到名称或 UUID 为 $INPUT 的用户。"
    return
  fi

  USER_NAME=$(jq -r ".inbounds[0].settings.clients[$CLIENT_INDEX].name" "$CONFIG_PATH")
  backup_config

  TEMP_FILE=$(mktemp)
  jq "del(.inbounds[0].settings.clients[$CLIENT_INDEX])" "$CONFIG_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CONFIG_PATH"

  echo "🚀 重启 Xray 服务..."
  systemctl restart xray

  echo "✅ 用户 $USER_NAME 已删除！"
  list_users
}

function install_xray() {
  echo "📦 开始全新安装 Xray-core..."

  if [[ -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 检测到已有配置文件：$CONFIG_PATH"
    read -p "是否覆盖已有配置并继续安装？(y/N): " CONFIRM
    case "$CONFIRM" in
      [yY]) backup_config ;;
      *) echo "❌ 已取消安装操作。"; exit 1 ;;
    esac
  fi

  echo "📌 安装 Xray..."
  bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) >/dev/null 2>&1
  mkdir -p /usr/local/etc/xray
  mkdir -p /var/log/xray
  ensure_xray_user
  chown xray:xray /var/log/xray || true
  chmod 755 /var/log/xray

  read -p "请输入 Reality 监听端口 [默认: 8443]: " PORT
  PORT=${PORT:-8443}
  echo "📌 使用端口: $PORT"

  read -p "请输入用户数量 [默认: 1]: " USER_COUNT
  USER_COUNT=${USER_COUNT:-1}
  if [[ ! $USER_COUNT =~ ^[0-9]+$ ]] || [[ $USER_COUNT -lt 1 ]]; then
    echo "❌ 用户数量必须为正整数，设置为默认值 1。"
    USER_COUNT=1
  fi
  echo "📌 用户数量: $USER_COUNT"

  load_nodename

  CLIENTS_JSON="[]"
  for ((i=1; i<=USER_COUNT; i++)); do
    while true; do
      read -p "请输入用户 $i 名称（不能为空）: " USER_NAME
      if [[ -n "$USER_NAME" ]]; then
        echo "📌 用户 $i 名称: $USER_NAME"
        break
      else
        echo "❌ 用户名称不能为空，请重新输入。"
      fi
    done
    UUID=$(cat /proc/sys/kernel/random/uuid)
    CLIENTS_JSON=$(echo "$CLIENTS_JSON" | jq ". += [{\"id\": \"$UUID\", \"name\": \"$USER_NAME\", \"flow\": \"\"}]")
  done

  echo "🔑 正在生成 Reality 密钥对..."
  KEYS=$(xray x25519)
  PRIVATE_KEY=$(echo "$KEYS" | grep 'Private key:' | awk '{print $3}')
  PUBLIC_KEY=$(echo "$KEYS" | grep 'Public key:' | awk '{print $3}')
  FAKE_DOMAIN="www.cloudflare.com"
  SHORT_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 6)

  echo "🧩 写入配置文件..."
  cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "nodename": "$NODENAME",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": $CLIENTS_JSON,
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$FAKE_DOMAIN:443",
          "xver": 0,
          "serverNames": ["$FAKE_DOMAIN"],
          "privateKey": "$PRIVATE_KEY",
          "publicKey": "$PUBLIC_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
  chown root:xray "$CONFIG_PATH" || true
  chmod 644 "$CONFIG_PATH"

  echo "🛡️ 配置防火墙规则..."
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT"/tcp
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
  fi

  echo "🚀 启动 Xray 服务..."
  systemctl daemon-reexec
  systemctl restart xray
  systemctl enable xray

  echo "✅ 安装完成！"
  
  # 创建软链接方便调试
  echo "📌 创建配置和日志软链接..."
  if [[ ! -f "config.json" ]]; then
    ln -s "$CONFIG_PATH" ./config.json && echo "✅ 配置文件软链接创建成功。" || echo "⚠️ 配置文件软链接创建失败。"
  else
    echo "⚠️ 当前目录已存在 config.json 文件，跳过创建软链接。"
  fi

  if [[ ! -d "logs" ]]; then
    ln -s "/var/log/xray" ./logs && echo "✅ 日志目录软链接创建成功。" || echo "⚠️ 日志目录软链接创建失败。"
  else
    echo "⚠️ 当前目录已存在 logs 目录，跳过创建软链接。"
  fi

  echo "以下是连接信息："
  print_client_info
}

# 参数分发入口
case "$1" in
  install)
    install_xray
    ;;
  upgrade)
    upgrade_xray
    ;;
  uninstall)
    uninstall_xray
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
  *)
    echo "❌ 参数错误！可用命令：install / upgrade / uninstall / adduser / deluser / listusers"
    echo "使用示例："
    echo "  ./xray.sh install     # 安装并覆盖配置"
    echo "  ./xray.sh upgrade     # 升级核心，保留配置"
    echo "  ./xray.sh uninstall   # 卸载"
    echo "  ./xray.sh adduser     # 添加新用户"
    echo "  ./xray.sh deluser     # 删除用户"
    echo "  ./xray.sh listusers   # 列出所有用户"
    exit 1
    ;;
esac
