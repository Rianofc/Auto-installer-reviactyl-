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

# =====================================
# INSTALL PANEL
# =====================================
install_panel(){

clear
echo "INSTALL PANEL REVIACTYL"

FQDN=$(ask "Domain Panel : ")
EMAIL=$(ask "Email SSL    : ")
DB_PASS=$(ask "Password DB  : ")

ADMIN_USER=$(ask "Username Admin : ")
ADMIN_EMAIL=$(ask "Email Admin    : ")
ADMIN_FIRST=$(ask "Nama Depan     : ")
ADMIN_LAST=$(ask "Nama Belakang  : ")
ADMIN_PASS=$(ask "Password Admin : ")

apt update -y
apt install -y software-properties-common curl ca-certificates gnupg unzip git tar

add-apt-repository -y ppa:ondrej/php
apt update -y

apt install -y \
php8.3 php8.3-cli php8.3-fpm php8.3-mysql php8.3-gd \
php8.3-mbstring php8.3-xml php8.3-bcmath php8.3-curl php8.3-zip php8.3-intl \
nginx mariadb-server redis-server certbot python3-certbot-nginx

# composer
if ! command -v composer >/dev/null 2>&1; then
 curl -sS https://getcomposer.org/installer | php
 mv composer.phar /usr/local/bin/composer
fi

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

COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev
php artisan key:generate --force

sed -i "s|APP_URL=.*|APP_URL=https://${FQDN}|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" .env

chown -R www-data:www-data /var/www/reviactyl

rm -f /etc/nginx/sites-enabled/default

cat >/etc/nginx/sites-available/reviactyl.conf <<EOF
server {
 listen 80;
 server_name ${FQDN};
 root /var/www/reviactyl/public;
 index index.php;

 location / {
  try_files \$uri \$uri/ /index.php?\$query_string;
 }

 location ~ \.php$ {
  include snippets/fastcgi-php.conf;
  fastcgi_pass unix:/run/php/php8.3-fpm.sock;
 }
}
EOF

ln -sf /etc/nginx/sites-available/reviactyl.conf \
/etc/nginx/sites-enabled/reviactyl.conf

systemctl restart nginx

certbot --nginx -d "$FQDN" --non-interactive --agree-tos -m "$EMAIL" || true

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
