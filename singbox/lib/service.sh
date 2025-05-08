#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 生成服务配置文件内容
generate_service_config() {
    # 获取当前用户名
    local current_user=$(whoami)
    
    cat << EOF
[Unit]
Description=Sing-box Proxy Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=${SING_BIN} run -c ${CONFIG_PATH}
Restart=on-failure
RestartPreventExitStatus=23
User=${current_user}

[Install]
WantedBy=multi-user.target
EOF
}

# 创建systemctl服务
service_install() {
    # 生成服务配置并写入文件
    generate_service_config > "${SERVICE_FILE}"
    
    service_enable
    reload_service
}

# 检查服务状态
service_check() {
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

# 禁用服务
service_disable() {
    echo "🔒 禁用服务..."
    if pgrep -x "sing-box" > /dev/null; then
        service_stop
    fi
    
    if [ -f "${SERVICE_FILE}" ]; then
        systemctl disable ${SERVICE_NAME}
        echo "✅ 服务已禁用"
    else
        echo "⚠️ 服务配置不存在"
    fi
}

# 查看服务状态详情
service_status() {
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

service_enable() {
    echo "🔓 启用服务..."
    if [ -f "${SERVICE_FILE}" ]; then
        systemctl enable ${SERVICE_NAME}
        echo "✅ 服务已启用"
    else
        echo "⚠️ 服务配置不存在"
    fi
}

# 启动服务
service_start() {
    echo "🚀 启动服务..."
    config_check
    if [ -f "${SERVICE_FILE}" ]; then
        systemctl start ${SERVICE_NAME}
        echo "✅ 服务已启动"
        service_check
    else
        echo "⚠️ 服务配置不存在"
    fi
}

# 停止服务
service_stop() {
    echo "🛑 停止服务..."
    systemctl stop ${SERVICE_NAME}
}

# 重启服务
service_restart() {
    echo "🔄 重启服务..."
    service_stop
    service_start
}

# 卸载服务
service_remove() {
    echo "🗑️ 卸载服务..."
    
    if [ -f "${SERVICE_FILE}" ]; then
        service_disable
        rm -f "${SERVICE_FILE}"
        systemctl daemon-reload
        echo "✅ 服务已卸载"
    else
        echo "⚠️ 服务配置不存在"
    fi
}