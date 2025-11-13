#!/bin/bash
echo "正在关闭 cnwall..."
nft delete table inet cnwall 2>/dev/null || echo "cnwall 已关闭"
echo "cnwall 已关闭，UFW 恢复控制"