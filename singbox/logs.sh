#!/bin/bash

# 加载工具库
source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"

# 查看日志文件
if [ -f "${LOG_PATH}" ]; then
    echo "📜 查看日志文件：${LOG_PATH}"
    tail -50f "${LOG_PATH}"
else
    echo "⚠️ 日志文件不存在：${LOG_PATH}"
fi