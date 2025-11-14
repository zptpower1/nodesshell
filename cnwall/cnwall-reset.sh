#!/bin/bash
echo "正在清空 nftables 所有规则..."
sudo nft flush ruleset
echo "nftables 已完全重置"