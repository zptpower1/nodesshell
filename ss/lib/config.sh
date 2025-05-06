#!/bin/bash
#配置管理模块

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 验证配置文件
function validate_config() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 配置目录 $CONFIG_PATH 不存在，请先运行 './ss.sh install' 创建配置。"
    exit 1
  fi
  if ! jq -e '.port_password' "$CONFIG_PATH" >/dev/null 2>&1; then
    echo "⚠️ 配置文件格式无效，缺少 port_password 字段。"
    exit 1
  fi
}

# 打印客户端信息
function print_client_info() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 未找到配置文件"
    return
  fi

  METHOD=$(jq -r '.method' "$CONFIG_PATH")
  NODENAME=$(source "$ENV_FILE" && echo "$NODENAME")
  NODEDOMAIN=$(source "$ENV_FILE" && echo "$NODEDOMAIN")
  if [[ -n "$NODEDOMAIN" ]]; then
    ADD="$NODEDOMAIN"
    echo "📌 使用节点域名: $ADD"
  else
    ADD=$(curl -s ipv4.ip.sb || echo "your.server.com")
    echo "📌 使用服务器 IP: $ADD"
  fi

  # 获取用户的端口和密码
  PORT=$(jq -r '.server_port' "$CONFIG_PATH")
  PASSWORD=$(jq -r '.password' "$CONFIG_PATH")

  echo "📱 Clash 配置："
  echo "  - name: $NODENAME"
  echo "    type: ss"
  echo "    server: $ADD"
  echo "    port: $PORT"
  echo "    cipher: $METHOD"
  echo "    password: $PASSWORD"

  # 生成 SS 链接和二维码
  CONFIG="$METHOD:$PASSWORD@$ADD:$PORT"
  SS_URL="ss://$(echo -n "$CONFIG" | base64 -w 0)#$NODENAME"
  echo "🔗 SS 链接:"
  echo "$SS_URL"
  
  # 根据环境变量配置决定是否显示二维码
  SHOW_QRCODE=$(source "$ENV_FILE" && echo "${SHOWQRCODE:-false}")
  if [[ "$SHOW_QRCODE" == "true" ]]; then
    echo "🔲 二维码:"
    echo "$SS_URL" | qrencode -t UTF8
  fi
  echo "-------------------------------------------"
}

# 备份配置
function backup_config() {
  if [[ -f "$CONFIG_PATH" ]]; then
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp "$CONFIG_PATH" "$BACKUP_DIR/config_$TIMESTAMP.json"
    echo "🗂️ 原配置已备份到: $BACKUP_DIR/config_$TIMESTAMP.json"
  fi
}