#!/bin/bash
set -e

clear
echo "=============================================="
echo "  اسکریپت خودکار تونل GRE برای x-ui"
echo "  اجرا روی هر دو سرور با یک لینک"
echo "=============================================="
echo
echo "این اسکریپت فقط روی همین سرور کار می‌کند."
echo "هیچ SSH به سرور مقابل انجام نمی‌شود."
echo

echo "این سرور کدام است؟"
echo "1) سرور ایران 🇮🇷"
echo "2) سرور خارج 🌍"
read -p "عدد را وارد کن (1 یا 2): " SERVER_TYPE

if [[ "$SERVER_TYPE" != "1" && "$SERVER_TYPE" != "2" ]]; then
  echo "❌ ورودی اشتباه است. فقط 1 یا 2 مجاز است."
  exit 1
fi

echo
read -p "IP عمومی همین سرور: " LOCAL_IP
read -p "IP عمومی سرور مقابل: " REMOTE_IP

echo
read -p "IP تونل این سرور (مثلاً 10.10.10.1 یا 10.10.10.2): " TUN_LOCAL
read -p "IP تونل سرور مقابل: " TUN_REMOTE

echo
read -p "نام اینترفیس تونل (مثلاً greIR یا greKH): " GRE_NAME

echo
read -p "پورت اول x-ui: " PORT1
read -p "پورت دوم x-ui: " PORT2

echo
echo "=============================================="
echo "خلاصه تنظیمات:"
echo "LOCAL_IP      = $LOCAL_IP"
echo "REMOTE_IP     = $REMOTE_IP"
echo "TUN_LOCAL     = $TUN_LOCAL"
echo "TUN_REMOTE    = $TUN_REMOTE"
echo "GRE_NAME      = $GRE_NAME"
echo "PORT1         = $PORT1"
echo "PORT2         = $PORT2"
if [ "$SERVER_TYPE" = "1" ]; then
  echo "نقش سرور     = ایران (DNAT فعال می‌شود)"
else
  echo "نقش سرور     = خارج (x-ui روی این نصب می‌شود)"
fi
echo "=============================================="
read -p "ادامه بدهم؟ (yes): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "لغو شد."
  exit 0
fi

echo
echo "▶ فعال‌سازی IP Forward..."
sysctl -w net.ipv4.ip_forward=1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
echo "✔ IP Forward فعال شد"

echo
echo "▶ حذف تونل قدیمی (اگر وجود داشته باشد)..."
ip tunnel del $GRE_NAME 2>/dev/null || true

echo
echo "▶ ساخت تونل GRE..."
ip tunnel add $GRE_NAME mode gre remote $REMOTE_IP local $LOCAL_IP ttl 255
ip addr add $TUN_LOCAL/30 dev $GRE_NAME
ip link set $GRE_NAME mtu 1476
ip link set $GRE_NAME up
echo "✔ تونل GRE ساخته شد"

echo
echo "▶ تنظیم NAT خروجی..."
OUT_IF=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
iptables -t nat -C POSTROUTING -o $OUT_IF -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o $OUT_IF -j MASQUERADE
echo "✔ NAT تنظیم شد روی اینترفیس $OUT_IF"

if [ "$SERVER_TYPE" = "1" ]; then
  echo
  echo "▶ این سرور ایران است — تنظیم DNAT برای پورت‌ها..."

  iptables -t nat -A PREROUTING -p tcp --dport $PORT1 -j DNAT --to-destination $TUN_REMOTE:$PORT1
  iptables -t nat -A PREROUTING -p tcp --dport $PORT2 -j DNAT --to-destination $TUN_REMOTE:$PORT2

  echo "✔ DNAT برای پورت‌ها انجام شد"
  echo "✔ هر اتصال روی IP ایران به این پورت‌ها به خارج تونل می‌شود"
fi

echo
echo "▶ نصب و ذخیره قوانین فایروال..."
apt update -y
apt install -y iptables-persistent
netfilter-persistent save

echo
echo "=============================================="
echo " ✅ تونل GRE با موفقیت راه‌اندازی شد"
echo "=============================================="
echo
echo "📌 تست ضروری:"
echo "ping $TUN_REMOTE"
echo

if [ "$SERVER_TYPE" = "2" ]; then
  echo "📌 این سرور خارج است."
  echo "الان x-ui را روی همین سرور نصب کن:"
  echo
  echo "bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)"
fi

echo
echo "اگر ping جواب داد ولی کانفیگ وصل نشد، مشکل 100٪ از x-ui یا inbound است، نه تونل."
