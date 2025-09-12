#!/bin/bash
# ==========================================
# 智能 rsync 脚本（最终版）
# 默认后台运行，支持 SSH key 或密码登录
# 如果密码登录且 sshpass 未安装，自动前台运行
# 用法:
#   ./rsync_backup.sh <SRC_DIR> <DEST_USER>@<DEST_HOST>:<DEST_DIR> [PORT]
# ==========================================

if [ $# -lt 2 ]; then
    echo "用法: $0 <SRC_DIR> <DEST_USER>@<DEST_HOST>:<DEST_DIR> [PORT]"
    exit 1
fi

SRC_DIR="$1"
DEST="$2"
PORT="${3:-22}"

DEST_USER="${DEST%@*}"
DEST_HOST="$(echo "$DEST" | cut -d'@' -f2 | cut -d':' -f1)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/rsync_$(date +%Y%m%d_%H%M%S).log"

# ==== 1. 检测主机可达 ====
ping -c 2 "$DEST_HOST" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ 远程主机不可达: $DEST_HOST"
    exit 1
fi

# ==== 2. 检测 SSH key 登录是否成功 ====
SSH_KEY=""
if [ -f "$HOME/.ssh/id_rsa" ]; then
    SSH_KEY="$HOME/.ssh/id_rsa"
elif [ -f "$HOME/.ssh/id_ed25519" ]; then
    SSH_KEY="$HOME/.ssh/id_ed25519"
fi

SSH_OPTS="-p ${PORT} -o StrictHostKeyChecking=no"

if [ -n "$SSH_KEY" ]; then
    SSH_OPTS_KEY="$SSH_OPTS -i $SSH_KEY -o BatchMode=yes"
    ssh $SSH_OPTS_KEY "$DEST_USER@$DEST_HOST" "echo 1" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ SSH key 登录成功，rsync 默认后台运行"
        nohup rsync -avzP -e "ssh $SSH_OPTS_KEY" "$SRC_DIR" "$DEST" >> "$LOG_FILE" 2>&1 &
        PID=$!
        echo "后台 PID: $PID"
        echo "日志文件: $LOG_FILE"
        echo "查看实时日志: tail -f $LOG_FILE"
        exit 0
    fi
fi

# ==== 3. 密码登录模式 ====
echo "⚠️ SSH key 登录失败，需要使用密码登录"

# 判断 sshpass 是否安装
if ! command -v sshpass >/dev/null 2>&1; then
    echo "⚠️ 系统未安装 sshpass，自动进入前台模式"
    rsync -avzP -e "ssh $SSH_OPTS" "$SRC_DIR" "$DEST"
    exit 0
fi

# sshpass 已安装，用户选择前台或后台，默认后台
read -p "选择模式：1) 前台运行 2) 后台运行（sshpass，默认） [2]: " MODE
MODE=${MODE:-2}  # 默认后台

read -s -p "请输入远程密码: " PASSWORD
echo

if [ "$MODE" == "1" ]; then
    echo "ℹ️ 前台运行模式"
    rsync -avzP -e "ssh $SSH_OPTS" "$SRC_DIR" "$DEST"
elif [ "$MODE" == "2" ]; then
    echo "ℹ️ 使用 sshpass 后台运行 rsync"
    nohup sshpass -p "$PASSWORD" rsync -avzP -e "ssh $SSH_OPTS" "$SRC_DIR" "$DEST" >> "$LOG_FILE" 2>&1 &
    PID=$!
    echo "后台 PID: $PID"
    echo "日志文件: $LOG_FILE"
    echo "查看实时日志: tail -f $LOG_FILE"
else
    echo "❌ 无效选项"
    exit 1
fi