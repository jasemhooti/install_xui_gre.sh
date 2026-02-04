#!/bin/bash

echo "======================================"
echo " اسکریپت راه‌اندازی تونل GRE + x-ui "
echo "======================================"
echo

read -p "این سرور ایران است یا خارج؟ (iran/kharej): " ROLE
read -p "IP سرور مقابل را وارد کن: " REMOTE_IP
read -p "IP عمومی همین سرور را وارد کن: " LOCAL_IP

read -p "IP تونل این سرور (مثلاً 10.10.10.1 یا 10.10.10.2): " TUN_LOCAL
read -p "IP تونل سرور مقابل: " TUN_REMOTE

read -p "نام اینترفیس تونل (مثلاً greIR یا greKH): " GRE_NAME

read -p "پورت اول x-ui: " PORT1
read -p "پورت دوم x-ui: " PORT2

echo
echo "▶ فعال‌سازی IP Forward..."
sysctl -w net.ipv4.ip_forward=1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
echo "✔ IP Forward فعال شد"

echo
echo "▶ ساخت تونل GRE..."
ip tunnel add $GRE_NAME mode gre remote $REMOTE_IP local $LOCAL_IP ttl 255
ip addr add $TUN_LOCAL/30 dev $GRE_NAME
ip link set $GRE_NAME mtu 1476
ip link set $GRE_NAME up
echo "✔ تونل GRE ساخته شد"

echo
echo "▶ تنظیم NAT..."
iptables -t nat -A POSTROUTING -o $(ip route get 1.1.1.1 | awk '{print $5; exit}') -j MASQUERADE
echo "✔ NAT تنظیم شد"

if [ "$ROLE" = "iran" ]; then
  echo
  echo "▶ این سرور ایران است — تنظیم DNAT برای پورت‌ها..."
  iptables -t nat -A PREROUTING -p tcp --dport $PORT1 -j DNAT --to-destination $TUN_REMOTE:$PORT1
  iptables -t nat -A PREROUTING -p tcp --dport $PORT2 -j DNAT --to-destination $TUN_REMOTE:$PORT2
  echo "✔ DNAT برای پورت‌ها انجام شد"
fi

echo
echo "▶ ذخیره قوانین فایروال..."
apt install -y iptables-persistent
netfilter-persistent save

echo
echo "======================================"
echo " ✅ تنظیمات با موفقیت انجام شد "
echo "======================================"

echo
echo "📌 تست:"
echo "ping $TUN_REMOTE"
echo

if [ "$ROLE" = "kharej" ]; then
  echo "📌 حالا x-ui را روی این سرور نصب کن"
  echo "bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)"
fi
