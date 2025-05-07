#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 创建服务
setup_service() {
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Sing-box Proxy Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=${SING_BIN} run -c ${CONFIG_PATH}
Restart=on-failure
RestartPreventExitStatus=23
User=nobody

[Install]
WantedBy=multi-user.target
EOF

    enable_service
    reload_service
}

# 检查服务状态
check_service() {
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        # 显示 systemctl 的状态信息
        systemctl status ${SERVICE_NAME}
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
        if [ -f "${LOG_PATH}" ]; then
            tail -n 10 "${LOG_PATH}"
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

reload_service() {
    echo "🔄 重载服务..."
    if [ -f "${SERVICE_FILE}" ]; then
        systemctl daemon-reload
        systemctl restart ${SERVICE_NAME}
        echo "✅ 服务已重载"
    else
        echo "⚠️ 服务配置不存在"
    fi
}

enable_service() {
    echo "🔓 启用服务..."
    if [ -f "${SERVICE_FILE}" ]; then
        systemctl enable ${SERVICE_NAME}
        echo "✅ 服务已启用"
    else
        echo "⚠️ 服务配置不存在"
    fi
}

# 启动服务
start_service() {
    echo "🚀 启动服务..."
    check_config
    if [ -f "${SERVICE_FILE}" ]; then
        systemctl start ${SERVICE_NAME}
        echo "✅ 服务已启动"
        check_service
    else
        echo "⚠️ 服务配置不存在"
    fi
    # if systemctl list-units --type=service | grep -q "${SERVICE_NAME}"; then
    #     systemctl start ${SERVICE_NAME}
    #     echo "✅ 服务已通过 systemctl 启动"
    # else
    #     if ! pgrep -x "sing-box" > /dev/null; then
    #         nohup ${SING_BIN} run -c ${CONFIG_PATH} &
    #         echo "✅ 服务已通过 nohup 启动"
    #     else
    #         echo "⚠️ 服务已在运行"
    #     fi
    # fi
}

# 停止服务
stop_service() {
    echo "🛑 停止服务..."
    systemctl stop ${SERVICE_NAME}
    # if systemctl list-units --type=service | grep -q "${SERVICE_NAME}"; then
    #     systemctl stop ${SERVICE_NAME}
    #     echo "✅ 服务已通过 systemctl 停止"
    # else
    #     if pgrep -x "sing-box" > /dev/null; then
    #         kill $(pgrep -x "sing-box")
    #         echo "✅ 服务已通过 kill 停止"
    #     else
    #         echo "⚠️ 服务未运行"
    #     fi
    # fi
}

# 禁用服务
disable_service() {
    echo "🔒 禁用服务..."
    if systemctl list-units --type=service | grep -q "${SERVICE_NAME}"; then
        systemctl disable ${SERVICE_NAME}
        echo "✅ 服务已通过 systemctl 禁用"
    else
        if pgrep -x "sing-box" > /dev/null; then
            stop_service
        fi
        
        if [ -f "${SERVICE_FILE}" ]; then
            rm -f "${SERVICE_FILE}"
            echo "✅ 服务已禁用"
        else
            echo "⚠️ 服务配置不存在"
        fi
    fi
}

# 重启服务
restart_service() {
    echo "🔄 重启服务..."
    stop_service
    start_service
}