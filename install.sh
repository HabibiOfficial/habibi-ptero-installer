#!/usr/bin/env bash
###############################################################################
# Habibi Pterodactyl Auto Installer
# -----------------------------------------------------------------------------
# Installer all-in-one untuk Pterodactyl Panel & Wings, plus INSTALL TEMA.
# Bahasa Indonesia. Dijalankan sebagai root di Ubuntu 20.04 / 22.04 / 24.04.
#
# Cara pakai:
#   sudo bash install.sh
###############################################################################

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export COMPOSER_ALLOW_SUPERUSER=1

PANEL_DIR="/var/www/pterodactyl"
WINGS_BIN="/usr/local/bin/wings"
WINGS_CFG_DIR="/etc/pterodactyl"

# ------------------------------- Warna output -------------------------------
if [[ -t 1 ]]; then
    MERAH='\033[0;31m'; HIJAU='\033[0;32m'; KUNING='\033[1;33m'
    BIRU='\033[0;34m';  CYAN='\033[0;36m';  TEBAL='\033[1m';  RESET='\033[0m'
else
    MERAH=''; HIJAU=''; KUNING=''; BIRU=''; CYAN=''; TEBAL=''; RESET=''
fi

info() { echo -e "${BIRU}[INFO]${RESET} $*"; }
ok()   { echo -e "${HIJAU}[OK]${RESET} $*"; }
warn() { echo -e "${KUNING}[!]${RESET} $*"; }
err()  { echo -e "${MERAH}[ERROR]${RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

# confirm "pertanyaan" [default Y/N] -> return 0 (ya) / 1 (tidak)
confirm() {
    local pesan="$1" default="${2:-N}" jawab label="y/N"
    [[ "$default" =~ ^[Yy]$ ]] && label="Y/n"
    while true; do
        printf "${KUNING}[?]${RESET} %s [%s]: " "$pesan" "$label"
        read -r jawab || jawab=""
        jawab="${jawab:-$default}"
        case "$jawab" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) warn "Jawab y atau n." ;;
        esac
    done
}

banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${TEBAL}"
    echo "  ================================================================"
    echo "   _   _       _     _ _     ____  _                      _       "
    echo "  | | | | __ _| |__ (_) |__ |  _ \| |_ ___ _ __ ___   __| |      "
    echo "  | |_| |/ _\` | '_ \| | '_ \| |_) | __/ _ \ '__/ _ \ / _\` |  "
    echo "  |  _  | (_| | |_) | | |_) |  __/| ||  __/ | | (_) | (_| |      "
    echo "  |_| |_|\__,_|_.__/|_|_.__/ |_|    \__\___|_|  \___/ \__,_|  "
    echo "                                                                "
    echo "   P T E R O D A C T Y L   I N S T A L L E R                     "
    echo "  ================================================================"
    echo -e "${RESET}"
    echo -e "  ${KUNING}Panel + Wings + Install Tema  •  Bahasa Indonesia${RESET}"
    echo
}

need_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "Script ini harus dijalankan sebagai root. Coba: sudo bash $0"
    fi
}

check_os() {
    local os_id="" os_ver=""
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-}"; os_ver="${VERSION_ID:-}"
    fi
    if [[ "$os_id" != "ubuntu" ]]; then
        die "OS tidak didukung (terdeteksi: '${os_id:-tidak diketahui}'). Script ini hanya untuk Ubuntu 20.04 / 22.04 / 24.04."
    fi
    case "$os_ver" in
        20.04|22.04|24.04) ok "OS terdeteksi: Ubuntu $os_ver" ;;
        *) die "Ubuntu $os_ver belum didukung. Gunakan Ubuntu 20.04 / 22.04 / 24.04 yang fresh." ;;
    esac
}

# ------------------------------- Helper umum --------------------------------
rand_hex() { openssl rand -hex "${1:-16}"; }

rand_pass() { openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20; echo; }

# github_latest_asset <owner/repo> <pola-regex-asset> -> cetak URL download
github_latest_asset() {
    local repo="$1" pola="$2" url=""
    printf "${BIRU}[INFO]${RESET} Mengambil info rilis terbaru dari %s ...\n" "$repo" >&2
    url=$(curl -fsSL --retry 3 "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -oE '"browser_download_url": *"[^"]+"' \
        | grep -oE 'https://[^"]+' \
        | grep -E "$pola" | head -n 1 || true)
    if [[ -z "$url" ]]; then
        die "Gagal menemukan asset '$pola' di rilis terbaru $repo. Cek koneksi internet / GitHub API."
    fi
    echo "$url"
}

require_panel() {
    if [[ ! -d "$PANEL_DIR" || ! -f "$PANEL_DIR/artisan" ]]; then
        err "Panel belum terinstall di $PANEL_DIR."
        err "Jalankan menu [1] Install Panel dulu."
        return 1
    fi
}

# set_env KEY VALUE  -> tulis/ubah .env panel dengan aman (via PHP)
set_env() {
    local key="$1" value="$2"
    php -r '
$lines = @file($argv[1], FILE_IGNORE_NEW_LINES);
if ($lines === false) { fwrite(STDERR, "Tidak bisa membaca .env\n"); exit(1); }
$key = $argv[2]; $value = $argv[3];
if ($value === "" || preg_match("/[\s#]/", $value)) {
    $value = "\"" . addcslashes($value, "\"\\") . "\"";
}
$pattern = "/^" . preg_quote($key, "/") . "=.*$/";
$found = false;
foreach ($lines as $i => $line) {
    if (preg_match($pattern, $line)) { $lines[$i] = $key . "=" . $value; $found = true; break; }
}
if (!$found) { $lines[] = $key . "=" . $value; }
file_put_contents($argv[1], implode("\n", $lines) . "\n");
' "$PANEL_DIR/.env" "$key" "$value"
}

fix_perm() {
    chown -R www-data:www-data "$PANEL_DIR"
    chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
}

# ============================ 1. INSTALL PANEL ==============================
install_panel() {
    echo -e "${TEBAL}${CYAN}=== INSTALL PANEL PTERODACTYL ===${RESET}"
    echo

    if [[ -d "$PANEL_DIR" ]]; then
        warn "Folder $PANEL_DIR sudah ada (panel mungkin sudah terinstall)."
        confirm "Lanjut dan TIMPA install yang ada? Data lama bisa hilang" "N" \
            || { info "Dibatalkan."; return 1; }
    fi

    local fqdn email admin_user admin_pass nama_depan nama_belakang
    local db_name db_user db_pass pass_generated="tidak"

    read -rp "FQDN panel (contoh: panel.namadomain.com): " fqdn || fqdn=""
    if [[ ! "$fqdn" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        err "FQDN tidak valid: '$fqdn'"; return 1
    fi
    read -rp "Email admin: " email || email=""
    [[ -n "$email" ]] || { err "Email wajib diisi."; return 1; }

    read -rp "Username admin [admin]: " admin_user || admin_user=""
    admin_user="${admin_user:-admin}"
    read -rp "Nama depan admin [Admin]: " nama_depan || nama_depan=""
    nama_depan="${nama_depan:-Admin}"
    read -rp "Nama belakang admin [Habibi]: " nama_belakang || nama_belakang=""
    nama_belakang="${nama_belakang:-Habibi}"
    read -rsp "Password admin (kosongkan = generate otomatis): " admin_pass; echo
    if [[ -z "$admin_pass" ]]; then
        admin_pass="$(rand_pass)"; pass_generated="ya"
    fi

    read -rp "Nama database [pterodactyl]: " db_name || db_name=""
    db_name="${db_name:-pterodactyl}"
    read -rp "User database [pterodactyl]: " db_user || db_user=""
    db_user="${db_user:-pterodactyl}"
    db_pass="$(rand_hex 16)"

    echo
    info "Ringkasan install:"
    echo "  FQDN     : $fqdn"
    echo "  Email    : $email"
    echo "  Admin    : $admin_user"
    echo "  Database : $db_name (user: $db_user)"
    echo
    confirm "Lanjut install panel?" "Y" || { info "Dibatalkan."; return 1; }

    info "Update package & install perkakas dasar ..."
    apt-get update -y
    apt-get install -y software-properties-common curl tar unzip git \
        lsb-release ca-certificates apt-transport-https gnupg openssl

    info "Menambah PPA ondrej/php ..."
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y

    info "Install PHP 8.2 + ekstensi yang dibutuhkan panel ..."
    apt-get install -y php8.2 php8.2-cli php8.2-fpm php8.2-common php8.2-mysql \
        php8.2-zip php8.2-gd php8.2-mbstring php8.2-curl php8.2-xml php8.2-bcmath

    info "Install MariaDB, Redis, Nginx ..."
    apt-get install -y mariadb-server redis-server nginx
    systemctl enable --now mariadb redis-server nginx

    info "Install Composer (installer resmi) ..."
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f composer-setup.php

    info "Membuat database & user MariaDB ..."
    mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`$db_name\`;
CREATE USER IF NOT EXISTS '$db_user'@'127.0.0.1' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    ok "Database '$db_name' siap."

    info "Download Pterodactyl Panel (rilis terbaru) ..."
    local panel_url tag
    panel_url="$(github_latest_asset "pterodactyl/panel" "panel\.tar\.gz$")"
    tag="$(curl -fsSL --retry 3 https://api.github.com/repos/pterodactyl/panel/releases/latest \
        | grep -oE '"tag_name": *"[^"]+"' | head -n1 | cut -d'"' -f4 || true)"
    info "Versi panel: ${tag:-tidak diketahui}"
    mkdir -p "$PANEL_DIR"
    curl -fsSL --retry 3 -o /tmp/panel.tar.gz "$panel_url"
    tar -xzf /tmp/panel.tar.gz -C "$PANEL_DIR"
    rm -f /tmp/panel.tar.gz
    chmod -R 755 "$PANEL_DIR"

    cd "$PANEL_DIR"
    [[ -f .env.example ]] || { err "File .env.example tidak ditemukan setelah extract."; return 1; }
    cp .env.example .env

    info "Install dependensi Composer (bisa beberapa menit, sabar ya) ..."
    composer install --no-dev --optimize-autoloader --no-interaction

    info "Generate APP_KEY & konfigurasi .env ..."
    php artisan key:generate --force
    set_env "APP_URL" "https://$fqdn"
    set_env "DB_DATABASE" "$db_name"
    set_env "DB_USERNAME" "$db_user"
    set_env "DB_PASSWORD" "$db_pass"
    set_env "CACHE_DRIVER" "redis"
    set_env "SESSION_DRIVER" "redis"
    set_env "QUEUE_CONNECTION" "redis"
    set_env "REDIS_HOST" "127.0.0.1"

    info "Migrasi & seed database ..."
    php artisan migrate --seed --force

    info "Membuat user admin ..."
    php artisan p:user:make \
        --email="$email" \
        --username="$admin_user" \
        --name-first="$nama_depan" \
        --name-last="$nama_belakang" \
        --password="$admin_pass" \
        --admin=1 --no-interaction

    info "Atur kepemilikan & permission ..."
    fix_perm

    info "Membuat service queue worker (pteroq) ..."
    cat > /etc/systemd/system/pteroq.service <<'UNIT'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now pteroq.service

    info "Menjadwalkan cron artisan ..."
    (crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run" || true
     echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

    info "Membuat Nginx vhost untuk $fqdn ..."
    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    server_name ${fqdn};
    root /var/www/pterodactyl/public;
    index index.php;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINX
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    nginx -t
    systemctl reload nginx
    ok "Nginx vhost aktif."

    echo
    if confirm "Pasang SSL gratis (Let's Encrypt via Certbot) sekarang? (butuh DNS $fqdn sudah mengarah ke VPS ini)" "Y"; then
        install_ssl "$fqdn" "$email" || warn "SSL gagal dipasang — bisa dicoba lagi via menu [5]."
    else
        warn "SSL dilewati. Panel hanya bisa diakses via HTTP sampai SSL dipasang (menu 5)."
    fi

    echo
    echo -e "${HIJAU}${TEBAL}================ INSTALL PANEL SELESAI ================${RESET}"
    echo -e "  URL Panel   : ${TEBAL}https://$fqdn${RESET}"
    echo -e "  Username    : ${TEBAL}$admin_user${RESET}"
    echo -e "  Email       : $email"
    echo -e "  Password    : ${KUNING}$admin_pass${RESET}$( [[ "$pass_generated" == "ya" ]] && echo "  (di-generate otomatis — simpan baik-baik!)" )"
    echo -e "  Database    : $db_name  |  User DB: $db_user  |  Pass DB: ${KUNING}$db_pass${RESET}"
    echo -e "  Folder panel: $PANEL_DIR"
    echo -e "${HIJAU}${TEBAL}========================================================${RESET}"
    echo
    warn "SIMPAN kredensial di atas di tempat aman, lalu ganti password admin dari dalam panel."
}

# ============================ 2. INSTALL WINGS ==============================
install_wings() {
    echo -e "${TEBAL}${CYAN}=== INSTALL WINGS (DAEMON) ===${RESET}"
    echo

    if [[ -x "$WINGS_BIN" ]]; then
        warn "Wings sudah terinstall di $WINGS_BIN."
        confirm "Install ulang / update binary Wings?" "N" || { info "Dibatalkan."; return 1; }
    fi

    if command -v docker >/dev/null 2>&1; then
        ok "Docker sudah terinstall, lewati install Docker."
        systemctl enable --now docker 2>/dev/null || true
    else
        info "Install Docker via get.docker.com ..."
        curl -fsSL --retry 3 https://get.docker.com | sh
        systemctl enable --now docker
        ok "Docker terinstall."
    fi

    info "Download Wings (rilis terbaru) ..."
    local wings_url
    wings_url="$(github_latest_asset "pterodactyl/wings" "wings_linux_amd64$")"
    curl -fsSL --retry 3 -o "$WINGS_BIN" "$wings_url"
    chmod +x "$WINGS_BIN"
    ok "Binary Wings tersimpan di $WINGS_BIN."

    mkdir -p "$WINGS_CFG_DIR"

    info "Membuat wings.service ..."
    cat > /etc/systemd/system/wings.service <<'UNIT'
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
ExecStart=/usr/local/bin/wings --config /etc/pterodactyl/config.yml
Restart=on-failure
StartLimitInterval=600

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    ok "Service wings dibuat (SENGAJA belum dijalankan)."

    echo
    echo -e "${TEBAL}${KUNING}>>> LANGKAH WAJIB BERIKUTNYA (manual, cuma sekali):${RESET}"
    echo "  1. Buka panel -> menu Admin -> Nodes -> buat Node baru"
    echo "     (FQDN/IP diisi domain/IP VPS ini, centang SSL bila panel sudah HTTPS)."
    echo "  2. Buka halaman Node tersebut -> tab Configuration."
    echo "  3. Salin SELURUH isi YAML, lalu di VPS jalankan:"
    echo -e "       ${TEBAL}sudo nano /etc/pterodactyl/config.yml${RESET}  -> tempel -> simpan (Ctrl+O, Enter, Ctrl+X)."
    echo "  4. Jalankan Wings:"
    echo -e "       ${TEBAL}sudo systemctl enable --now wings${RESET}"
    echo "  5. Cek status:"
    echo -e "       ${TEBAL}sudo systemctl status wings${RESET}"
    echo

    if grep -q "swapaccount=1" /proc/cmdline 2>/dev/null; then
        ok "Swap accounting terdeteksi aktif."
    else
        warn "Swap accounting BELUM terdeteksi aktif di kernel."
        echo "  Docker butuh ini untuk limit memori server game."
        echo "  Cara cek manual : docker info 2>/dev/null | grep -i swap"
        echo "  Jika muncul 'No swap limit support', aktifkan:"
        echo "    1) Edit /etc/default/grub -> tambah swapaccount=1 di GRUB_CMDLINE_LINUX"
        echo "       contoh: GRUB_CMDLINE_LINUX=\"swapaccount=1\""
        echo "    2) sudo update-grub && sudo reboot"
    fi
}

# ============================ 3. INSTALL TEMA ===============================
install_theme() {
    echo -e "${TEBAL}${CYAN}=== INSTALL TEMA PANEL ===${RESET}"
    echo
    require_panel || return 1

    warn "Pemasangan tema menimpa file panel. Backup otomatis AKAN dibuat dulu."
    local url ts backup tmpzip
    read -rp "URL file ZIP tema (contoh: link release GitHub tema): " url || url=""
    if [[ ! "$url" =~ ^https?:// ]]; then
        err "URL tidak valid: '$url'"; return 1
    fi

    confirm "Panel akan masuk maintenance mode sementara. Lanjut pasang tema?" "Y" \
        || { info "Dibatalkan."; return 1; }

    cd "$PANEL_DIR"
    php artisan down 2>/dev/null || true

    ts="$(date +%Y%m%d-%H%M%S)"
    backup="/root/pterodactyl-backup-${ts}.tar.gz"
    info "Backup panel ke $backup ..."
    tar -czf "$backup" -C /var/www pterodactyl
    ok "Backup selesai."

    tmpzip="/tmp/tema-${ts}.zip"
    info "Download tema ..."
    if ! curl -fsSL --retry 3 -o "$tmpzip" "$url"; then
        err "Download tema gagal. Cek URL-nya."
        php artisan up 2>/dev/null || true
        return 1
    fi
    info "Extract tema ke $PANEL_DIR (timpa file lama) ..."
    if ! unzip -o -q "$tmpzip" -d "$PANEL_DIR"; then
        err "Extract ZIP gagal. File mungkin bukan ZIP valid."
        php artisan up 2>/dev/null || true
        return 1
    fi
    rm -f "$tmpzip"
    ok "File tema di-extract."

    if [[ -f "$PANEL_DIR/install.sh" ]]; then
        warn "Tema ini menyertakan install.sh bawaannya sendiri."
        if confirm "Jalankan install.sh bawaan tema?" "N"; then
            info "Menjalankan install.sh bawaan tema ..."
            bash "$PANEL_DIR/install.sh" || warn "install.sh tema selesai dengan error (cek manual)."
        fi
    fi

    info "Bersihkan cache Laravel ..."
    php artisan view:clear 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true

    echo
    warn "Build ulang assets HANYA perlu jika tema mengubah file frontend (resources/)."
    warn "Butuh Node.js + Yarn dan bisa makan waktu 10-30 menit."
    if confirm "Jalankan yarn install && yarn build:production ?" "N"; then
        if command -v yarn >/dev/null 2>&1; then
            info "Build assets (lama, jangan tutup terminal) ..."
            (cd "$PANEL_DIR" && yarn install && yarn build:production) \
                || warn "Build gagal — panel mungkin tetap jalan, cek manual."
        else
            err "Yarn tidak ditemukan. Install Node.js + Yarn dulu, lalu build manual dari $PANEL_DIR."
        fi
    else
        info "Build assets dilewati."
    fi

    info "Perbaiki permission & nyalakan panel ..."
    fix_perm
    php artisan up 2>/dev/null || true

    echo
    ok "Tema selesai dipasang!"
    info "File backup: $backup"
    warn "Jika panel error setelah ganti tema, restore dengan:"
    echo -e "  ${TEBAL}tar -xzf $backup -C / && chown -R www-data:www-data $PANEL_DIR${RESET}"
}

# ============================ 4. BUAT USER ADMIN ============================
create_admin() {
    echo -e "${TEBAL}${CYAN}=== BUAT USER ADMIN BARU ===${RESET}"
    echo
    require_panel || return 1

    local email username nama_depan nama_belakang pass generated="tidak"
    read -rp "Email: " email || email=""
    [[ -n "$email" ]] || { err "Email wajib diisi."; return 1; }
    read -rp "Username: " username || username=""
    [[ -n "$username" ]] || { err "Username wajib diisi."; return 1; }
    read -rp "Nama depan [Admin]: " nama_depan || nama_depan=""
    nama_depan="${nama_depan:-Admin}"
    read -rp "Nama belakang [Habibi]: " nama_belakang || nama_belakang=""
    nama_belakang="${nama_belakang:-Habibi}"
    read -rsp "Password (kosongkan = generate otomatis): " pass; echo
    if [[ -z "$pass" ]]; then
        pass="$(rand_pass)"; generated="ya"
    fi

    cd "$PANEL_DIR"
    php artisan p:user:make \
        --email="$email" \
        --username="$username" \
        --name-first="$nama_depan" \
        --name-last="$nama_belakang" \
        --password="$pass" \
        --admin=1 --no-interaction

    ok "User admin '$username' berhasil dibuat."
    if [[ "$generated" == "ya" ]]; then
        echo -e "  Password (generate): ${KUNING}$pass${RESET}  <- simpan baik-baik!"
    fi
}

# ============================ 5. PASANG SSL =================================
install_ssl() {
    local fqdn="${1:-}" email="${2:-}"
    echo -e "${TEBAL}${CYAN}=== PASANG SSL (CERTBOT / LET'S ENCRYPT) ===${RESET}"
    echo

    if [[ -z "$fqdn" ]]; then
        if [[ -f "$PANEL_DIR/.env" ]]; then
            fqdn="$(grep -E "^APP_URL=" "$PANEL_DIR/.env" | cut -d= -f2- | sed -e 's#^https\?://##' -e 's#/.*##' -e 's#"##g' || true)"
        fi
        if [[ -z "$fqdn" ]]; then
            read -rp "FQDN (contoh: panel.namadomain.com): " fqdn || fqdn=""
        fi
    fi
    [[ -n "$fqdn" ]] || { err "FQDN tidak diketahui."; return 1; }

    if [[ -z "$email" ]]; then
        read -rp "Email untuk notifikasi Let's Encrypt: " email || email=""
        [[ -n "$email" ]] || { err "Email wajib diisi."; return 1; }
    fi

    warn "Pastikan DNS $fqdn SUDAH mengarah ke IP VPS ini sebelum lanjut."
    confirm "Lanjut pasang SSL untuk $fqdn ?" "Y" || { info "Dibatalkan."; return 1; }

    info "Install Certbot ..."
    apt-get update -y
    apt-get install -y certbot python3-certbot-nginx

    info "Meminta sertifikat untuk $fqdn ..."
    if certbot --nginx -d "$fqdn" --non-interactive --agree-tos -m "$email" --redirect; then
        ok "SSL terpasang! Panel bisa diakses via https://$fqdn"
        info "Auto-renewal sudah dijadwalkan otomatis oleh Certbot."
    else
        err "Certbot gagal. Penyebab umum: DNS belum propagasi / port 80 tertutup."
        return 1
    fi
}

# ============================ 6. UPDATE PANEL ===============================
update_panel() {
    echo -e "${TEBAL}${CYAN}=== UPDATE PANEL KE VERSI TERBARU ===${RESET}"
    echo
    require_panel || return 1

    warn "Panel akan maintenance sementara & backup otomatis dibuat."
    confirm "Lanjut update panel?" "Y" || { info "Dibatalkan."; return 1; }

    cd "$PANEL_DIR"
    php artisan down 2>/dev/null || true

    local ts backup url tag
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="/root/pterodactyl-backup-${ts}.tar.gz"
    info "Backup ke $backup ..."
    tar -czf "$backup" -C /var/www pterodactyl

    info "Download panel versi terbaru ..."
    url="$(github_latest_asset "pterodactyl/panel" "panel\.tar\.gz$")"
    tag="$(curl -fsSL --retry 3 https://api.github.com/repos/pterodactyl/panel/releases/latest \
        | grep -oE '"tag_name": *"[^"]+"' | head -n1 | cut -d'"' -f4 || true)"
    info "Versi: ${tag:-tidak diketahui}"
    curl -fsSL --retry 3 -o /tmp/panel.tar.gz "$url"
    tar -xzf /tmp/panel.tar.gz -C "$PANEL_DIR"
    rm -f /tmp/panel.tar.gz

    info "Composer install & migrasi database ..."
    composer install --no-dev --optimize-autoloader --no-interaction
    php artisan migrate --force

    info "Bersihkan cache & restart queue ..."
    php artisan view:clear 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true
    php artisan queue:restart 2>/dev/null || true

    fix_perm
    php artisan up 2>/dev/null || true

    echo
    ok "Panel berhasil di-update ke ${tag:-versi terbaru}!"
    info "Backup tersimpan di: $backup"
}

# ============================ 7. UNINSTALL PANEL ============================
uninstall_panel() {
    echo -e "${TEBAL}${MERAH}=== UNINSTALL PANEL ===${RESET}"
    echo
    warn "INI AKAN MENGHAPUS SELURUH PANEL PTERODACTYL DARI VPS!"
    confirm "Yakin mau uninstall panel?" "N" || { info "Dibatalkan."; return 1; }

    local ketik=""
    read -rp "Ketik HAPUS (huruf kapital semua) untuk konfirmasi terakhir: " ketik || ketik=""
    if [[ "$ketik" != "HAPUS" ]]; then
        info "Konfirmasi tidak cocok. Dibatalkan."
        return 1
    fi

    info "Stop & hapus service pteroq ..."
    systemctl stop pteroq.service 2>/dev/null || true
    systemctl disable pteroq.service 2>/dev/null || true
    rm -f /etc/systemd/system/pteroq.service
    systemctl daemon-reload 2>/dev/null || true

    info "Hapus cron artisan ..."
    (crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run" || true) | crontab - 2>/dev/null || true

    info "Hapus vhost Nginx ..."
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true

    if [[ -f "$PANEL_DIR/.env" ]] && confirm "Drop database panel juga? (data user/server ikut hilang)" "N"; then
        local db dbuser
        db="$(grep -E "^DB_DATABASE=" "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"' || true)"
        dbuser="$(grep -E "^DB_USERNAME=" "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"' || true)"
        if [[ -n "$db" ]]; then
            mysql -u root -e "DROP DATABASE IF EXISTS \`$db\`;" 2>/dev/null || warn "Gagal drop database (mungkin MariaDB sudah tidak ada)."
        fi
        if [[ -n "$dbuser" ]]; then
            mysql -u root -e "DROP USER IF EXISTS '$dbuser'@'127.0.0.1';" 2>/dev/null || true
        fi
        ok "Database dihapus."
    fi

    info "Hapus folder panel $PANEL_DIR ..."
    rm -rf "$PANEL_DIR"

    echo
    ok "Panel berhasil di-uninstall."
    info "Catatan: PHP/MariaDB/Redis/Nginx TIDAK ikut dihapus (dipakai komponen lain)."
}

# ============================ 8. UNINSTALL WINGS ============================
uninstall_wings() {
    echo -e "${TEBAL}${MERAH}=== UNINSTALL WINGS ===${RESET}"
    echo
    warn "Ini akan menghapus Wings daemon dari VPS."
    confirm "Yakin mau uninstall Wings?" "N" || { info "Dibatalkan."; return 1; }

    info "Stop & hapus service wings ..."
    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
    rm -f /etc/systemd/system/wings.service
    systemctl daemon-reload 2>/dev/null || true

    info "Hapus binary Wings ..."
    rm -f "$WINGS_BIN"

    if confirm "Hapus juga folder konfigurasi $WINGS_CFG_DIR ?" "Y"; then
        rm -rf "$WINGS_CFG_DIR"
        ok "Folder konfigurasi dihapus."
    else
        info "Folder konfigurasi dibiarkan (bisa dipakai kalau install ulang)."
    fi

    if confirm "Hapus juga Docker?" "N"; then
        info "Hapus Docker ..."
        apt-get purge -y docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        warn "Data image/container di /var/lib/docker TIDAK dihapus otomatis."
        warn "Hapus manual bila perlu: sudo rm -rf /var/lib/docker"
    fi

    echo
    ok "Wings berhasil di-uninstall."
}

# ================================== MENU ====================================
tampilkan_menu() {
    banner
    echo -e "  ${TEBAL}Pilih aksi:${RESET}"
    echo
    echo -e "   ${HIJAU}${TEBAL}1${RESET}) Install Panel           ${BIRU}(panel web Pterodactyl)${RESET}"
    echo -e "   ${HIJAU}${TEBAL}2${RESET}) Install Wings           ${BIRU}(daemon server game)${RESET}"
    echo -e "   ${HIJAU}${TEBAL}3${RESET}) Install Tema Panel      ${BIRU}(ganti tampilan panel)${RESET}"
    echo -e "   ${HIJAU}${TEBAL}4${RESET}) Buat User Admin         ${BIRU}(tambah admin baru)${RESET}"
    echo -e "   ${HIJAU}${TEBAL}5${RESET}) Pasang SSL (Certbot)     ${BIRU}(HTTPS Let's Encrypt)${RESET}"
    echo -e "   ${HIJAU}${TEBAL}6${RESET}) Update Panel            ${BIRU}(ke versi terbaru)${RESET}"
    echo -e "   ${MERAH}${TEBAL}7${RESET}) Uninstall Panel"
    echo -e "   ${MERAH}${TEBAL}8${RESET}) Uninstall Wings"
    echo -e "   ${TEBAL}9${RESET}) Keluar"
    echo
}

main() {
    # Script ini 100% interaktif (menu + tanya jawab), jadi WAJIB dijalankan
    # dengan keyboard asli. Kalau dijalankan via pipe (curl ... | bash),
    # stdin bukan terminal -> read langsung EOF -> menu nge-loop tanpa henti.
    if [[ ! -t 0 ]]; then
        err "Script ini interaktif dan butuh keyboard. Jangan dijalankan dengan:"
        err "  curl ... | sudo bash"
        err "Cara yang benar:"
        err "  curl -sSL -o install.sh https://raw.githubusercontent.com/HabibiOfficial/habibi-ptero-installer/main/install.sh"
        err "  chmod +x install.sh"
        err "  sudo ./install.sh"
        exit 1
    fi
    need_root
    check_os
    trap 'echo; err "Dibatalkan oleh user."; exit 130' INT

    while true; do
        tampilkan_menu
        local pilih=""
        read -rp "Pilih menu [1-9]: " pilih || pilih=""
        echo
        case "$pilih" in
            1) install_panel || true ;;
            2) install_wings || true ;;
            3) install_theme || true ;;
            4) create_admin || true ;;
            5) install_ssl || true ;;
            6) update_panel || true ;;
            7) uninstall_panel || true ;;
            8) uninstall_wings || true ;;
            9) echo -e "${HIJAU}Terima kasih sudah memakai Habibi Pterodactyl Installer!${RESET}"; exit 0 ;;
            *) warn "Pilihan tidak valid, coba lagi." ;;
        esac
        echo
        read -rp "Tekan Enter untuk kembali ke menu ..." _ || true
    done
}

main "$@"
