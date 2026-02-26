#!/bin/bash

# Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Tolong jalankan script ini sebagai root (gunakan sudo su)"
  exit
fi

# ==========================================
# FUNGSI: INSTALL PANEL REVIACTYL
# ==========================================
install_panel() {
    clear
    echo "======================================================"
    echo "        MENGINSTAL REVIACTYL PANEL (WEB & DB)         "
    echo "======================================================"
    echo "--- Konfigurasi Sistem ---"
    read -p "Masukkan nama domain (contoh: dash.kadokun.my.id): " FQDN
    read -p "Masukkan alamat Email (untuk SSL Let's Encrypt): " EMAIL
    read -p "Buat Password Database Panel (jangan lupa!): " DB_PASS
    
    echo ""
    echo "--- Konfigurasi Akun Admin Panel ---"
    read -p "Username Admin: " ADMIN_USER
    read -p "Email Admin: " ADMIN_EMAIL
    read -p "Nama Depan Admin: " ADMIN_FIRST
    read -p "Nama Belakang Admin: " ADMIN_LAST
    read -p "Password Akun Admin: " ADMIN_PASS

    echo "▶ Memasang Dependencies (PHP, NGINX, MariaDB, Redis)..."
    apt update && apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    apt update && apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl} mariadb-server nginx tar unzip git redis-server certbot python3-certbot-nginx

    echo "▶ Menginstal Composer..."
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

    echo "▶ Membuat Database..."
    mysql -u root -e "CREATE USER IF NOT EXISTS 'reviactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'reviactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"

    echo "▶ Mengunduh File Reviactyl..."
    mkdir -p /var/www/reviactyl && cd /var/www/reviactyl
    curl -Lo panel.tar.gz https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz && chmod -R 755 storage/* bootstrap/cache/

    echo "▶ Konfigurasi Environment..."
    cp .env.example .env
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
    
    # Auto-fill .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
    sed -i "s/APP_URL=http:\/\/localhost/APP_URL=https:\/\/${FQDN}/" .env
    chown -R www-data:www-data /var/www/reviactyl/*

    echo "▶ Membuat Konfigurasi NGINX..."
    rm -f /etc/nginx/sites-enabled/default
    cat <<EOF > /etc/nginx/sites-available/reviactyl.conf
server {
    listen 80;
    server_name ${FQDN};
    root /var/www/reviactyl/public;
    index index.html index.htm index.php;
    charset utf-8;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    access_log off;
    error_log  /var/log/nginx/reviactyl.app-error.log error;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
    location ~ /\.ht { deny all; }
}
EOF
    ln -sf /etc/nginx/sites-available/reviactyl.conf /etc/nginx/sites-enabled/reviactyl.conf
    systemctl restart nginx

    echo "▶ Memasang SSL (Let's Encrypt)..."
    certbot --nginx -d ${FQDN} --non-interactive --agree-tos -m ${EMAIL}

    echo "▶ Membuat Queue Worker & Cronjob..."
    (crontab -l 2>/dev/null | grep -v "artisan schedule:run"; echo "* * * * * php /var/www/reviactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
    cat <<EOF > /etc/systemd/system/reviq.service
[Unit]
Description=Reviactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/reviactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now redis-server && systemctl enable --now reviq.service

    echo "▶ Menyiapkan Database & Membuat Akun Admin Otomatis..."
    cd /var/www/reviactyl
    php artisan migrate --seed --force
    php artisan p:user:make --email="${ADMIN_EMAIL}" --username="${ADMIN_USER}" --name-first="${ADMIN_FIRST}" --name-last="${ADMIN_LAST}" --password="${ADMIN_PASS}" --admin=1

    echo "======================================================"
    echo "✅ INSTALASI PANEL SELESAI 100%!"
    echo "🌐 Akses Panel : https://${FQDN}"
    echo "👤 Username    : ${ADMIN_USER}"
    echo "======================================================"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ==========================================
# FUNGSI: INSTALL WINGS
# ==========================================
install_wings() {
    clear
    echo "======================================================"
    echo "          MENGINSTAL PTERODACTYL WINGS (NODE)         "
    echo "======================================================"
    echo "▶ Menginstal Docker..."
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker

    echo "▶ Mengunduh Wings..."
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings

    echo "▶ Membuat Service Systemd untuk Wings..."
    cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now wings
    
    echo "✅ INSTALASI WINGS SELESAI!"
    echo "⚠️ Lakukan konfigurasi Node di Web Panel, lalu jalankan token auto-deploy di terminal ini."
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ==========================================
# FUNGSI: UNINSTALL (HAPUS)
# ==========================================
uninstall_menu() {
    while true; do
        clear
        echo "======================================================"
        echo "                 DANGER ZONE: HAPUS                   "
        echo "======================================================"
        echo "1. Hapus Reviactyl Panel (Web & Database)"
        echo "2. Hapus Wings (Node & Konfigurasi)"
        echo "3. Kembali ke Menu Utama"
        echo "======================================================"
        read -p "Pilih yang ingin dihapus (1-3): " del_choice
        
        case $del_choice in
            1)
                read -p "⚠️ YAKIN ingin menghapus Panel beserta Database? (y/n): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    echo "Mengahapus Panel..."
                    systemctl stop reviq 2>/dev/null
                    systemctl disable reviq 2>/dev/null
                    rm -f /etc/systemd/system/reviq.service
                    rm -rf /var/www/reviactyl
                    rm -f /etc/nginx/sites-available/reviactyl.conf /etc/nginx/sites-enabled/reviactyl.conf
                    systemctl restart nginx
                    mysql -u root -e "DROP DATABASE IF EXISTS panel; DROP USER IF EXISTS 'reviactyl'@'127.0.0.1';"
                    systemctl daemon-reload
                    echo "✅ Panel berhasil dihapus!"
                    read -p "Tekan Enter untuk lanjut..."
                fi
                ;;
            2)
                read -p "⚠️ YAKIN ingin menghapus Wings dan semua konfigurasinya? (y/n): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    echo "Mengahapus Wings..."
                    systemctl stop wings 2>/dev/null
                    systemctl disable wings 2>/dev/null
                    rm -f /usr/local/bin/wings
                    rm -f /etc/systemd/system/wings.service
                    rm -rf /etc/pterodactyl
                    rm -rf /var/lib/pterodactyl
                    systemctl daemon-reload
                    echo "✅ Wings berhasil dihapus dari sistem!"
                    read -p "Tekan Enter untuk lanjut..."
                fi
                ;;
            3)
                break
                ;;
            *)
                echo "Pilihan tidak valid!"
                sleep 1
                ;;
        esac
    done
}

# ==========================================
# MENU UTAMA (VERSI FIX BUG INPUT)
# ==========================================
while true; do
    clear
    echo "======================================================"
    echo "       🚀 REVIACTYL & WINGS MANAGER BY SEPTIA 🚀      "
    echo "======================================================"
    echo "1. Install Reviactyl Panel (Web & Database)"
    echo "2. Install Wings (Pterodactyl Node)"
    echo "3. Uninstall / Hapus Panel atau Wings"
    echo "4. Keluar"
    echo "======================================================"
    
    # Tambahin -p biar prompt nunggu input dengan bener
    read -r -p "Pilih menu (1-4): " main_choice

    case "$main_choice" in
        1) install_panel ;;
        2) install_wings ;;
        3) uninstall_menu ;;
        4) clear; echo "Sampai jumpa, Septia!"; exit 0 ;;
        "") continue ;; # Kalau cuma pencet enter, balik ke atas (jangan bilang invalid)
        *) echo -e "\n❌ Pilihan [$main_choice] tidak valid, coba lagi."; sleep 2 ;;
    esac
done
