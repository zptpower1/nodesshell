#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 创建服务
setup_service() {
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Sing-box Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=${SING_BIN} run -c ${CONFIG_PATH}
Restart=on-failure
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    systemctl start ${SERVICE_NAME}
}

# 检查服务状态
check_service() {
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo "✅ ${SERVICE_NAME} 服务运行正常"
        return 0
    else
        echo "❌ ${SERVICE_NAME} 服务运行异常"
        return 1
    fi
}

# 停止服务
stop_service() {
    echo "🛑 停止服务..."
    if pgrep -x "sing-box" > /dev/null; then
        kill $(pgrep -x "sing-box")
        echo "✅ 服务已停止"
    else
        echo "⚠️ 服务未运行"
    fi
}

# 禁用服务
disable_service() {
    echo "🔒 禁用服务..."
    if pgrep -x "sing-box" > /dev/null; then
        stop_service
    fi
    
    if [ -f "${SERVICE_FILE}" ]; then
        rm -f "${SERVICE_FILE}"
        echo "✅ 服务已禁用"
    else
        echo "⚠️ 服务配置不存在"
    fi
}

# 查看服务状态详情
status_service() {
    echo "📊 服务状态检查..."
    
    # 检查进程
    if pgrep -x "sing-box" > /dev/null; then
        echo "✅ 服务进程运行中"
        echo
        echo "📈 进程信息："
        ps aux | grep sing-box | grep -v grep
        echo
        echo "🔌 监听端口："
        lsof -i -P -n | grep sing-box
        echo
        echo "📜 最近日志："
        if [ -f "${LOG_DIR}/sing-box.log" ]; then
            tail -n 10 "${LOG_DIR}/sing-box.log"
        else
            echo "⚠️ 日志文件不存在"
        fi
    else
        echo "❌ 服务未运行"
    fi
    
    # 检查配置文件
    if [ -f "${CONFIG_PATH}" ]; then
        echo
        echo "📄 配置文件存在"
        echo "路径：${CONFIG_PATH}"
    else
        echo
        echo "⚠️ 配置文件不存在"
    fi
}