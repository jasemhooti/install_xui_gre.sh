#!/bin/bash

# ┌────────────────────────────────────────────────────────────────────────────┐
# │ اسکریپت راه‌اندازی تونل WireGuard + نصب پنل X-UI                        │
# │ نسخه بهبودیافته: جلوگیری از قطع شدن SSH موقع wg-quick up               │
# │ هدف: سرور ایران ↔ تونل ↔ سرور خارج → اینترنت آزاد                      │
# └────────────────────────────────────────────────────────────────────────────┘

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ باید با root اجرا بشه (sudo bash ...)"
    exit 1
fi

if ! grep -q "Ubuntu" /etc/os-release; then
    echo "❌ فقط روی Ubuntu کار می‌کند"
    exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     اسکریپت تونل WireGuard + X-UI (جلوگیری از قطع SSH)   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# تازه کردن لیست پکیج‌ها (بدون upgrade کامل)
echo "📦 تازه کردن لیست پکیج‌ها..."
apt update -y

# نصب WireGuard اگر نباشه
if ! command -v wg &> /dev/null; then
    echo "📡 نصب WireGuard..."
    apt install wireguard -y
else
    echo "✅ WireGuard قبلاً نصب است"
fi

# تولید کلیدها
echo "🔑 تولید کلیدهای این سرور..."
private_key=$(wg genkey)
public_key=$(echo "$private_key" | wg pubkey)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "کلیدهای این سرور:"
echo ""
echo "کلید خصوصی (Private Key):   $private_key"
echo "کلید عمومی (Public Key):    $public_key"
echo ""
echo "⚠️ همین الان کلید عمومی بالا رو کپی کن"
echo "   برو سرور مقابل و وقتی پرسید کلید عمومی سرور مقابل رو وارد کن"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# پرسیدن نوع سرور
echo "این سرور کدومه؟"
echo "1 = سرور ایران     (پنل X-UI اینجا نصب می‌شه)"
echo "2 = سرور خارج      (ترافیک به اینترنت آزاد می‌ره)"
echo ""
read -p "انتخاب (1 یا 2): " server_type

if [[ "$server_type" != "1" && "$server_type" != "2" ]]; then
    echo "❌ فقط 1 یا 2 وارد کن"
    exit 1
fi

# متغیرهای ثابت
WG_INTERFACE="wg0"
WG_PORT=51820
WG_IP_IRAN="10.66.66.2/32"
WG_IP_OUTSIDE="10.66.66.1/32"

# قوانین برای جلوگیری از قطع SSH (پورت 22 رو از تونل مستثنی می‌کنیم)
ANTI_LOCKOUT_POSTUP="ip rule add sport 22 lookup main priority 100; ip route flush cache"
ANTI_LOCKOUT_POSTDOWN="ip rule del sport 22 lookup main priority 100; ip route flush cache"

echo ""
echo "حالا اطلاعات سرور مقابل رو وارد کن"
echo ""

if [[ "$server_type" == "1" ]]; then
    # سرور ایران (Client)
    read -p "IP عمومی سرور خارج: " peer_endpoint_ip
    read -p "پورت WireGuard سرور خارج (پیش‌فرض 51820): " peer_port
    peer_port=${peer_port:-51820}
    read -p "کلید عمومی سرور خارج: " peer_public_key

    echo "در حال ساخت کانفیگ client..."
    cat > /etc/wireguard/$WG_INTERFACE.conf << EOF
[Interface]
PrivateKey = $private_key
Address = $WG_IP_IRAN

PostUp = $ANTI_LOCKOUT_POSTUP
PostDown = $ANTI_LOCKOUT_POSTDOWN

[Peer]
PublicKey = $peer_public_key
Endpoint = $peer_endpoint_ip:$peer_port
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    echo "راه‌اندازی تونل..."
    wg-quick up $WG_INTERFACE || { echo "خطا در بالا آوردن تونل! اگر SSH قطع شد از کنسول وب سرور استفاده کن و wg-quick down wg0 بزن."; exit 1; }
    systemctl enable wg-quick@$WG_INTERFACE

    # IP Forwarding
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    # نصب X-UI
    echo ""
    echo "🚀 نصب پنل X-UI شروع شد..."
    echo "بعد نصب → http://$(curl -s ifconfig.me):54321    (admin/admin - حتما عوض کن)"
    bash <(curl -Ls https://raw.githubusercontent.com/alireza0/x-ui/master/install.sh)

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "برای هدایت ترافیک Xray از تونل:"
    echo "در پنل X-UI → تنظیمات Xray → outbound freedom بساز"
    echo "یا routing rule بزن که ترافیک از wg0 بره"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

elif [[ "$server_type" == "2" ]]; then
    # سرور خارج (Server)
    read -p "IP عمومی سرور ایران: " peer_ip
    read -p "پورت WireGuard (پیش‌فرض 51820): " wg_port
    wg_port=${wg_port:-51820}
    read -p "کلید عمومی سرور ایران: " peer_public_key

    echo "در حال ساخت کانفیگ server..."
    cat > /etc/wireguard/$WG_INTERFACE.conf << EOF
[Interface]
PrivateKey = $private_key
Address = $WG_IP_OUTSIDE
ListenPort = $wg_port

PostUp = $ANTI_LOCKOUT_POSTUP
PostDown = $ANTI_LOCKOUT_POSTDOWN

[Peer]
PublicKey = $peer_public_key
AllowedIPs = $WG_IP_IRAN, 0.0.0.0/0, ::/0
EOF

    echo "راه‌اندازی تونل..."
    wg-quick up $WG_INTERFACE || { echo "خطا! اگر SSH قطع شد wg-quick down wg0 بزن."; exit 1; }
    systemctl enable wg-quick@$WG_INTERFACE

    # IP Forwarding + NAT
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    MAIN_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
    if [ -n "$MAIN_IFACE" ]; then
        echo "رابط اصلی اینترنت: $MAIN_IFACE"
        iptables -t nat -A POSTROUTING -o "$MAIN_IFACE" -j MASQUERADE
        apt install -y iptables-persistent
        netfilter-persistent save
    else
        echo "⚠️ رابط اصلی پیدا نشد → NAT رو دستی تنظیم کن"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "سرور خارج آماده است"
    echo "پورت $wg_port udp رو توی فایروال باز کن"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "🎉 تمام شد!"
echo "وضعیت تونل:   wg show"
echo "لاگ‌ها:       journalctl -u wg-quick@wg0 -f"
echo ""
echo "اگر باز SSH قطع شد:"
echo "1. از کنسول وب سرور وارد شو"
echo "2. wg-quick down wg0 بزن"
echo "3. اگر IP ثابت داری، بگو تا PostUp رو با from YOUR_IP عوض کنیم"
echo "موفق باشی!"
