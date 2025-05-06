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
    read -p "请输入要查询的用户名或关键词: " SEARCH_TERM
    if [[ -z "$SEARCH_TERM" ]]; then
      echo "⚠️ 搜索关键词不能为空。"
      return
    fi

    # 使用 list_users 函数进行模糊查询
    MATCHED_USERS=$(jq -r --arg term "$SEARCH_TERM" '
      .users 
      | to_entries[] 
      | select(
          (.key | ascii_downcase | contains($term | ascii_downcase)) or
          (.value.description | ascii_downcase | contains($term | ascii_downcase))
        )
      | .key' "$USERS_PATH")

    # 统计匹配用户数量
    USERS_COUNT=$(echo "$MATCHED_USERS" | grep -c "^" || echo 0)

    case $USERS_COUNT in
      0)
        echo "⚠️ 未找到匹配的用户。"
        return
        ;;
      1)
        USERNAME=$(echo "$MATCHED_USERS" | head -n1)
        echo "📌 找到唯一匹配用户: $USERNAME"
        ;;
      *)
        echo "📋 找到多个匹配用户:"
        echo "$MATCHED_USERS" | nl
        while true; do
          read -p "请输入要查询的用户编号 [1-$USERS_COUNT]: " USER_NUM
          if [[ "$USER_NUM" =~ ^[0-9]+$ ]] && [ "$USER_NUM" -ge 1 ] && [ "$USER_NUM" -le "$USERS_COUNT" ]; then
            USERNAME=$(echo "$MATCHED_USERS" | sed -n "${USER_NUM}p")
            break
          else
            echo "❌ 无效的编号，请重新输入。"
          fi
        done
        ;;
    esac
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
  echo "    password: \"$PASSWORD\""

  # 生成 SS 链接和二维码
  CONFIG="$METHOD:$PASSWORD@$ADD:$PORT"
  SS_URL="ss://$(echo -n "$CONFIG" | base64)#$NODENAME"
  echo "🔗 SS 链接: $SS_URL"
  echo "🔲 二维码:"
  echo "$SS_URL" | qrencode -t UTF8
  echo "-------------------------------------------"
}

# 查询用户信息
function query_user_info() {
  validate_users
  
  # 如果提供了搜索关键词，则进行模糊匹配
  read -p "请输入搜索关键词 [可选，直接回车显示所有]: " SEARCH_TERM
  
  echo "📋 查询结果："
  echo "========================================="
  
  if [[ -n "$SEARCH_TERM" ]]; then
    echo "🔍 搜索关键词: $SEARCH_TERM"
    # 使用 jq 查找匹配的用户
    MATCHED_USERS=$(jq -r --arg term "$SEARCH_TERM" '
      .users 
      | to_entries[] 
      | select(
          (.key | ascii_downcase | contains($term | ascii_downcase)) or
          (.value.description | ascii_downcase | contains($term | ascii_downcase)) or
          (.value.created_at | contains($term))
        )
      | .key' "$USERS_PATH")
  else
    # 获取所有用户
    MATCHED_USERS=$(jq -r '.users | keys[]' "$USERS_PATH")
  fi

  # 将匹配结果转换为数组并打印每个用户的信息
  while IFS= read -r USERNAME; do
    if [[ -n "$USERNAME" ]]; then
      echo "用户信息："
      jq -r --arg un "$USERNAME" '
        .users[$un] | 
        "用户名: \($un)\n端口: \(.port)\n密码: \(.password)\n创建时间: \(.created_at)\n描述: \(.description)"
      ' "$USERS_PATH"
      echo "连接信息："
      print_client_info "$USERNAME"
      echo "========================================="
    fi
  done <<< "$MATCHED_USERS"
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