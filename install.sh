#!/usr/bin/env bash

# =====================================
# AUTO INSTALL REVIACTYL BY Ryan(Asep)
# =====================================

[ "$(id -u)" != "0" ] && {
 echo "Jalankan sebagai root!"
 exit 1
}

INPUT="/dev/tty"

pause(){
 echo ""
 read -r -p "Tekan Enter untuk kembali..." _ < "$INPUT"
}

ask(){
 printf "%s" "$1"
 read -r REPLY < "$INPUT"
 echo "$REPLY"
}
install_panel(){

clear
echo "======================================"
echo " INSTALL PANEL REVIACTYL"
echo "======================================"

printf "Domain Panel : "
read -r FQDN < /dev/tty

printf "Email SSL    : "
read -r EMAIL < /dev/tty

printf "Password DB  : "
read -r DB_PASS < /dev/tty

printf "Username Admin : "
read -r ADMIN_USER < /dev/tty

printf "Email Admin    : "
read -r ADMIN_EMAIL < /dev/tty

printf "Nama Depan     : "
read -r ADMIN_FIRST < /dev/tty

printf "Nama Belakang  : "
read -r ADMIN_LAST < /dev/tty

printf "Password Admin : "
read -r ADMIN_PASS < /dev/tty

echo ""
echo "Mulai install panel..."

apt update -y
apt install -y software-properties-common curl ca-certificates gnupg unzip git tar

add-apt-repository -y ppa:ondrej/php
apt update -y

apt install -y \
php8.3 php8.3-cli php8.3-fpm php8.3-mysql php8.3-gd \
php8.3-mbstring php8.3-xml php8.3-bcmath php8.3-curl php8.3-zip php8.3-intl \
nginx mariadb-server redis-server certbot python3-certbot-nginx

echo "Setup database..."

mysql <<EOF
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'reviactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'reviactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

mkdir -p /var/www/reviactyl
cd /var/www/reviactyl || exit

curl -L https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz -o panel.tar.gz
tar -xzf panel.tar.gz

cp .env.example .env

composer install --no-dev
php artisan key:generate --force

sed -i "s|APP_URL=.*|APP_URL=https://${FQDN}|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" .env

chown -R www-data:www-data /var/www/reviactyl

systemctl restart nginx

certbot --nginx -d "$FQDN" \
--non-interactive --agree-tos -m "$EMAIL" || true

php artisan migrate --seed --force

php artisan p:user:make \
--email="$ADMIN_EMAIL" \
--username="$ADMIN_USER" \
--name-first="$ADMIN_FIRST" \
--name-last="$ADMIN_LAST" \
--password="$ADMIN_PASS" \
--admin=1

echo ""
echo "✅ PANEL BERHASIL DIINSTALL"
echo "https://${FQDN}"

pause
}

# =====================================
# INSTALL WINGS
# =====================================
install_wings(){

clear
echo "INSTALL WINGS"

curl -sSL https://get.docker.com | bash
systemctl enable docker --now

ARCH="amd64"
[ "$(uname -m)" = "aarch64" ] && ARCH="arm64"

mkdir -p /etc/pterodactyl

curl -L \
https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH} \
-o /usr/local/bin/wings

chmod +x /usr/local/bin/wings

cat >/etc/systemd/system/wings.service <<EOF
[Unit]
Description=Wings
After=docker.service

[Service]
ExecStart=/usr/local/bin/wings
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wings --now

echo "✅ Wings berhasil diinstall"
pause
}

# =====================================
# MENU
# =====================================
while true; do

clear
echo "======================================"
echo " AUTO INSTALL REVIACTYL"
echo "        by Ryan (Asep)"
echo "======================================"
echo "1. Install Reviactyl Panel"
echo "2. Install Wings Node"
echo "3. Keluar"
echo "======================================"

printf "Pilih Menu : "
read -r menu < "$INPUT"

case "$menu" in
1) install_panel ;;
2) install_wings ;;
3) exit 0 ;;
*) echo "Menu tidak valid"; sleep 1 ;;
esac

done
