#!/bin/bash
#用户管理模块

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/service.sh"

# 验证用户配置文件
function validate_users() {
  if [[ ! -f "$USERS_PATH" ]]; then
    echo "⚠️ 用户配置文件 $USERS_PATH 不存在，将创建新文件。"
    echo '{
      "users": {}
    }' > "$USERS_PATH"
    chown root:shadowsocks "$USERS_PATH" || true
    chmod 644 "$USERS_PATH"
  fi
}

# 同步用户配置到 config.json
function sync_users_to_config() {
  validate_users
  TEMP_FILE=$(mktemp)
  
  # 从 users.json 构建 port_password 对象
  PORT_PASSWORD=$(jq -r '.users | to_entries | reduce .[] as $item ({}; . + {($item.value.port | tostring): $item.value.password})' "$USERS_PATH")
  
  # 更新 config.json
  jq --argjson pp "$PORT_PASSWORD" '.port_password = $pp' "$CONFIG_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CONFIG_PATH"
  chown root:shadowsocks "$CONFIG_PATH" || true
  chmod 644 "$CONFIG_PATH"
}

# 列出用户
function list_users() {
  validate_users
  echo "📋 当前用户列表："
  echo "-------------------------------------------"
  jq -r '.users | to_entries[] | "用户名: \(.key)\n端口: \(.value.port)\n密码: \(.value.password)\n创建时间: \(.value.created_at)\n描述: \(.value.description)\n-------------------------------------------"' "$USERS_PATH"
}

# 添加用户
function add_user() {
  check_root
  validate_users
  validate_config

  read -p "请输入用户名称: " USERNAME
  if [[ -z "$USERNAME" ]]; then
    echo "❌ 用户名称不能为空。"
    return
  fi

  read -p "请输入用户描述 [可选]: " DESCRIPTION
  DESCRIPTION=${DESCRIPTION:-"用户 $USERNAME"}

  read -p "请输入端口 [默认: 随机端口]: " PORT
  if [[ -z "$PORT" ]]; then
    PORT=$((RANDOM % 10000 + 50000))
  fi
  
  PASSWORD=$(cat /proc/sys/kernel/random/uuid)
  echo "📌 端口: $PORT"
  echo "📌 自动生成密码: $PASSWORD"

  backup_config

  # 更新 users.json
  TEMP_FILE=$(mktemp)
  jq --arg un "$USERNAME" \
     --arg port "$PORT" \
     --arg pass "$PASSWORD" \
     --arg desc "$DESCRIPTION" \
     --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
     '.users += {($un): {"port": ($port|tonumber), "password": $pass, "created_at": $time, "description": $desc}}' \
     "$USERS_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$USERS_PATH"
  chown root:shadowsocks "$USERS_PATH" || true
  chmod 644 "$USERS_PATH"

  # 同步到 config.json
  sync_users_to_config

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
  validate_users
  validate_config

  list_users
  read -p "请输入要删除的用户名称: " USERNAME
  if [[ -z "$USERNAME" ]]; then
    echo "❌ 用户名称不能为空。"
    return
  fi

  if ! jq -e ".users[\"$USERNAME\"]" "$USERS_PATH" >/dev/null 2>&1; then
    echo "❌ 指定用户不存在。"
    return
  fi

  PORT=$(jq -r ".users[\"$USERNAME\"].port" "$USERS_PATH")
  echo "是否删除用户 $USERNAME (端口: $PORT)？"
  read -p "确认 (y/N): " CONFIRM
  case "$CONFIRM" in
    [yY]) ;;
    *) echo "❌ 已取消删除操作。"; return ;;
  esac

  backup_config

  # 更新 users.json
  TEMP_FILE=$(mktemp)
  jq "del(.users[\"$USERNAME\"])" "$USERS_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$USERS_PATH"
  chown root:shadowsocks "$USERS_PATH" || true
  chmod 644 "$USERS_PATH"

  # 同步到 config.json
  sync_users_to_config

  restart_service

  echo "✅ 用户已删除！"
  list_users
}