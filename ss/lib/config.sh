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
  local USERNAME="$1"
  if [[ ! -f "$CONFIG_PATH" ]] || [[ ! -f "$USERS_PATH" ]]; then
    echo "⚠️ 未找到配置文件，无法生成客户端信息。"
    return
  fi

  # 如果没有提供用户名参数，进入交互式查询模式
  if [[ -z "$USERNAME" ]]; then
    read -p "请输入要查询的用户名 [可选，直接回车显示所有]: " USERNAME
  fi

  if ! jq -e ".users[\"$USERNAME\"]" "$USERS_PATH" >/dev/null 2>&1; then
    echo "⚠️ 用户 $USERNAME 不存在。"
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
  PORT=$(jq -r --arg un "$USERNAME" '.users[$un].port' "$USERS_PATH")
  PASSWORD=$(jq -r --arg un "$USERNAME" '.users[$un].password' "$USERS_PATH")

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

# 查询用户信息
function query_user_info() {
  validate_users

  # 如果提供了命令行参数，则使用参数作为搜索关键词
  if [[ -n "$1" ]]; then
    SEARCH_TERM="$1"
  else
    # 否则交互式输入用户名
    read -p "请输入用户名: " SEARCH_TERM
  fi
  
  # 必须提供用户名参数
  if [[ -z "$SEARCH_TERM" ]]; then
    echo "❌ 错误：必须提供用户名参数。"
    echo "使用方法: ./ss.sh query <用户名>"
    return 1
  fi

  USERNAME="$SEARCH_TERM"
  
  echo "📋 查询结果："
  echo "========================================="
  
  # 检查用户是否存在
  if ! jq -e ".users[\"$USERNAME\"]" "$USERS_PATH" >/dev/null 2>&1; then
    echo "⚠️ 用户 $USERNAME 不存在。"
    return 1
  fi

  # 显示用户信息
  echo "用户信息："
  jq -r --arg un "$USERNAME" '
    .users[$un] | 
    "用户名: \($un)\n端口: \(.port)\n密码: \(.password)\n创建时间: \(.created_at)\n描述: \(.description)"
  ' "$USERS_PATH"
  echo "连接信息："
  print_client_info "$USERNAME"
  echo "========================================="
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