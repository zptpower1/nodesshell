#!/bin/bash
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 安装Python依赖库
pip3 install -r "${SCRIPT_DIR}/lib/requirements.txt"

# 运行Python脚本
python3 "${SCRIPT_DIR}/lib/ss2022.py" "$@"