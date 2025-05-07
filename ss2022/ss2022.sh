#!/bin/bash
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 安装Python依赖
pip3 install -r "${SCRIPT_DIR}/lib/requirements.txt"

# 运行Python脚本
# 将 SCRIPT_DIR 作为 --script-dir 参数传递给 Python 脚本
python3 "${SCRIPT_DIR}/lib/ss2022.py" --script-dir "${SCRIPT_DIR}" "$@"