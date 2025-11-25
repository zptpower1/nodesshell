#!/bin/bash
# 用于开启/关闭docker自动控制iptables做端口映射
# docker安装完成后默认是开启状态
set -euo pipefail

CMD=${1:-status}
OVR_DIR="/etc/systemd/system/docker.service.d"
OVR_FILE="$OVR_DIR/override.conf"

case "$CMD" in
  disable|off)
    sudo mkdir -p "$OVR_DIR"
    sudo tee "$OVR_FILE" >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --iptables=false
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo "Docker 已关闭自管理防火墙，UFW/cnwall 可控制端口"
    ;;
  enable|on)
    if [[ -f "$OVR_FILE" ]]; then
      sudo rm -f "$OVR_FILE"
    fi
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo "Docker 已启用自管理防火墙"
    ;;
  status)
    if systemctl cat docker | grep -q -- '--iptables=false'; then
      echo "状态: disabled (通过 override)"
    else
      echo "状态: enabled"
    fi
    ;;
  *)
    echo "用法: sudo ./docker-wallset.sh [enable|disable|status]"
    exit 1
    ;;
esac