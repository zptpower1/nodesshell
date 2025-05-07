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