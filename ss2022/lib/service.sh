#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 设置服务
setup_service() {
    mkdir -p "${LOG_DIR}"
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Shadowsocks-rust Server Service
After=network.target

[Service]
Type=simple
ExecStart=${SS_BIN} -c ${CONFIG_PATH} -v > ${LOG_DIR}/ss-server.log 2>&1
Restart=on-failure
RestartSec=5
StandardOutput=append:${LOG_DIR}/ss-server.log
StandardError=append:${LOG_DIR}/ss-server.log

[Install]
WantedBy=multi-user.target
EOF

    # 设置日志目录权限
    chmod 755 "${LOG_DIR}"
    
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"
    echo "✅ 服务设置完成"
}

# 启动服务
start_service() {
    check_root
    echo "🚀 启动服务..."
    systemctl start ${SERVICE_NAME}
    echo "✅ 服务已启动"
}

# 停止服务
stop_service() {
    check_root
    echo "🛑 停止服务..."
    systemctl stop ${SERVICE_NAME}
    echo "✅ 服务已停止"
}

# 重启服务
restart_service() {
    check_root
    echo "🔄 重启服务..."
    systemctl restart ${SERVICE_NAME}
    echo "✅ 服务已重启"
}

# 查看状态
status_service() {
    check_root
    echo "📊 服务状态："
    systemctl status ${SERVICE_NAME}
}

# 查看日志
show_logs() {
    check_root
    echo "📜 服务日志："
    journalctl -u ${SERVICE_NAME} -n 100 --no-pager
}