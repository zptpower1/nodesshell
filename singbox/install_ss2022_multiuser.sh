#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# 加载所有模块
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/install.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/service.sh"

# 主安装流程
main() {
    check_root
    check_dependencies
    install_sing_box
    create_config
    setup_service
    check_service
    generate_client_configs
}

main "$@"