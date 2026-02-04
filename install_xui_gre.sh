#!/bin/bash
set -e
echo "============================================="
echo "     x-ui + GRE Tunnel Installer (Auto)     "
echo "============================================="

# 1️⃣ گرفتن اطلاعات از کاربر
read -p "IP سرور ایران 🇮🇷 : " IP_IRAN
read -p "IP سرور خارج 🌍 : " IP_KHAREJ
read -p "پورت اول x-ui (مثلاً 57837): " PORT1
read -p "پورت دوم x-ui (مثلاً 12305): " PORT2

# 2️⃣ نصب پیش‌نیازها
echo "در حال نصب پیش‌نیازها..."
apt update -y && apt upgrade -y
apt install -y iptables iproute2 curl ssh tcpdump

# 3️⃣ حذف تونل‌های قبلی اگر موجود باشند
ip tunnel del greIR 2>/dev/null || true

# 4️⃣ ساخت تونل GRE روی ایران
echo "در حال ایجاد تونل GRE روی ایران..."
ip tunnel add greIR mode gre remote $IP_KHAREJ local $IP_IRAN ttl 255
ip addr add 10.10.10.1/30 dev greIR
ip link set greIR mtu 1476
ip link set greIR up

# فعال کردن IP Forwarding
sysctl -w net.ipv4.ip_forward=1

# 5️⃣ تنظیم DNAT و Policy Routing روی ایران
echo "ست کردن DNAT و Policy Routing روی ایران..."
iptables -t nat -F PREROUTING
iptables -t nat -A PREROUTING -p tcp --dport $PORT1 -j DNAT --to-destination 10.10.10.2:$PORT1
iptables -t nat -A PREROUTING -p tcp --dport $PORT2 -j DNAT --to-destination 10.10.10.2:$PORT2

iptables -t mangle -F PREROUTING
iptables -t mangle -A PREROUTING -p tcp --dport $PORT1 -j MARK --set-mark 10
iptables -t mangle -A PREROUTING -p tcp --dport $PORT2 -j MARK --set-mark 10

ip rule add fwmark 10 table gre
ip route add default via 10.10.10.2 dev greIR table gre

# 6️⃣ نصب x-ui روی سرور خارج
echo "در حال نصب x-ui روی سرور خارج..."
ssh root@$IP_KHAREJ bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# 7️⃣ تنظیم MASQUERADE روی سرور خارج
ssh root@$IP_KHAREJ "iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE"

# 8️⃣ پایان
echo "---------------------------------------------"
echo "✅ نصب و کانفیگ GRE + x-ui انجام شد!"
echo "IP سرور ایران 🇮🇷: $IP_IRAN"
echo "IP سرور خارج 🌍: $IP_KHAREJ"
echo "Ports: $PORT1 و $PORT2"
echo "✅ حالا می‌توانید از کلاینت V2Ray یا مشابه استفاده کنید"
echo "---------------------------------------------"
