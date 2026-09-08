# Docker PHP

Production-ready Docker PHP-FPM runtime for PHP 7.4, 8.3, 8.4, and 8.5 applications.

Repository ini menyediakan standar deployment PHP-FPM berbasis Docker untuk aplikasi web production dengan **Nginx sebagai web server pada host** dan **MariaDB sebagai database pada host**.

Fokus utama project ini adalah:

* Standardisasi deployment PHP-FPM
* Dukungan beberapa versi PHP dalam satu server
* Isolasi container per aplikasi
* Read-only application source
* Pemisahan directory writable
* PHP-FPM menggunakan Unix socket
* Integrasi dengan Nginx
* Docker container hardening
* Deployment aplikasi Laravel, CodeIgniter 4, dan PHP generic

---

## Architecture

```text
                         PRODUCTION SERVER
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│                           NGINX                             │
│                             │                               │
│                             │ Unix Socket                   │
│                             ▼                               │
│                      /run/php/*.sock                        │
│                             │                               │
│              ┌──────────────┼──────────────┐                │
│              │              │              │                │
│              ▼              ▼              ▼                │
│          PHP-FPM        PHP-FPM        PHP-FPM              │
│          Container      Container      Container            │
│                                                             │
│          PHP 7.4        PHP 8.3        PHP 8.5              │
│                                                             │
│              │              │              │                │
│              └──────────────┼──────────────┘                │
│                             │                               │
│                             │ TCP                           │
│                             ▼                               │
│                          MariaDB                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Setiap aplikasi berjalan pada container PHP-FPM tersendiri.

Contoh:

```text
Application A → PHP 7.4
Application B → PHP 8.3
Application C → PHP 8.4
Application D → PHP 8.5
```

Dengan pendekatan ini, satu server dapat menjalankan aplikasi dengan kebutuhan versi PHP yang berbeda.

---

# Supported PHP Versions

| PHP Version | Docker Image    | Use Case           |
| ----------- | --------------- | ------------------ |
| PHP 7.4     | `local/php:7.4` | Legacy application |
| PHP 8.3     | `local/php:8.3` | Production         |
| PHP 8.4     | `local/php:8.4` | Production         |
| PHP 8.5     | `local/php:8.5` | Production         |

> **Note:** PHP 7.4 sudah End-of-Life dan sebaiknya hanya digunakan untuk aplikasi legacy yang belum dapat dimigrasikan.

---

# Directory Structure

Repository ini menggunakan struktur standar:

```text
/opt/
├── docker-php/
│   ├── README.md
│   ├── create-php-app.sh
│   │
│   ├── images/
│   │   ├── 7.4/
│   │   │   ├── Dockerfile
│   │   │   └── php.ini
│   │   │
│   │   ├── 8.3/
│   │   │   ├── Dockerfile
│   │   │   └── php.ini
│   │   │
│   │   ├── 8.4/
│   │   │   ├── Dockerfile
│   │   │   └── php.ini
│   │   │
│   │   └── 8.5/
│   │       ├── Dockerfile
│   │       └── php.ini
│   │
│   └── templates/
│       ├── docker/
│       └── nginx/
│
└── docker-apps/
    ├── myapp/
    ├── myapp2/
    └── myapp3/


/var/
└── apps/
    ├── myapp/
    ├── myapp2/
    └── myapp3/
```

### `/opt/docker-php`

Repository utama yang berisi:

* Dockerfile PHP
* PHP configuration
* Application generator
* Docker template
* Nginx template
* Dokumentasi

### `/opt/docker-apps`

Berisi konfigurasi Docker untuk setiap aplikasi.

Contoh:

```text
/opt/docker-apps/myapp/
├── docker-compose.yml
├── zz-custom.conf
└── nginx/
    └── myapp.conf
```

### `/var/apps`

Berisi source code dan data aplikasi.

Contoh:

```text
/var/apps/myapp/
├── htdocs/
├── data/
│   └── writable/
├── logs/
└── backup/
```

---

# Application Architecture

Setiap aplikasi mempunyai struktur terisolasi:

```text
/opt/docker-apps/myapp/
└── docker-compose.yml

/var/apps/myapp/
├── htdocs/
├── data/
│   └── writable/
├── logs/
└── backup/
```

Pembagian fungsi:

| Directory        | Fungsi                | Access     |
| ---------------- | --------------------- | ---------- |
| `htdocs/`        | Source code aplikasi  | Read Only  |
| `data/writable/` | Data runtime aplikasi | Read/Write |
| `logs/`          | Log aplikasi          | Read/Write |
| `backup/`        | Backup aplikasi       | Read/Write |

---

# Supported Frameworks

Generator mendukung tiga tipe aplikasi:

```text
laravel
ci
generic
```

## Laravel

```bash
./create-php-app.sh myapp 8.3 laravel
```

Writable directory:

```text
/var/apps/myapp/data/writable/
├── storage/
│   ├── app/
│   ├── framework/
│   │   ├── cache/
│   │   ├── sessions/
│   │   └── views/
│   └── logs/
│
└── bootstrap-cache/
```

---

## CodeIgniter 4

```bash
./create-php-app.sh myapp 8.4 ci
```

Writable directory:

```text
/var/apps/myapp/data/writable/
├── cache/
├── logs/
├── session/
└── uploads/
```

Directory tersebut akan digunakan sebagai:

```text
/var/www/html/writable
```

---

## Generic PHP

Untuk aplikasi PHP biasa:

```bash
./create-php-app.sh myapp 8.5 generic
```

Writable directory:

```text
/var/apps/myapp/data/writable/
├── cache/
├── logs/
├── session/
└── uploads/
```

---

# Docker Security

Container dirancang dengan beberapa lapisan hardening.

## Read-Only Root Filesystem

```yaml
read_only: true
```

Filesystem utama container dibuat read-only.

---

## Read-Only Application Source

Source code:

```yaml
volumes:
  - /var/apps/myapp/htdocs:/var/www/html:ro
```

Dengan demikian proses PHP tidak dapat menulis langsung ke source code.

---

## Writable Directory Terpisah

Directory yang memang membutuhkan write dipisahkan dari source code.

Contoh Laravel:

```yaml
volumes:
  - /var/apps/myapp/data/writable/storage:/var/www/html/storage:rw
```

---

## No New Privileges

```yaml
security_opt:
  - no-new-privileges:true
```

Mencegah proses dalam container memperoleh privilege tambahan.

---

## Temporary Filesystem

```yaml
tmpfs:
  - /tmp:rw,noexec,nosuid,size=128m
```

Directory `/tmp` menggunakan filesystem sementara dengan:

* `noexec`
* `nosuid`
* size limit

---

## PID Limit

```yaml
pids_limit: 100
```

Membatasi jumlah process/thread yang dapat dibuat container.

---

## Resource Limits

Default resource limit:

```yaml
deploy:
  resources:
    limits:
      cpus: "2.0"
      memory: 1G
    reservations:
      cpus: "0.25"
      memory: 128M
```

Nilai dapat disesuaikan dengan kebutuhan aplikasi.

---

# Container Capabilities

Repository ini **tidak menggunakan**:

```yaml
cap_drop:
  - ALL
```

Hardening dilakukan menggunakan mekanisme yang lebih praktis dan kompatibel seperti:

```text
read_only
no-new-privileges
tmpfs
pids_limit
resource limits
read-only source code
isolated writable directories
```

---

# PHP-FPM

PHP-FPM berjalan menggunakan Unix socket.

Contoh:

```text
/run/php/myapp.sock
```

Nginx akan meneruskan request PHP melalui socket tersebut:

```nginx
fastcgi_pass unix:/run/php/myapp.sock;
```

Tidak diperlukan port TCP khusus untuk masing-masing PHP-FPM container.

Contoh:

```text
/run/php/
├── myapp.sock
├── myapp2.sock
└── myapp3.sock
```

Keuntungan:

* Tidak membuka PHP-FPM ke jaringan.
* Mengurangi attack surface.
* Tidak membutuhkan port `9001`, `9002`, `9003`, dan seterusnya.
* Konfigurasi multi-PHP lebih sederhana.

---

# Nginx

Nginx berjalan langsung pada host.

Virtual host masing-masing aplikasi dibuat di:

```text
/etc/nginx/sites-available/
```

dan di-enable melalui:

```text
/etc/nginx/sites-enabled/
```

Contoh:

```text
/etc/nginx/sites-available/myapp.conf
/etc/nginx/sites-enabled/myapp.conf
```

Document root untuk Laravel dan CodeIgniter 4:

```text
/var/apps/myapp/htdocs/public
```

Untuk aplikasi PHP generic:

```text
/var/apps/myapp/htdocs
```

---

# MariaDB

MariaDB tetap berjalan pada host.

Arsitektur:

```text
PHP-FPM Container
        │
        │ TCP
        ▼
     MariaDB
```

Aplikasi menggunakan konfigurasi database melalui environment variable.

Contoh:

```env
DB_HOST=172.17.0.1
DB_PORT=3306
DB_DATABASE=myapp
DB_USERNAME=myapp
DB_PASSWORD=********
```

`DB_HOST` harus disesuaikan dengan konfigurasi jaringan Docker pada server.

---

# Installation

Buat directory `/opt` jika belum tersedia:

```bash
mkdir -p /opt
```

Clone repository:

```bash
cd /opt

git clone https://github.com/USERNAME/docker-php.git docker-php
```

Repository akan tersedia di:

```text
/opt/docker-php
```

Masuk ke repository:

```bash
cd /opt/docker-php
```

Berikan permission executable:

```bash
chmod +x create-php-app.sh
```

---

# Build PHP Images

Build seluruh PHP image:

```bash
cd /opt/docker-php/images

for version in 7.4 8.3 8.4 8.5; do
    docker build \
        -t local/php:${version} \
        ${version}
done
```

Atau build satu versi:

```bash
docker build \
    -t local/php:8.3 \
    8.3
```

Verifikasi:

```bash
docker images | grep 'local/php'
```

Expected:

```text
local/php    7.4
local/php    8.3
local/php    8.4
local/php    8.5
```

---

# Create Application

Syntax:

```bash
./create-php-app.sh <application-name> <php-version> <framework>
```

Framework yang tersedia:

```text
laravel
ci
generic
```

Contoh Laravel:

```bash
./create-php-app.sh myapp 8.3 laravel
```

CodeIgniter 4:

```bash
./create-php-app.sh myapp2 8.4 ci
```

PHP generic:

```bash
./create-php-app.sh myapp3 8.5 generic
```

Legacy application:

```bash
./create-php-app.sh legacy-app 7.4 generic
```

---

# Generated Configuration

Setelah:

```bash
./create-php-app.sh myapp 8.3 laravel
```

generator akan membuat:

```text
/opt/docker-apps/myapp/
├── docker-compose.yml
├── zz-custom.conf
└── nginx/
    └── myapp.conf
```

dan:

```text
/var/apps/myapp/
├── htdocs/
├── data/
│   └── writable/
├── logs/
└── backup/
```

Virtual host Nginx juga akan dibuat:

```text
/etc/nginx/sites-available/myapp.conf
/etc/nginx/sites-enabled/myapp.conf
```

---

# Start Application

Masuk ke konfigurasi Docker:

```bash
cd /opt/docker-apps/myapp
```

Start container:

```bash
docker compose up -d
```

Check:

```bash
docker compose ps
```

Logs:

```bash
docker compose logs -f
```

---

# Verify PHP

Check PHP version:

```bash
docker exec myapp-php php -v
```

Check PHP modules:

```bash
docker exec myapp-php php -m
```

Check PHP-FPM configuration:

```bash
docker exec myapp-php php-fpm -tt
```

---

# Nginx Validation

Sebelum reload:

```bash
nginx -t
```

Jika valid:

```bash
systemctl reload nginx
```

---

# Container Management

Start:

```bash
docker compose up -d
```

Stop:

```bash
docker compose down
```

Restart:

```bash
docker compose restart
```

View logs:

```bash
docker compose logs -f
```

View container:

```bash
docker compose ps
```

Masuk ke container:

```bash
docker exec -it myapp-php bash
```

---

# Laravel Deployment

Source code Laravel berada di:

```text
/var/apps/myapp/htdocs/
```

Document root:

```text
/var/apps/myapp/htdocs/public
```

Writable directory:

```text
/var/apps/myapp/data/writable/
```

Konsep mapping:

```text
Laravel
   │
   ├── storage
   │      │
   │      └── /var/apps/myapp/data/writable/storage
   │
   └── bootstrap/cache
          │
          └── /var/apps/myapp/data/writable/bootstrap-cache
```

Source code tetap read-only.

---

# CodeIgniter 4 Deployment

Source code:

```text
/var/apps/myapp/htdocs/
```

Document root:

```text
/var/apps/myapp/htdocs/public
```

Writable directory:

```text
/var/apps/myapp/data/writable/
```

Mapping:

```text
/var/apps/myapp/data/writable/
        │
        ▼
/var/www/html/writable
```

---

# Generic PHP Deployment

Untuk aplikasi PHP generic:

```text
/var/apps/myapp/
├── htdocs/
├── data/
│   └── writable/
├── logs/
└── backup/
```

Document root:

```text
/var/apps/myapp/htdocs
```

Writable application data:

```text
/var/apps/myapp/data/writable
```

---

# Backup

Directory backup aplikasi disediakan pada:

```text
/var/apps/myapp/backup/
```

Directory ini dapat digunakan untuk:

* Database backup
* Application backup
* Configuration backup
* Deployment backup

Backup sebaiknya dikelola menggunakan sistem backup terpisah dan tidak hanya disimpan pada server production.

---

# Application Isolation

Setiap aplikasi mendapatkan:

```text
Container
Docker network
PHP-FPM socket
Docker Compose
Writable directory
Nginx virtual host
Application log
Backup directory
```

Contoh:

```text
myapp
│
├── myapp-php
├── myapp-network
├── /run/php/myapp.sock
└── /var/apps/myapp/


myapp2
│
├── myapp2-php
├── myapp2-network
├── /run/php/myapp2.sock
└── /var/apps/myapp2/
```

Dengan demikian konfigurasi masing-masing aplikasi tetap terisolasi.

---

# Recommended Production Layout

```text
/opt/
│
├── docker-php/
│   ├── README.md
│   ├── create-php-app.sh
│   ├── images/
│   │   ├── 7.4/
│   │   ├── 8.3/
│   │   ├── 8.4/
│   │   └── 8.5/
│   └── templates/
│
└── docker-apps/
    ├── myapp/
    ├── myapp2/
    └── myapp3/


/var/
└── apps/
    ├── myapp/
    │   ├── htdocs/
    │   ├── data/
    │   ├── logs/
    │   └── backup/
    │
    ├── myapp2/
    │   ├── htdocs/
    │   ├── data/
    │   ├── logs/
    │   └── backup/
    │
    └── myapp3/
        ├── htdocs/
        ├── data/
        ├── logs/
        └── backup/
```

---

# Upgrade PHP

Aplikasi dapat menggunakan versi PHP berbeda tanpa memengaruhi aplikasi lainnya.

Contoh:

```text
myapp  → PHP 8.3
myapp2 → PHP 8.4
myapp3 → PHP 8.5
```

Versi PHP aplikasi ditentukan pada:

```text
/opt/docker-apps/myapp/docker-compose.yml
```

Contoh:

```yaml
image: local/php:8.4
```

Setelah perubahan:

```bash
cd /opt/docker-apps/myapp

docker compose up -d --force-recreate
```

---

# Security Recommendations

Untuk deployment production, disarankan:

* Gunakan HTTPS.
* Gunakan firewall.
* Batasi akses database.
* Jangan expose PHP-FPM ke internet.
* Gunakan Nginx sebagai web server.
* Gunakan WAF untuk aplikasi yang membutuhkan perlindungan tambahan.
* Pisahkan source code dan writable directory.
* Lakukan backup secara berkala.
* Monitor container dan host.
* Gunakan logging terpusat.
* Update PHP image secara berkala.
* Migrasikan aplikasi PHP 7.4 ke versi PHP yang masih didukung.

---

# Project Goals

Project `docker-php` bertujuan menjadi standar deployment PHP-FPM untuk server yang menjalankan banyak aplikasi web.

Target utama:

```text
Consistency
     │
     ▼
Isolation
     │
     ▼
Security
     │
     ▼
Maintainability
     │
     ▼
Scalability
```

---

# License

Repository ini merupakan infrastructure dan deployment template.

Lisensi dapat ditentukan sesuai kebutuhan organisasi atau project yang menggunakan repository ini.

---

# Maintainer

**NR Technology**

Infrastructure, DevOps, Cybersecurity, and Web Server Engineering.
