#!/usr/bin/env bash
set -e

# =====================================
# AUTO INSTALL REVIACTYL
# by Ryan (Asep)
# =====================================

INPUT="/dev/tty"

[ "$(id -u)" != "0" ] && {
 echo "Jalankan sebagai root!"
 exit 1
}

pause(){
 read -r -p "Tekan Enter..." _ < "$INPUT"
}

ask(){
 printf "%s" "$1"
 read -r val < "$INPUT"
 echo "$val"
}

install_composer(){

if command -v composer >/dev/null 2>&1; then
 return
fi

echo "Install Composer..."

apt install -y php-cli curl unzip

php -r "copy('https://getcomposer.org/installer','composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php
}

# =====================================
# INSTALL PANEL
# =====================================
install_panel(){

clear
echo "===== INSTALL REVIACTYL PANEL ====="

FQDN=$(ask "Domain Panel : ")
EMAIL=$(ask "Email SSL    : ")
DB_PASS=$(ask "Password DB  : ")

ADMIN_USER=$(ask "Username Admin : ")
ADMIN_EMAIL=$(ask "Email Admin    : ")
ADMIN_FIRST=$(ask "Nama Depan     : ")
ADMIN_LAST=$(ask "Nama Belakang  : ")
ADMIN_PASS=$(ask "Password Admin : ")

apt update -y
apt install -y software-properties-common curl ca-certificates gnupg git unzip tar mariadb-server nginx redis-server certbot python3-certbot-nginx

add-apt-repository -y ppa:ondrej/php
apt update -y

apt install -y \
php8.3 php8.3-cli php8.3-fpm php8.3-mysql \
php8.3-gd php8.3-mbstring php8.3-xml \
php8.3-bcmath php8.3-curl php8.3-zip php8.3-intl

install_composer

mysql <<EOF
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'reviactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'reviactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

rm -rf /var/www/reviactyl
mkdir -p /var/www/reviactyl
cd /var/www/reviactyl

curl -L https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz -o panel.tar.gz
tar -xzf panel.tar.gz
rm panel.tar.gz

cp .env.example .env

COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

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

echo "✅ PANEL TERINSTALL"
echo "https://${FQDN}"

pause
}

# =====================================
# INSTALL WINGS
# =====================================
install_wings(){

clear
echo "===== INSTALL WINGS ====="

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

echo "✅ WINGS TERINSTALL"
pause
}

# =====================================
# DELETE PANEL TOTAL
# =====================================
delete_panel(){

clear
echo "Hapus Panel..."

rm -rf /var/www/reviactyl
rm -f /etc/nginx/sites-enabled/reviactyl.conf
rm -f /etc/nginx/sites-available/reviactyl.conf

mysql -e "DROP DATABASE IF EXISTS panel;"
mysql -e "DROP USER IF EXISTS 'reviactyl'@'127.0.0.1';"

systemctl restart nginx

rm -rf /etc/letsencrypt/live/*
rm -rf /etc/letsencrypt/archive/*
rm -rf /etc/letsencrypt/renewal/*

echo "✅ PANEL DIHAPUS TOTAL"
pause
}

# =====================================
# DELETE WINGS TOTAL
# =====================================
delete_wings(){

clear
echo "Hapus Wings..."

systemctl stop wings || true
systemctl disable wings || true

rm -f /etc/systemd/system/wings.service
rm -f /usr/local/bin/wings

rm -rf /etc/pterodactyl
rm -rf /var/lib/pterodactyl

docker rm -f $(docker ps -aq) 2>/dev/null || true
docker network prune -f || true

systemctl daemon-reload

echo "✅ WINGS DIHAPUS TOTAL"
pause
}

# =====================================
# RESET SEMUA
# =====================================
delete_all(){
delete_panel
delete_wings
echo "✅ VPS PANEL CLEAN TOTAL"
pause
}

# =====================================
# MENU
# =====================================
while true; do

clear
echo "======================================"
echo " REVIACTYL FULL MANAGER"
echo "        by Ryan (Asep)"
echo "======================================"
echo "1. Install Panel"
echo "2. Install Wings"
echo "3. Delete Panel"
echo "4. Delete Wings"
echo "5. Reset Semua"
echo "6. Keluar"
echo "======================================"

printf "Pilih Menu : "
read -r menu < "$INPUT"

case "$menu" in
1) install_panel ;;
2) install_wings ;;
3) delete_panel ;;
4) delete_wings ;;
5) delete_all ;;
6) exit 0 ;;
*) echo "Menu tidak valid"; sleep 1 ;;
esac

done
