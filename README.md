# Habibi Pterodactyl Installer

Auto-installer **all-in-one** untuk **Pterodactyl Panel & Wings** dalam SATU file, dengan menu interaktif **Bahasa Indonesia**.

Beda dari script installer orang lain: script ini punya menu **Install Tema Panel** 🎨 — lengkap dengan backup otomatis sebelum tema dipasang, jadi aman kalau tema bikin panel error.

---

## ✨ Fitur

| Menu | Keterangan |
|------|------------|
| 1. Install Panel | Install Pterodactyl Panel versi terbaru (diambil otomatis dari GitHub), PHP 8.2, MariaDB, Redis, Nginx, Composer, queue worker, cron, vhost Nginx |
| 2. Install Wings | Install Docker + Wings daemon versi terbaru + systemd service |
| 3. **Install Tema Panel** ⭐ | Pasang tema dari URL ZIP (backup otomatis dulu, maintenance mode, clear cache, opsional build assets) |
| 4. Buat User Admin | Tambah admin baru kapan saja via `p:user:make` |
| 5. Pasang SSL | HTTPS gratis via Let's Encrypt (Certbot) |
| 6. Update Panel | Update ke rilis terbaru (backup otomatis dulu) |
| 7. Uninstall Panel | Hapus panel bersih-bersih (konfirmasi 2x) |
| 8. Uninstall Wings | Hapus Wings (+ opsi hapus Docker) |
| 9. Keluar | — |

Selama install, password database & password admin bisa **di-generate otomatis** (aman, acak).

---

## 📋 Syarat

- VPS **fresh** (belum diutak-atik) — Ubuntu **22.04** atau **24.04** (20.04 juga didukung script, tapi 22.04/24.04 disarankan)
- Akses **root** (atau user dengan `sudo`)
- Punya **FQDN** (contoh: `panel.namadomain.com`) yang DNS-nya **sudah mengarah (A record) ke IP VPS** — wajib untuk SSL & Wings
- Koneksi internet yang stabil (install butuh download ± beberapa ratus MB)

> ⚠️ Jangan jalankan di VPS yang sudah ada web server / panel lain — port 80/443 dan Nginx akan dikonfigurasi ulang.

---

## 🚀 Cara Pakai

Jalankan perintah ini di VPS (sebagai root / pakai sudo):

```bash
curl -sSL -o install.sh https://raw.githubusercontent.com/HabibiOfficial/habibi-ptero-installer/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

> ⚠️ Jangan dijalankan dengan `curl ... | sudo bash` — script ini interaktif
> (menu pilihan + tanya jawab) dan butuh keyboard. Kalau di-pipe, menunya akan
> nge-loop tanpa henti. Script akan menolak berjalan dan menampilkan cara yang
> benar kalau kamu mencobanya.

Lalu tinggal pilih menu angka **1–9** dan ikuti pertanyaannya (semua Bahasa Indonesia).

---

## 🧭 Penjelasan Tiap Menu

### 1. Install Panel
- Input: FQDN, email admin, username + nama + password admin (boleh kosong → generate), nama DB & user DB (password DB selalu generate).
- Yang dikerjakan: tambah PPA `ondrej/php`, install PHP 8.2 + ekstensi (`cli fpm common mysql zip gd mbstring curl xml bcmath`), MariaDB, Redis, Nginx, Composer (installer resmi).
- Buat database & user MariaDB, download `panel.tar.gz` rilis terbaru dari GitHub, `composer install`, `key:generate`, set `.env` (`APP_URL`, `DB_*`, `CACHE/SESSION/QUEUE = redis`), `migrate --seed`, buat admin via `p:user:make --admin=1`.
- Buat service `pteroq` (queue worker), cron `schedule:run` tiap menit, vhost Nginx + `nginx -t` + reload.
- Di akhir ditawari pasang SSL otomatis, lalu tampil **ringkasan kredensial** — simpan baik-baik!

### 2. Install Wings
- Install Docker via `https://get.docker.com` (dilewati kalau Docker sudah ada).
- Download binary `wings_linux_amd64` rilis terbaru ke `/usr/local/bin/wings`, buat folder `/etc/pterodactyl`, buat `wings.service` (systemd, jalan setelah Docker).
- **Sengaja TIDAK auto-start.** Ikuti 4 langkah yang ditampilkan script: buat Node di panel → salin `config.yml` dari tab Configuration → tempel ke `/etc/pterodactyl/config.yml` → `sudo systemctl enable --now wings`.
- Script juga mengingatkan soal **swap accounting** bila belum aktif (dibutuhkan Docker untuk limit memori).

### 3. Install Tema Panel ⭐
- Input: **URL file ZIP tema** (bebas — dari release GitHub tema apa pun, tidak dikunci ke tema tertentu).
- Alur otomatis: `artisan down` → **backup** ke `/root/pterodactyl-backup-YYYYMMDD-HHMMSS.tar.gz` → download & extract timpa → kalau tema bawa `install.sh`, ditawari menjalankannya → `view:clear`/`config:clear`/`route:clear` → perbaiki permission → `artisan up`.
- Opsional (default **N**): build ulang assets (`yarn build:production`) — hanya perlu kalau tema mengubah file frontend; butuh Node.js + Yarn dan bisa 10–30 menit.

### 4. Buat User Admin
Tambah admin baru kapan saja tanpa install ulang. Password boleh dikosongkan (generate otomatis).

### 5. Pasang SSL (Certbot)
Baca FQDN dari `APP_URL` di `.env` (atau input manual), install `certbot` + `python3-certbot-nginx`, lalu `certbot --nginx` non-interaktif + redirect HTTP→HTTPS. Auto-renewal sudah diatur Certbot otomatis.

### 6. Update Panel
`down` → backup otomatis → download rilis terbaru → extract timpa → `composer install` → `migrate` → clear cache → `queue:restart` → `up`.

### 7. Uninstall Panel
**Konfirmasi 2x** (termasuk ketik `HAPUS`). Menghapus: service `pteroq`, cron, vhost Nginx, folder `/var/www/pterodactyl`, dan **opsional** drop database. PHP/MariaDB/Redis/Nginx tidak ikut dihapus.

### 8. Uninstall Wings
Stop + hapus service, binary, dan (opsional) folder `/etc/pterodactyl` serta Docker-nya.

---

## 🎨 Catatan Tema

**Cara dapat URL ZIP tema:**
1. Cari tema Pterodactyl yang kamu suka (misalnya di GitHub).
2. Buka halaman **Releases** repo tema itu → klik kanan file `.zip`-nya → **Copy link**.
3. Tempel link itu saat menu [3] meminta URL.

**Contoh alur:**
```
Menu [3] → tempel URL ZIP → panel maintenance → backup otomatis
→ extract → clear cache → panel nyala lagi dengan tampilan baru
```

**Kalau panel error setelah ganti tema**, restore dari backup otomatis:
```bash
tar -xzf /root/pterodactyl-backup-YYYYMMDD-HHMMSS.tar.gz -C /
chown -R www-data:www-data /var/www/pterodactyl
```

> Catatan: tidak semua tema cocok dengan semua versi panel. Selalu cek deskripsi tema — versi panel yang didukung harus sama dengan versimu. Backup otomatis di script ini adalah jaring pengamanmu.

---

## 🧹 Catatan Uninstall

- Uninstall panel **tidak** menghapus PHP/MariaDB/Redis/Nginx/Docker (mungkin dipakai hal lain).
- File backup tema & panel di `/root/pterodactyl-backup-*.tar.gz` **tidak** ikut terhapus — hapus manual kalau sudah tidak perlu.
- Setelah uninstall panel, sertifikat SSL (Certbot) tetap ada — revoke/hapus manual via `certbot delete` bila perlu.

---

## ⚠️ Disclaimer

- Script ini untuk **VPS milikmu sendiri**. Jalankan hanya di server fresh Ubuntu.
- Selalu baca script sebelum menjalankan `curl | bash` dari internet — termasuk script ini.
- Pembuat tidak bertanggung jawab atas kehilangan data. **Backup dulu** sebelum install/update/uninstall (script sudah membuat backup otomatis di langkah berisiko, tapi backup manual tambahan tidak pernah salah).
- Pterodactyl, Wings, Docker, dan Let's Encrypt adalah milik pengembang masing-masing.
