#!/bin/bash

# =====================================
# AUTO INSTALL REVIACTYL BY Ryan(Asep)
# =====================================

if [[ $EUID -ne 0 ]]; then
 echo "Jalankan sebagai root!"
 exit 1
fi

pause(){
 read -rp "Tekan Enter untuk kembali..."
}

# =====================================
# INSTALL PANEL
# =====================================
install_panel(){

clear
echo "======================================"
echo " AUTO INSTALL REVIACTYL BY Ryan(Asep)"
echo " INSTALL PANEL"
echo "======================================"

read -rp "Domain Panel : " FQDN
read -rp "Email SSL    : " EMAIL
read -rsp "Password DB  : " DB_PASS
echo

read -rp "Username Admin : " ADMIN_USER
read -rp "Email Admin    : " ADMIN_EMAIL
read -rp "Nama Depan     : " ADMIN_FIRST
read -rp "Nama Belakang  : " ADMIN_LAST
read -rsp "Password Admin: " ADMIN_PASS
echo

apt update -y
apt install -y software-properties-common curl ca-certificates gnupg unzip git tar

add-apt-repository -y ppa:ondrej/php
apt update -y

apt install -y \
php8.3 php8.3-{cli,fpm,mysql,gd,mbstring,xml,bcmath,curl,zip,intl} \
nginx mariadb-server redis-server \
certbot python3-certbot-nginx

# Composer
if ! command -v composer &>/dev/null; then
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
fi

echo "Setup Database..."

mysql <<EOF
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'reviactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'reviactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

mkdir -p /var/www/reviactyl
cd /var/www/reviactyl

echo "Download Panel..."
curl -L https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz -o panel.tar.gz
tar -xzf panel.tar.gz

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

 client_max_body_size 100m;
}
EOF

ln -sf /etc/nginx/sites-available/reviactyl.conf \
/etc/nginx/sites-enabled/reviactyl.conf

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

echo
echo "✅ PANEL BERHASIL DIINSTALL"
echo "https://${FQDN}"

pause
}

# =====================================
# INSTALL WINGS
# =====================================
install_wings(){

clear
echo "INSTALL WINGS NODE"

curl -sSL https://get.docker.com | bash
systemctl enable docker --now

mkdir -p /etc/pterodactyl

ARCH="amd64"
[[ $(uname -m) == "aarch64" ]] && ARCH="arm64"

curl -L \
https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH} \
-o /usr/local/bin/wings

chmod +x /usr/local/bin/wings

cat >/etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings
After=docker.service

[Service]
ExecStart=/usr/local/bin/wings
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wings --now

echo "✅ Wings berhasil diinstall"
pause
}

# =====================================
# UNINSTALL PANEL
# =====================================
remove_panel(){

clear
read -rp "Yakin hapus Panel? (y/n): " confirm
[[ $confirm != "y" ]] && return

systemctl stop nginx

rm -rf /var/www/reviactyl
rm -f /etc/nginx/sites-enabled/reviactyl.conf
rm -f /etc/nginx/sites-available/reviactyl.conf

mysql -e "DROP DATABASE IF EXISTS panel;"
mysql -e "DROP USER IF EXISTS 'reviactyl'@'127.0.0.1';"

systemctl restart nginx

echo "✅ Panel berhasil dihapus"
pause
}

# =====================================
# UNINSTALL WINGS
# =====================================
remove_wings(){

clear
read -rp "Yakin hapus Wings? (y/n): " confirm
[[ $confirm != "y" ]] && return

systemctl stop wings
systemctl disable wings

rm -f /usr/local/bin/wings
rm -rf /etc/pterodactyl
rm -rf /var/lib/pterodactyl
rm -f /etc/systemd/system/wings.service

systemctl daemon-reload

echo "✅ Wings berhasil dihapus"
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
echo "3. Uninstall Panel"
echo "4. Uninstall Wings"
echo "5. Keluar"
echo "======================================"

read -rp "Pilih Menu : " menu

case "$menu" in
1) install_panel ;;
2) install_wings ;;
3) remove_panel ;;
4) remove_wings ;;
5) exit 0 ;;
*) echo "Menu tidak valid"; sleep 1 ;;
esac

done
