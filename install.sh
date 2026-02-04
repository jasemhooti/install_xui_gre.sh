#!/bin/bash

# اسکریپت تونل WireGuard + X-UI (فقط پیش‌نیازهای ضروری)
# نسخه 1.4 - بدون هیچ dialog needrestart یا کرنل

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# چک اوبونتو
if ! grep -q "Ubuntu" /etc/os-release; then
    echo -e "${RED}فقط روی Ubuntu کار می‌کنه.${NC}"
    exit 1
fi

# ساکت کردن دائمی needrestart (بدون popup)
echo -e "${YELLOW}ساکت کردن needrestart برای همیشه...${NC}"
sudo sed -i 's/#\$nrconf{restart} = '"'"'i'"'"';/\$nrconf{restart} = '"'"'l'"'"';/' /etc/needrestart/needrestart.conf || true
# اگر خط وجود نداشت، اضافه کن
if ! grep -q "\$nrconf{restart} = 'l';" /etc/needrestart/needrestart.conf; then
    echo "\$nrconf{restart} = 'l';" | sudo tee -a /etc/needrestart/needrestart.conf
fi

# بروزرسانی + نصب فقط پیش‌نیازهای ضروری برای WireGuard + مدیریت
echo -e "${YELLOW}بروزرسانی و نصب فقط پیش‌نیازهای تونل...${NC}"
export DEBIAN_FRONTEND=noninteractive
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y wireguard wireguard-tools resolvconf jq ufw curl wget

# گزینه ریست سرور (اختیاری)
echo ""
echo -e "${GREEN}تونل WireGuard ایران ↔ خارج${NC}"
echo -e "${YELLOW}سرور رو ریست کنیم؟ (حذف تونل قدیمی + WireGuard + X-UI)${NC}"
read -p "(y/n): " reset_server

if [[ $reset_server == "y" || $reset_server == "Y" ]]; then
    echo -e "${YELLOW}ریست سرور...${NC}"
    wg-quick down wg0 &>/dev/null || true
    systemctl disable --now wg-quick@wg0 &>/dev/null || true
    rm -rf /etc/wireguard/*
    sudo apt purge wireguard wireguard-tools -y &>/dev/null || true
    sudo apt autoremove -y &>/dev/null || true
    
    if command -v x-ui >/dev/null; then
        x-ui uninstall || true
        rm -rf /usr/local/x-ui/
    fi
    
    sudo ufw --force reset || true
    sudo ufw allow 22/tcp || true
    sudo ufw allow 51820/udp || true
    sudo ufw --force enable || true
    sudo ufw reload || true
    echo -e "${GREEN}ریست تمام شد.${NC}"
fi

# نصب 3X-UI فقط اگر نبود
if ! command -v x-ui >/dev/null; then
    echo -e "${YELLOW}نصب 3X-UI...${NC}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    x-ui default
fi

# ادامه تنظیمات تونل (همون قبلی)
echo ""
echo -e "${YELLOW}کدوم سرور؟${NC}"
echo "1) ایران (پنل اصلی)"
echo "2) خارج"
read -p "1 یا 2: " server_type

if [[ $server_type != "1" && $server_type != "2" ]]; then
    echo -e "${RED}انتخاب اشتباه.${NC}"
    exit 1
fi

mkdir -p /etc/wireguard
private_key_file="/etc/wireguard/private.key"
public_key_file="/etc/wireguard/public.key"

if [ ! -f "$private_key_file" ]; then
    echo -e "${YELLOW}ساخت کلید...${NC}"
    wg genkey | tee "$private_key_file" | wg pubkey > "$public_key_file"
    chmod 600 "$private_key_file"
fi

my_private_key=$(cat "$private_key_file")
my_public_key=$(cat "$public_key_file")

echo -e "${GREEN}کلید عمومی این سرور (کپی کن):${NC}"
echo "$my_public_key"

if [ "$server_type" = "1" ]; then
    echo -e "${YELLOW}سرور خارج:${NC}"
    read -p "IP خارج: " foreign_ip
    read -p "کلید عمومی خارج: " foreign_public_key
    read -p "پورت (51820 پیش‌فرض): " wg_port
    wg_port=${wg_port:-51820}
    
    read -p "دامنه؟ (y/n): " use_domain
    if [[ $use_domain == "y" || $use_domain == "Y" ]]; then
        read -p "دامنه: " foreign_domain
        endpoint="$foreign_domain:$wg_port"
    else
        endpoint="$foreign_ip:$wg_port"
    fi
    
    my_wg_ip="10.66.66.2/32"
    peer_wg_ip="10.66.66.1/32"
else
    echo -e "${YELLOW}سرور ایران:${NC}"
    read -p "IP ایران: " iran_ip
    read -p "کلید عمومی ایران: " iran_public_key
    read -p "پورت (51820 پیش‌فرض): " wg_port
    wg_port=${wg_port:-51820}
    
    my_wg_ip="10.66.66.1/32"
    peer_wg_ip="10.66.66.2/32"
    endpoint=""
fi

wg_config="/etc/wireguard/wg0.conf"

if [ "$server_type" = "1" ]; then
    cat > "$wg_config" <<EOL
[Interface]
Address = $my_wg_ip
PrivateKey = $my_private_key

[Peer]
PublicKey = $foreign_public_key
AllowedIPs = 0.0.0.0/0
Endpoint = $endpoint
PersistentKeepalive = 25
EOL
else
    cat > "$wg_config" <<EOL
[Interface]
Address = $my_wg_ip
PrivateKey = $my_private_key
ListenPort = $wg_port

[Peer]
PublicKey = $iran_public_key
AllowedIPs = $peer_wg_ip
EOL
fi

echo -e "${YELLOW}فعال کردن تونل...${NC}"
wg-quick down wg0 &>/dev/null || true
wg-quick up wg0
systemctl enable wg-quick@wg0 --now

if wg show wg0 &>/dev/null; then
    echo -e "${GREEN}تونل فعال شد!${NC}"
    wg show wg0
else
    echo -e "${RED}تونل بالا نیومد - ufw و پورت چک کن.${NC}"
    exit 1
fi

if [ "$server_type" = "1" ]; then
    echo -e "${YELLOW}تنظیم X-UI...${NC}"
    config_file="/usr/local/x-ui/bin/config.json"
    if [ -f "$config_file" ]; then
        jq '.outbounds += [{"protocol": "freedom", "settings": {"domainStrategy": "AsIs"}, "tag": "direct-to-foreign"}]' "$config_file" > temp.json && mv temp.json "$config_file"
        jq '.routing.rules += [{"type": "field", "outboundTag": "direct-to-foreign", "network": "udp,tcp"}]' "$config_file" > temp.json && mv temp.json "$config_file"
        x-ui restart
        echo -e "${GREEN}X-UI آماده است.${NC}"
    else
        echo -e "${YELLOW}کانفیگ X-UI پیدا نشد.${NC}"
    fi
fi

echo -e "${GREEN}تموم!${NC}"
echo "تست: روی ایران → ping 10.66.66.1"
echo "وضعیت: wg show wg0"
echo "فایروال: sudo ufw status"
