#!/bin/bash

# اسکریپت راه‌اندازی تونل UDP-based با WireGuard برای اتصال دو پنل X-UI
# ساخته شده توسط Grok برای جاسم - نسخه 1.1 (فوریه 2026)
# این اسکریپت روی Ubuntu 20.04+ کار می‌کنه. پیش‌نیازها رو نصب می‌کنه و تونل site-to-site می‌سازه.
# برای استفاده: curl -O https://raw.githubusercontent.com/USERNAME/REPO/main/setup-tunnel.sh && bash setup-tunnel.sh
# جایگزین USERNAME/REPO با گیت‌هاب خودت کن.
# تغییرات جدید: اضافه کردن گزینه خام کردن سرور قبل از شروع (حذف تونل‌های قدیمی، باز کردن پورت‌ها، رفع فایروال)

# رنگ‌ها برای خروجی زیبا
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# چک توزیع سیستم
if ! grep -q "Ubuntu" /etc/os-release; then
    echo -e "${RED}این اسکریپت فقط روی Ubuntu کار می‌کنه. سیستم شما سازگار نیست.${NC}"
    exit 1
fi

# بروزرسانی سیستم و نصب پیش‌نیازها
echo -e "${YELLOW}بروزرسانی سیستم و نصب پیش‌نیازها...${NC}"
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl wget wireguard resolvconf jq ufw  # اضافه کردن ufw برای فایروال

# گزینه خام کردن سرور
echo -e "${GREEN}سلام جاسم! این اسکریپت تونل WireGuard (UDP-based) رو راه‌اندازی می‌کنه.${NC}"
echo -e "${GREEN}تونل بین سرور ایران (با پنل X-UI برای ساخت کانفیگ) و سرور خارج (برای دسترسی به اینترنت آزاد) ساخته می‌شه.${NC}"
echo -e "${GREEN}ترافیک کاربران از ایران به خارج هدایت می‌شه.${NC}"
echo ""
echo -e "${YELLOW}آیا می‌خوای سرور رو خام کنی (حذف تونل‌های قدیمی WireGuard، باز کردن پورت‌های لازم مثل 51820/UDP و SSH، رفع مشکلات فایروال، و uninstall X-UI اگر نصب باشه)؟${NC}"
echo -e "${YELLOW}اگر y بزنی، سرور رو تمیز می‌کنه و آماده نصب جدید می‌شه. اگر n، مستقیم می‌ره به تنظیمات.${NC}"
read -p "(y/n): " reset_server

if [[ $reset_server == "y" || $reset_server == "Y" ]]; then
    echo -e "${YELLOW}خام کردن سرور...${NC}"
    
    # حذف تونل‌های قدیمی WireGuard
    wg-quick down wg0 &> /dev/null
    systemctl disable wg-quick@wg0 &> /dev/null
    rm -rf /etc/wireguard/*
    
    # uninstall WireGuard اگر نصب باشه
    sudo apt purge wireguard -y &> /dev/null
    sudo apt autoremove -y &> /dev/null
    
    # uninstall X-UI اگر نصب باشه
    if command -v x-ui &> /dev/null; then
        x-ui uninstall
        rm -rf /usr/local/x-ui/
    fi
    
    # تنظیم فایروال: ریست به حالت امن، اجازه پورت‌های لازم
    sudo ufw --force reset  # ریست فایروال (با احتیاط، همه رول‌ها حذف می‌شن)
    sudo ufw allow 22/tcp   # SSH برای جلوگیری از لاک اوت
    sudo ufw allow 51820/udp  # پورت پیش‌فرض WireGuard
    sudo ufw --force enable
    sudo ufw reload
    
    echo -e "${GREEN}سرور خام شد! حالا ادامه می‌دیم.${NC}"
else
    echo -e "${GREEN}خام کردن رد شد. ادامه به تنظیمات.${NC}"
fi

# نصب X-UI اگر نصب نیست (فرض می‌کنیم 3X-UI که پایدارتره)
if ! command -v x-ui &> /dev/null; then
    echo -e "${YELLOW}نصب پنل 3X-UI (fork پیشرفته X-UI)...${NC}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    # تنظیم پیش‌فرض پنل (نام کاربری و رمز admin/admin - بعداً تغییر بده)
    x-ui default
fi

# پرسیدن از کاربر: ایران یا خارج
echo ""
echo -e "${YELLOW}روی کدوم سرور هستی؟${NC}"
echo "1) سرور ایران (پنل اصلی برای کاربران)"
echo "2) سرور خارج (endpoint برای اینترنت آزاد)"
read -p "انتخاب کن (1 یا 2): " server_type

if [[ $server_type != 1 && $server_type != 2 ]]; then
    echo -e "${RED}انتخاب اشتباه! اسکریپت متوقف شد.${NC}"
    exit 1
fi

# ساخت کلیدهای WireGuard اگر وجود ندارن
private_key_file="/etc/wireguard/private.key"
public_key_file="/etc/wireguard/public.key"

mkdir -p /etc/wireguard
if [ ! -f "$private_key_file" ]; then
    echo -e "${YELLOW}ساخت کلیدهای WireGuard...${NC}"
    wg genkey | tee $private_key_file | wg pubkey > $public_key_file
    chmod 600 $private_key_file
fi

my_private_key=$(cat $private_key_file)
my_public_key=$(cat $public_key_file)

echo -e "${GREEN}کلید عمومی این سرور (برای کپی به سرور دیگه):${NC}"
echo "$my_public_key"

# گرفتن اطلاعات از کاربر
if [ $server_type -eq 1 ]; then  # سرور ایران
    echo -e "${YELLOW}حالا اطلاعات سرور خارج رو وارد کن:${NC}"
    read -p "IP عمومی سرور خارج رو وارد کن (مثل 1.2.3.4): " foreign_ip
    read -p "کلید عمومی سرور خارج رو وارد کن (از خروجی اسکریپت روی خارج کپی کن): " foreign_public_key
    read -p "پورت UDP برای WireGuard (پیش‌فرض 51820 - اگر بلاکه عوض کن): " wg_port
    wg_port=${wg_port:-51820}
    
    # چک کردن دامنه یا IP
    read -p "آیا می‌خوای دامنه برای endpoint استفاده کنی؟ (y/n - اگر y، دامنه رو وارد کن): " use_domain
    if [[ $use_domain == "y" || $use_domain == "Y" ]]; then
        read -p "دامنه سرور خارج رو وارد کن (مثل example.com): " foreign_domain
        endpoint="$foreign_domain:$wg_port"
    else
        endpoint="$foreign_ip:$wg_port"
    fi
    
    # تنظیم آدرس‌های داخلی
    my_wg_ip="10.66.66.2/32"  # ایران
    peer_wg_ip="10.66.66.1/32" # خارج
    
elif [ $server_type -eq 2 ]; then  # سرور خارج
    echo -e "${YELLOW}حالا اطلاعات سرور ایران رو وارد کن:${NC}"
    read -p "IP عمومی سرور ایران رو وارد کن (مثل 5.6.7.8): " iran_ip
    read -p "کلید عمومی سرور ایران رو وارد کن (از خروجی اسکریپت روی ایران کپی کن): " iran_public_key
    read -p "پورت UDP برای WireGuard (پیش‌فرض 51820 - اگر بلاکه عوض کن): " wg_port
    wg_port=${wg_port:-51820}
    
    # تنظیم آدرس‌های داخلی
    my_wg_ip="10.66.66.1/32"  # خارج
    peer_wg_ip="10.66.66.2/32" # ایران
    
    # برای خارج، endpoint لازم نیست چون listenerه
    endpoint=""
fi

# ساخت فایل کانفیگ WireGuard
wg_config="/etc/wireguard/wg0.conf"
echo -e "${YELLOW}ساخت فایل کانفیگ WireGuard...${NC}"

if [ $server_type -eq 1 ]; then  # ایران
    cat <<EOL > $wg_config
[Interface]
Address = $my_wg_ip
PrivateKey = $my_private_key

[Peer]
PublicKey = $foreign_public_key
AllowedIPs = 0.0.0.0/0
Endpoint = $endpoint
PersistentKeepalive = 25
EOL

elif [ $server_type -eq 2 ]; then  # خارج
    cat <<EOL > $wg_config
[Interface]
Address = $my_wg_ip
PrivateKey = $my_private_key
ListenPort = $wg_port

[Peer]
PublicKey = $iran_public_key
AllowedIPs = $peer_wg_ip
EOL
fi

# فعال کردن WireGuard
echo -e "${YELLOW}فعال کردن تونل WireGuard...${NC}"
wg-quick down wg0 &> /dev/null  # اگر قبلاً باشه خاموش کن
wg-quick up wg0
systemctl enable wg-quick@wg0

# چک وضعیت
if wg show wg0 &> /dev/null; then
    echo -e "${GREEN}تونل WireGuard فعال شد! وضعیت:${NC}"
    wg show wg0
else
    echo -e "${RED}خطا در فعال کردن WireGuard. چک کن firewall (ufw allow $wg_port/udp) یا IPها.${NC}"
    exit 1
fi

# تنظیم X-UI برای تونل (فقط روی ایران و خارج اگر پنل دارن)
if [ $server_type -eq 1 ]; then  # ایران: تنظیم outbound به خارج
    echo -e "${YELLOW}تنظیم outbound در X-UI برای هدایت ترافیک به خارج...${NC}"
    # فرض می‌کنیم پنل در /usr/local/x-ui/bin/config.json هست (برای 3X-UI)
    config_file="/usr/local/x-ui/bin/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}فایل کانفیگ X-UI پیدا نشد. مطمئن شو پنل نصب باشه.${NC}"
        exit 1
    fi
    
    # اضافه کردن outbound freedom به WireGuard IP خارج
    jq '.outbounds += [{"protocol": "freedom", "settings": {"domainStrategy": "AsIs"}, "tag": "direct-to-foreign"}]' $config_file > temp.json && mv temp.json $config_file
    
    # اضافه کردن rule برای routing تمام ترافیک به این outbound
    jq '.routing.rules += [{"type": "field", "outboundTag": "direct-to-foreign", "network": "udp,tcp"}]' $config_file > temp.json && mv temp.json $config_file
    
    # ریستارت پنل
    x-ui restart
    echo -e "${GREEN}تنظیم X-UI روی ایران کامل شد. حالا کاربران کانفیگ بگیرن، ترافیک به خارج می‌ره.${NC}"
    
elif [ $server_type -eq 2 ]; then  # خارج: تنظیم inbound برای دریافت از ایران
    echo -e "${YELLOW}تنظیم inbound در X-UI برای دریافت ترافیک از ایران...${NC}"
    # روی خارج هم پنل نصب کن اگر بخوای، اما معمولاً فقط freedom outbound پیش‌فرض کافیه
    # اگر پنل نداری، فقط WireGuard کافیه
    echo -e "${GREEN}روی خارج، پنل لازم نیست اما اگر داری، inbound معمولی بساز.${NC}"
fi

# نکات نهایی
echo -e "${GREEN}نصب کامل شد!${NC}"
echo -e "${GREEN}نکته: firewall رو چک کن (sudo ufw status). اگر UDP بلاک شد، udp2raw اضافه کن.${NC}"
echo -e "${GREEN}برای تست: روی ایران ping 10.66.66.1 بزن.${NC}"
echo -e "${GREEN}اگر مشکلی بود، logها رو چک کن: journalctl -u wg-quick@wg0${NC}"
echo -e "${GREEN}موفق باشی در گسترش بات تلگرامت جاسم! اگر نیاز به اضافه کردن ویژگی به بات داری، بگو.${NC}"
