#!/bin/bash

echo "=== TCP Retransmission Analyzer ==="
echo

# 捕获输出
data=$(netstat -s | grep -i -E 'retrans|TCPLost|SynRetrans')

# 解析指标
segments_retransmitted=$(echo "$data" | grep -i "segments retransmitted" | awk '{print $1}')
fast_retrans=$(echo "$data" | grep -i "fast retransmits" | awk '{print $1}')
slowstart_retrans=$(echo "$data" | grep -i "retransmits in slow start" | awk '{print $1}')
syn_retrans=$(echo "$data" | grep -i "TCPSynRetrans" | awk '{print $2}')
lost_retrans=$(echo "$data" | grep -i "TCPLostRetransmit" | awk '{print $2}')
reordering=$(echo "$data" | grep -i "reordering" | awk '{print $3}')

# 函数：健康判断
function assess_level() {
  local value=$1
  local warn=$2
  local critical=$3

  if (( value > critical )); then
    echo "严重 🔥"
  elif (( value > warn )); then
    echo "警告 ⚠️"
  else
    echo "正常 ✅"
  fi
}

# 输出分析结果
echo "1. Segments retransmitted: $segments_retransmitted ($(assess_level $segments_retransmitted 10000 100000))"
echo "2. Fast retransmits: $fast_retrans ($(assess_level $fast_retrans 5000 50000))"
echo "3. Slow start retransmits: $slowstart_retrans ($(assess_level $slowstart_retrans 100 1000))"
echo "4. SYN retransmissions: $syn_retrans ($(assess_level $syn_retrans 1000 10000))"
echo "5. Lost retransmits: $lost_retrans ($(assess_level $lost_retrans 5000 50000))"
echo "6. Detected reordering: ${reordering:-0} ($(assess_level ${reordering:-0} 100 1000))"

echo
echo "=== 建议 ==="
if (( syn_retrans > 10000 )); then
  echo "- 检查是否有 SYN Flood 攻击 (如 SYN_RECV 数量异常)"
fi

if (( lost_retrans > 50000 || segments_retransmitted > 100000 )); then
  echo "- 检查服务器与客户端间的链路质量，可能存在严重丢包"
  echo "- 可用 'mtr' 或 'ping' 检查网络延迟和丢包"
fi

if (( fast_retrans > 50000 )); then
  echo "- TCP 快速重传频繁，可能存在轻微至中度网络不稳定"
fi

if (( reordering > 100 )); then
  echo "- 网络可能存在路由器跳数不稳定或带宽瓶颈问题"
fi

echo "- 如果服务器暴露公网，建议部署防火墙和限速策略。"
echo "- 使用 'iperf3' 可进一步测试网络吞吐能力。"
