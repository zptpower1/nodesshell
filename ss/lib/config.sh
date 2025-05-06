#!/bin/bash
#配置管理模块

source "$(dirname "$0")/utils.sh"

# 验证配置文件
function validate_config() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "⚠️ 配置文件 $CONFIG_PATH 不存在，请先运行 './ss.sh install' 创建配置。"
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
    echo "⚠️ 未找到配置文件，无法生成客户端信息。"
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

  echo "✅ 所有端口配置信息："
  echo "-------------------------------------------"
  jq -r '.port_password | to_entries[] | "端口: \(.key)\n密码: \(.value)\n-------------------------------------------"' "$CONFIG_PATH"

  echo "📱 Clash 配置示例："
  echo "proxies:"
  jq -r '.port_password | to_entries[] | "  - name: \($ENV.NODENAME)-\(.key)\n    type: ss\n    server: \($ENV.ADD)\n    port: \(.key)\n    cipher: \($ENV.METHOD)\n    password: \"\(.value)\""' --arg ENV "$NODENAME" --arg ADD "$ADD" --arg METHOD "$METHOD" "$CONFIG_PATH"

  echo "SS 链接: "
  jq -r '.port_password | to_entries[] | "ss://\(($ENV.METHOD + ":" + .value + "@" + $ENV.ADD + ":" + .key) | @base64)#\($ENV.NODENAME)-\(.key)"' --arg ENV "$NODENAME" --arg ADD "$ADD" --arg METHOD "$METHOD" "$CONFIG_PATH"
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