#!/bin/bash

# ┌────────────────────────────────────────────────────────────────────────────┐
# │ اسکریپت راه‌اندازی تونل WireGuard + نصب پنل X-UI برای فروش فیلترشکن     │
# │                                                                            │
# │ هدف: سرور ایران → تونل → سرور خارج → اینترنت آزاد                       │
# │ کاربران به IP ایران وصل می‌شن، اما ترافیک از خارج می‌ره                 │
# │                                                                            │
# │ اجرا: bash <(curl -Ls https://raw.githubusercontent.com/USERNAME/REPO/main/tunnel-xui-setup.sh) │
# └────────────────────────────────────────────────────────────────────────────┘

set -e  # اگر خطایی رخ داد اسکریپت متوقف بشه

# فقط root می‌تونه اجرا کنه
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ این اسکریپت باید با دسترسی root اجرا بشه. از sudo استفاده کن."
    exit 1
fi

# چک کردن سیستم عامل
if ! grep -q "Ubuntu" /etc/os-release; then
    echo "❌ این اسکریپت فقط روی Ubuntu کار می‌کنه."
    exit 1
fi

echo "╔════════════════════════════════════════════════════╗"
echo "║      خوش آمدید! اسکریپت تونل + X-UI              ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# فقط بروزرسانی لیست پکیج‌ها (بدون ارتقای کل سیستم - سریع‌تره)
echo "📦 تازه کردن لیست پکیج‌ها (update) - بدون ارتقای کامل سیستم..."
apt update -y

# نصب WireGuard اگر نباشه
if ! command -v wg &> /dev/null; then
    echo "📡 نصب WireGuard (پروتکل تونل سریع و امن)..."
    apt install wireguard -y
else
    echo "✅ WireGuard قبلاً نصب بوده، رد می‌شیم."
fi

# تولید کلیدها
echo "🔑 تولید کلیدهای خصوصی و عمومی WireGuard..."
private_key=$(wg genkey)
public_key=$(echo "$private_key" | wg pubkey)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "کلید عمومی این سرور: $public_key"
echo "این کلید رو کپی کن و توی سرور مقابل (ایران یا خارج) وارد کن."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# پرسیدن نوع سرور
echo "روی کدوم سرور هستی؟"
echo "1 = سرور ایران (جایی که پنل X-UI نصب می‌شه و کاربران بهش وصل می‌شن)"
echo "2 = سرور خارج (جایی که ترافیک به اینترنت آزاد می‌ره)"
echo ""
read -p "انتخاب (1 یا 2): " server_type

if [[ "$server_type" != "1" && "$server_type" != "2" ]]; then
    echo "❌ انتخاب اشتباه. فقط 1 یا 2 بزن."
    exit 1
fi

# متغیرهای مشترک
WG_INTERFACE="wg0"
WG_PORT=51820           # می‌تونی عوض کنی اگر خواستی
WG_IP_IRAN="10.66.66.2/32"
WG_IP_OUTSIDE="10.66.66.1/32"

if [[ "$server_type" == "1" ]]; then
    # ┌─────────────────────────────┐
    # │         سرور ایران          │
    # └─────────────────────────────┘
    echo ""
    echo "🌍 شما روی سرور ایران هستید (Client)"
    echo "این سرور به سرور خارج وصل می‌شه."

    read -p "IP عمومی سرور خارج را وارد کن: " peer_endpoint_ip
    read -p "پورت WireGuard سرور خارج (پیش‌فرض 51820): " peer_port
    peer_port=${peer_port:-51820}
    read -p "کلید عمومی سرور خارج را وارد کن: " peer_public_key

    echo "در حال ساخت کانفیگ WireGuard..."
    cat > /etc/wireguard/$WG_INTERFACE.conf << EOF
[Interface]
PrivateKey = $private_key
Address = $WG_IP_IRAN
# DNS = 1.1.1.1, 8.8.8.8   # می‌تونی DNS دلخواه بذاری

[Peer]
PublicKey = $peer_public_key
Endpoint = $peer_endpoint_ip:$peer_port
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    echo "فعال‌سازی تونل..."
    wg-quick up $WG_INTERFACE
    systemctl enable wg-quick@$WG_INTERFACE

    # فعال کردن IP Forwarding
    echo "فعال کردن IP Forwarding..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    # نصب X-UI
    echo ""
    echo "🚀 در حال نصب پنل X-UI روی سرور ایران..."
    echo "بعد از نصب → http://IP-سرور:54321   (admin / admin - حتما عوض کن)"
    bash <(curl -Ls https://raw.githubusercontent.com/alireza0/x-ui/master/install.sh)

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "نکته: برای هدایت ترافیک Xray از تونل WireGuard:"
    echo "در پنل X-UI → تنظیمات Xray → outbound freedom بساز"
    echo "یا از routing استفاده کن تا ترافیک از wg0 بره"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

elif [[ "$server_type" == "2" ]]; then
    # ┌─────────────────────────────┐
    # │         سرور خارج           │
    # └─────────────────────────────┘
    echo ""
    echo "🌐 شما روی سرور خارج هستید (Server)"
    echo "این سرور منتظر اتصال از ایران است."

    read -p "IP عمومی سرور ایران را وارد کن: " peer_ip
    read -p "پورت WireGuard (پیش‌فرض 51820): " wg_port
    wg_port=${wg_port:-51820}
    read -p "کلید عمومی سرور ایران را وارد کن: " peer_public_key

    echo "در حال ساخت کانفیگ WireGuard..."
    cat > /etc/wireguard/$WG_INTERFACE.conf << EOF
[Interface]
PrivateKey = $private_key
Address = $WG_IP_OUTSIDE
ListenPort = $wg_port

[Peer]
PublicKey = $peer_public_key
AllowedIPs = $WG_IP_IRAN, 0.0.0.0/0, ::/0
EOF

    echo "فعال‌سازی تونل..."
    wg-quick up $WG_INTERFACE
    systemctl enable wg-quick@$WG_INTERFACE

    # IP Forwarding + NAT
    echo "فعال کردن IP Forwarding و NAT..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    MAIN_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
    if [ -n "$MAIN_IFACE" ]; then
        echo "رابط اصلی: $MAIN_IFACE"
        iptables -t nat -A POSTROUTING -o $MAIN_IFACE -j MASQUERADE
        apt install iptables-persistent -y -qq
        netfilter-persistent save
    else
        echo "⚠️ رابط شبکه اصلی پیدا نشد. NAT رو دستی تنظیم کن."
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "سرور خارج آماده است! پورت $wg_port/udp رو باز کن."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "🎉 تمام شد!"
echo "چک وضعیت تونل: wg show"
echo "لاگ: journalctl -u wg-quick@wg0 -f"
echo "اگر بعداً خواستی سیستم رو کامل آپدیت کنی: apt upgrade -y"
echo "موفق باشی!"
