#!/bin/bash
#
# china-firewall.sh
# 目标：
#   - 22/443/8080 仅允许中国 IP
#   - 其他端口全部拒绝
#   - ipset 原子更新
#   - iptables 规则顺序正确，不会短路
#   - 不会把自己锁在外面
#

SET_NAME="china"
TMP_SET="${SET_NAME}_tmp"
CHINA_IP_URL="https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
TMP_FILE="/tmp/china_ip_list.txt"

echo "[1/4] 下载中国 IP 列表..."
curl -s "$CHINA_IP_URL" -o "$TMP_FILE"
if [ $? -ne 0 ]; then
    echo "下载失败，退出"
    exit 1
fi

echo "[2/4] 创建临时 ipset 集合..."
ipset create $TMP_SET hash:net maxelem 200000 2>/dev/null

echo "[2.1] 导入 IP 段到临时集合..."
while read ip; do
    ipset add $TMP_SET $ip
done < "$TMP_FILE"

echo "[2.2] 创建正式集合（如不存在）..."
ipset create $SET_NAME hash:net maxelem 200000 2>/dev/null

echo "[2.3] 原子替换集合..."
ipset swap $TMP_SET $SET_NAME
ipset destroy $TMP_SET

echo "[3/4] 配置 iptables 规则..."

# 清空 INPUT 链
iptables -F INPUT

# 1. 已建立连接
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# 2. 本地回环
iptables -A INPUT -i lo -j ACCEPT

# 3. ICMP
iptables -A INPUT -p icmp -j ACCEPT

# 4. SSH 仅允许中国 IP
iptables -A INPUT -p tcp --dport 22 -m set --match-set china src -j ACCEPT

# 5. HTTPS 仅允许中国 IP
iptables -A INPUT -p tcp --dport 443 -m set --match-set china src -j ACCEPT
iptables -A INPUT -p udp --dport 443 -m set --match-set china src -j ACCEPT
iptables -A INPUT -p tcp --dport 8080 -m set --match-set china src -j ACCEPT

# 6. DNS 返回包
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT

# 7. 其他全部拒绝
iptables -A INPUT -j DROP

echo "[4/4] 完成！当前规则如下："
iptables -L INPUT -n --line-numbers
