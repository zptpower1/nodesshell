#!/bin/bash
#用户管理模块

source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/service.sh"

# 列出用户
function list_users() {
  validate_config
  echo "📋 当前用户列表："
  echo "-------------------------------------------"
  jq -r '.port_password | to_entries[] | "端口: \(.key)\n密码: \(.value)\n-------------------------------------------"' "$CONFIG_PATH"
}

# 添加用户
function add_user() {
  check_root
  validate_config

  read -p "请输入新用户端口 [默认: 随机端口]: " PORT
  if [[ -z "$PORT" ]]; then
    PORT=$((RANDOM % 10000 + 50000))
  fi
  
  PASSWORD=$(cat /proc/sys/kernel/random/uuid)
  echo "📌 端口: $PORT"
  echo "📌 自动生成密码: $PASSWORD"

  backup_config

  TEMP_FILE=$(mktemp)
  jq ".port_password += {\"$PORT\": \"$PASSWORD\"}" "$CONFIG_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CONFIG_PATH"
  chown root:shadowsocks "$CONFIG_PATH" || true
  chmod 644 "$CONFIG_PATH"

  # 配置防火墙规则
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT"/tcp
    ufw allow "$PORT"/udp
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
    iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  fi

  restart_service

  echo "✅ 新用户添加完成！"
  print_client_info
}

# 删除用户
function delete_user() {
  check_root
  validate_config

  list_users
  read -p "请输入要删除的端口: " PORT
  if [[ -z "$PORT" ]]; then
    echo "❌ 端口不能为空。"
    return
  fi

  if ! jq -e ".port_password[\"$PORT\"]" "$CONFIG_PATH" >/dev/null 2>&1; then
    echo "❌ 指定端口不存在。"
    return
  fi

  echo "是否删除端口 $PORT？"
  read -p "确认 (y/N): " CONFIRM
  case "$CONFIRM" in
    [yY]) ;;
    *) echo "❌ 已取消删除操作。"; return ;;
  esac

  backup_config

  TEMP_FILE=$(mktemp)
  jq "del(.port_password[\"$PORT\"])" "$CONFIG_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CONFIG_PATH"
  chown root:shadowsocks "$CONFIG_PATH" || true
  chmod 644 "$CONFIG_PATH"

  restart_service

  echo "✅ 用户已删除！"
  list_users
}