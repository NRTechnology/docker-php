# Docker PHP

Production-ready PHP-FPM Docker deployment standard for multi-application production servers.

Repository ini menyediakan standar deployment PHP-FPM berbasis Docker dengan:

- Nginx sebagai web server pada host
- MariaDB sebagai database standar pada host
- MySQL tetap didukung
- PHP-FPM berjalan di dalam container
- Isolasi container per aplikasi
- Application source mounted read-only
- Writable runtime directory dipisahkan dari source
- PHP-FPM menggunakan Unix socket
- PHP ke database menggunakan TCP
- Docker container hardening
- Dukungan Laravel, CodeIgniter 4, dan Generic PHP
- Dukungan multiple PHP versions dalam satu server

**Current Release: `1.1.0`**

---

# Architecture

```text
                         PRODUCTION SERVER

┌───────────────────────────────────────────────────────────────┐
│                                                               │
│                           NGINX                               │
│                         Host Server                           │
│                              │                                │
│                              │ Unix Socket                    │
│                              ▼                                │
│                     /run/php/*.sock                           │
│                              │                                │
│              ┌───────────────┼───────────────┐                │
│              │               │               │                │
│              ▼               ▼               ▼                │
│          PHP-FPM         PHP-FPM         PHP-FPM              │
│          Container       Container       Container             │
│                                                               │
│          PHP 8.3         PHP 8.4         PHP 8.5              │
│              │               │               │                │
│              └───────────────┼───────────────┘                │
│                              │                                │
│                              │ TCP :3306                      │
│                              ▼                                │
│                       MariaDB / MySQL                         │
│                          Host Server                           │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

Setiap aplikasi memiliki:

- PHP-FPM container sendiri
- Docker bridge network sendiri
- PHP-FPM Unix socket sendiri
- Docker Compose configuration sendiri
- Nginx virtual host sendiri
- Writable runtime directory sendiri
- Application log directory sendiri
- Backup directory sendiri
- Database dan database user sendiri

Dengan arsitektur ini, satu server dapat menjalankan beberapa aplikasi dengan versi PHP yang berbeda.

Contoh:

```text
myapp   → PHP 8.3
myapp2  → PHP 8.4
myapp3  → PHP 8.5
legacy  → PHP 7.4
```

---

# Supported PHP Versions

| PHP Version | Docker Image | Use |
|---|---|---|
| PHP 7.4 | `local/php:7.4` | Legacy application |
| PHP 8.2 | `local/php:8.2` | Application compatible with PHP 8.2 |
| PHP 8.3 | `local/php:8.3` | Production |
| PHP 8.4 | `local/php:8.4` | Production |
| PHP 8.5 | `local/php:8.5` | Production |

> **Note:** PHP 7.4 sudah End-of-Life dan hanya dipertahankan untuk kompatibilitas aplikasi legacy. Jangan gunakan PHP 7.4 untuk aplikasi baru.

Versi PHP yang digunakan aplikasi harus sesuai dengan requirement aplikasi dan dependency lock file.

---

# Supported Frameworks

Application generator mendukung:

```text
laravel
ci
generic
```

## Laravel

Document root:

```text
/var/apps/<application-name>/htdocs/public
```

Laravel menggunakan writable directory yang dipisahkan secara spesifik dari source code:

```text
/var/apps/<application-name>/data/

├── storage-app/
├── storage-framework/
├── storage-logs/
└── bootstrap-cache/
```

Mapping ke container:

```text
data/storage-app
        ↓
/var/www/html/storage/app

data/storage-framework
        ↓
/var/www/html/storage/framework

data/storage-logs
        ↓
/var/www/html/storage/logs

data/bootstrap-cache
        ↓
/var/www/html/bootstrap/cache
```

Application source tetap di-mount read-only.

```text
/var/apps/<application-name>/htdocs
        ↓
/var/www/html:ro
```

### Laravel Vendor

Generator **tidak membuat `data/vendor` dan tidak melakukan mount `data/vendor`**.

Dependency Laravel berada pada:

```text
/var/apps/<application-name>/htdocs/vendor
```

Direktori `vendor` harus tersedia sebagai bagian dari deployment application source/deployment artifact sebelum Laravel dijalankan.

Contoh struktur:

```text
/var/apps/<application-name>/htdocs/

├── app/
├── artisan
├── bootstrap/
├── composer.json
├── composer.lock
├── config/
├── public/
├── resources/
├── routes/
├── storage/
└── vendor/
```

### Composer

Composer **tidak termasuk dalam PHP-FPM runtime image**.

Untuk Laravel, generator menyiapkan Composer secara terpisah:

```text
/var/apps/<application-name>/composer/composer
```

Composer binary kemudian di-mount read-only ke container:

```text
/var/apps/<application-name>/composer/composer
        ↓
/usr/local/bin/composer:ro
```

Composer digunakan untuk proses dependency management/deployment, bukan sebagai komponen permanen yang dibangun ke dalam PHP-FPM image.

> **Catatan:** Jika application source menggunakan mount read-only, `composer install` tidak dapat membuat `vendor/` langsung di dalam `/var/www/html`. Dependency harus disiapkan melalui proses deployment yang sesuai sebelum runtime production digunakan.

PHP execution diblokir pada Laravel writable directories.

## CodeIgniter 4

Document root:

```text
/var/apps/<application-name>/htdocs/public
```

Writable directory:

```text
/var/apps/<application-name>/data/writable/

├── cache/
├── logs/
├── session/
└── uploads/
```

Mapping ke container:

```text
/var/apps/<application-name>/data/writable
        ↓
/var/www/html/writable
```

PHP execution diblokir pada writable directory.

CodeIgniter 4 tidak menggunakan workflow Composer Laravel yang disediakan oleh generator.

## Generic PHP

Untuk aplikasi PHP custom atau legacy:

Document root:

```text
/var/apps/<application-name>/htdocs
```

Writable directory:

```text
/var/apps/<application-name>/data/writable/

├── cache/
├── logs/
├── session/
└── uploads/
```

Mapping ke container:

```text
/var/apps/<application-name>/data/writable
        ↓
/var/www/html/data
```

PHP execution diblokir pada writable data directory.

---

# Repository Structure

```text
/opt/docker-php/

├── README.md
├── CHANGELOG.md
├── create-php-app.sh
├── .gitignore
│
├── images/
│   ├── 7.4/
│   │   ├── Dockerfile
│   │   └── php.ini
│   ├── 8.2/
│   │   ├── Dockerfile
│   │   └── php.ini
│   ├── 8.3/
│   │   ├── Dockerfile
│   │   └── php.ini
│   ├── 8.4/
│   │   ├── Dockerfile
│   │   └── php.ini
│   └── 8.5/
│       ├── Dockerfile
│       └── php.ini
│
├── templates/
│   ├── docker/
│   │   └── docker-compose.yml
│   ├── nginx/
│   │   └── app.conf
│   └── php-fpm/
│       └── zz-custom.conf
│
└── scripts/
    ├── build-image.sh
    ├── check-requirements.sh
    └── test-images.sh
```

---

# Production Directory Layout

```text
/opt/

├── docker-php/
└── docker-apps/

/var/

└── apps/
```

## `/opt/docker-php`

Repository utama yang berisi:

- PHP Dockerfile
- PHP configuration
- PHP-FPM configuration
- Application generator
- Docker Compose template
- Nginx template
- Requirement checker
- Image build script
- Image test script
- Documentation

## `/opt/docker-apps`

Berisi konfigurasi deployment Docker untuk masing-masing aplikasi.

Contoh:

```text
/opt/docker-apps/myapp/

├── docker-compose.yml
├── zz-custom.conf
└── db-credentials.env
```

Database credentials dibuat otomatis oleh `create-php-app.sh`.

## `/var/apps`

Berisi source code dan runtime data aplikasi.

Untuk Laravel:

```text
/var/apps/myapp/

├── htdocs/
│   └── vendor/
├── data/
│   ├── storage-app/
│   ├── storage-framework/
│   ├── storage-logs/
│   └── bootstrap-cache/
├── composer/
│   └── composer
├── logs/
└── backup/
```

Untuk CodeIgniter 4 dan Generic PHP:

```text
/var/apps/myapp/

├── htdocs/
├── data/
│   └── writable/
├── logs/
└── backup/
```

| Directory | Fungsi | Access |
|---|---|---|
| `htdocs/` | Application source | Read Only di container |
| `data/` | Runtime data terpisah | Read/Write sesuai kebutuhan |
| `composer/` | Composer binary untuk Laravel | Read Only di container |
| `logs/` | Application logs | Read/Write |
| `backup/` | Application/database backup | Read/Write |

---

# Installation

## 1. Prepare Server

Repository dirancang untuk server Linux production dengan:

- Nginx
- Docker Engine
- Docker Compose Plugin
- MariaDB

MariaDB merupakan database standar project.

MySQL tetap dapat digunakan apabila server telah menggunakan MySQL.

## 2. Clone Repository

```bash
mkdir -p /opt
cd /opt

git clone https://github.com/NRTechnology/docker-php.git docker-php

cd /opt/docker-php
```

## 3. Make Scripts Executable

```bash
chmod +x create-php-app.sh
chmod +x scripts/*.sh
```

Verify:

```bash
ls -lah create-php-app.sh scripts/
```

---

# Install Requirements

Requirement installation dilakukan menggunakan:

```text
scripts/check-requirements.sh
```

Script digunakan untuk memeriksa dan, jika diperlukan, memasang komponen dasar:

- Nginx
- Docker Engine
- Docker Compose Plugin
- MariaDB Server
- MariaDB Client

Jalankan:

```bash
cd /opt/docker-php

./scripts/check-requirements.sh
```

Verifikasi:

```bash
nginx -v
docker --version
docker compose version
mariadb --version
```

Jika menggunakan MySQL sebagai database server, pastikan MySQL client tersedia:

```bash
mysql --version
```

Verifikasi service:

```bash
systemctl status nginx
systemctl status docker
systemctl status mariadb
```

Jika server menggunakan MySQL:

```bash
systemctl status mysql
```

> **Important:** Script requirement tidak secara otomatis mengganti konfigurasi production yang sudah ada.

Script juga tidak secara otomatis mengubah:

- Firewall
- Database network binding
- Docker daemon configuration
- DNS
- TLS/SSL
- Reverse proxy
- Production-specific network policy

## MariaDB Security

`mariadb-secure-installation` tidak dijalankan otomatis karena merupakan proses interaktif.

Setelah instalasi MariaDB, administrator disarankan melakukan hardening secara manual.

---

# Database Standard

Database standar project adalah:

```text
MariaDB
```

Arsitektur:

```text
PHP-FPM Container
       │
       │ TCP :3306
       ▼
    MariaDB
    Host OS
```

MySQL tetap didukung:

```text
PHP-FPM Container
       │
       │ TCP :3306
       ▼
     MySQL
    Host OS
```

Application generator mendeteksi database client yang tersedia.

Prioritas:

```text
mariadb
   ↓
mysql
```

Jika `mariadb` tersedia, client tersebut digunakan.

Jika tidak tersedia tetapi `mysql` tersedia, client MySQL digunakan.

Generator tidak mengubah database server yang sudah berjalan hanya karena client yang tersedia berbeda.

---

# Database User Security

Setiap aplikasi mendapatkan database dan database user sendiri.

Generator:

- membuat database
- membuat database user
- menghasilkan password acak
- memberikan privilege hanya ke database aplikasi
- menyimpan credentials dalam file terpisah
- membatasi host user berdasarkan subnet Docker aktual

Contoh:

```text
Docker subnet:

172.24.0.0/16
```

Database user dapat dibatasi menjadi:

```text
'myapp'@'172.24.%'
```

bukan:

```text
'myapp'@'%'
```

Host restriction dibuat berdasarkan subnet Docker aktual, bukan hard-coded pada satu range tertentu.

---

# Build PHP Images

Image PHP harus tersedia sebelum membuat application environment.

Build script:

```text
scripts/build-image.sh
```

## Interactive Mode

```bash
cd /opt/docker-php

./scripts/build-image.sh
```

Menu menyediakan pilihan:

```text
1. PHP 7.4
2. PHP 8.2
3. PHP 8.3
4. PHP 8.4
5. PHP 8.5
6. Build All
7. Show Images
0. Exit
```

## Build Specific Version

```bash
./scripts/build-image.sh 7.4
./scripts/build-image.sh 8.2
./scripts/build-image.sh 8.3
./scripts/build-image.sh 8.4
./scripts/build-image.sh 8.5
```

## Build All Images

```bash
./scripts/build-image.sh all
```

Image yang dihasilkan:

```text
local/php:7.4
local/php:8.2
local/php:8.3
local/php:8.4
local/php:8.5
```

---

# Verify PHP Images

Image dapat diverifikasi menggunakan:

```bash
./scripts/test-images.sh
```

Pemeriksaan meliputi:

- PHP version
- PHP modules
- PHP configuration
- PHP-FPM configuration

Manual verification:

```bash
docker run --rm local/php:8.4 php -v
docker run --rm local/php:8.4 php -m
docker run --rm local/php:8.4 php-fpm -t
```

---

# Composer

Composer **tidak termasuk dalam PHP-FPM runtime image**.

Hal ini disengaja agar image runtime tetap fokus pada:

```text
PHP
PHP-FPM
Required PHP extensions
Runtime configuration
```

dan tidak membawa dependency-management tool yang tidak diperlukan oleh runtime aplikasi.

Untuk Laravel, `create-php-app.sh` menyiapkan Composer secara terpisah.

Lokasi host:

```text
/var/apps/<application-name>/composer/composer
```

Lokasi container:

```text
/usr/local/bin/composer
```

Mount:

```yaml
- /var/apps/<application-name>/composer/composer:/usr/local/bin/composer:ro
```

Composer binary diambil dari Composer image secara terpisah dan tidak dibangun ke dalam image PHP-FPM.

Verifikasi:

```bash
docker compose exec php composer --version
```

Composer hanya relevan untuk workflow aplikasi yang memang menggunakan Composer. CI4 dan Generic PHP tidak menggunakan workflow Composer Laravel yang dibuat oleh generator.

---

# Create Application

Application generator:

```text
create-php-app.sh
```

Syntax:

```bash
./create-php-app.sh <application-name> <php-version> <framework> <domain-name>
```

Supported framework:

```text
laravel
ci
generic
```

Supported PHP versions:

```text
7.4
8.2
8.3
8.4
8.5
```

## Laravel

```bash
./create-php-app.sh myapp 8.3 laravel myapp.example.go.id
```

## CodeIgniter 4

```bash
./create-php-app.sh myapp2 8.4 ci myapp2.example.go.id
```

## Generic PHP

```bash
./create-php-app.sh myapp3 8.5 generic myapp3.example.go.id
```

## Legacy Application

```bash
./create-php-app.sh legacy-app 7.4 generic legacy.example.go.id
```

---

# What `create-php-app.sh` Does

Generator melakukan beberapa proses secara otomatis.

## 1. Validate Input

Memvalidasi:

- Application name
- Domain name
- PHP version
- Framework
- Docker
- Docker Compose
- Nginx
- PHP image

## 2. Create Application Directories

Struktur dasar:

```text
/var/apps/myapp/
```

Untuk Laravel:

```text
/var/apps/myapp/

├── htdocs/
├── data/
│   ├── storage-app/
│   ├── storage-framework/
│   ├── storage-logs/
│   └── bootstrap-cache/
├── composer/
├── logs/
└── backup/
```

Untuk CodeIgniter 4 dan Generic PHP:

```text
/var/apps/myapp/

├── htdocs/
├── data/
│   └── writable/
├── logs/
└── backup/
```

Generator **tidak membuat `data/vendor`**.

## 3. Prepare Composer for Laravel

Untuk aplikasi Laravel, generator memastikan Composer tersedia dan menyiapkan binary secara terpisah.

Composer disimpan pada:

```text
/var/apps/myapp/composer/composer
```

Binary tersebut kemudian di-mount read-only ke container.

Composer tidak dimasukkan ke image:

```text
local/php:<version>
```

## 4. Create Docker Network

Setiap aplikasi mendapatkan network sendiri:

```text
myapp-network
```

Network menggunakan:

```yaml
driver: bridge
```

Subnet dan gateway Docker dideteksi secara dinamis setelah network dibuat.

## 5. Create Database

Generator secara otomatis membuat database:

```text
myapp
```

Database menggunakan:

```text
utf8mb4
utf8mb4_unicode_ci
```

## 6. Create Database User

Generator membuat user:

```text
myapp
```

User hanya diberikan privilege terhadap database aplikasi:

```text
myapp.*
```

## 7. Generate Database Password

Password database dibuat otomatis menggunakan random generator:

```text
openssl rand -hex
```

atau fallback:

```text
/dev/urandom
```

Password tidak menggunakan password default.

## 8. Restrict Database User Host

Host database user ditentukan berdasarkan subnet Docker aktual.

Contoh:

```text
Docker subnet:

172.24.0.0/16
```

Database user dapat dibatasi menjadi:

```text
'myapp'@'172.24.%'
```

Tujuannya menghindari penggunaan:

```text
'myapp'@'%'
```

yang terlalu luas.

## 9. Generate Nginx Configuration

Generator membuat konfigurasi virtual host berdasarkan domain aplikasi.

Konfigurasi ditempatkan pada:

```text
/etc/nginx/sites-available/
```

dan diaktifkan melalui:

```text
/etc/nginx/sites-enabled/
```

## 10. Generate Docker Compose

Generator membuat:

```text
/opt/docker-apps/myapp/docker-compose.yml
```

dan melakukan validasi:

```bash
docker compose config
```

Generator **tidak otomatis menjalankan**:

```bash
docker compose up -d
```

Administrator dapat meninjau konfigurasi terlebih dahulu.

---

# Database Credentials

Credentials disimpan di:

```text
/opt/docker-apps/myapp/db-credentials.env
```

Contoh:

```env
DB_CONNECTION=mysql
DB_HOST=172.24.0.1
DB_PORT=3306
DB_DATABASE=myapp
DB_USERNAME=myapp
DB_PASSWORD=<generated-password>
```

Permission:

```text
0600
```

Owner:

```text
root:root
```

Periksa:

```bash
cat /opt/docker-apps/myapp/db-credentials.env
```

> Jangan memasukkan file `db-credentials.env` ke Git repository.

`DB_CONNECTION=mysql` digunakan karena nama driver database Laravel adalah `mysql`, baik ketika backend database menggunakan MySQL maupun MariaDB.

---

# Generated Docker Configuration

Generator membuat:

```text
/opt/docker-apps/myapp/

├── docker-compose.yml
├── zz-custom.conf
└── db-credentials.env
```

Docker Compose menggunakan:

```yaml
image: local/php:<version>
```

Contoh:

```yaml
image: local/php:8.4
```

Untuk Laravel, konfigurasi juga menyediakan Composer binary secara read-only.

---

# Docker Security

Container menggunakan beberapa lapisan hardening.

## Read-Only Root Filesystem

```yaml
read_only: true
```

## Read-Only Application Source

```yaml
volumes:
  - /var/apps/myapp/htdocs:/var/www/html:ro
```

Source code tidak dapat ditulis langsung oleh PHP-FPM.

## Writable Runtime Directory

Directory yang membutuhkan write dipisahkan dari source.

Laravel:

```text
/var/apps/myapp/data/storage-app
/var/apps/myapp/data/storage-framework
/var/apps/myapp/data/storage-logs
/var/apps/myapp/data/bootstrap-cache
```

Mapping:

```text
storage-app
    ↓
/var/www/html/storage/app

storage-framework
    ↓
/var/www/html/storage/framework

storage-logs
    ↓
/var/www/html/storage/logs

bootstrap-cache
    ↓
/var/www/html/bootstrap/cache
```

CodeIgniter 4:

```text
/var/apps/myapp/data/writable
    ↓
/var/www/html/writable
```

Generic PHP:

```text
/var/apps/myapp/data/writable
    ↓
/var/www/html/data
```

## No New Privileges

```yaml
security_opt:
  - no-new-privileges:true
```

## Temporary Filesystem

```yaml
tmpfs:
  - /tmp:rw,noexec,nosuid,size=128m
```

## Resource Limits

Default:

```yaml
cpus: "2.0"
mem_limit: 1g
pids_limit: 100
```

File descriptor limit:

```yaml
ulimits:
  nofile:
    soft: 65535
    hard: 65535
```

Nilai dapat disesuaikan sesuai kebutuhan aplikasi.

---

# Container Capabilities

Project ini **tidak menggunakan**:

```yaml
cap_drop:
  - ALL
```

Hardening dilakukan menggunakan:

```text
read_only
no-new-privileges
tmpfs
pids_limit
resource limits
read-only source code
isolated writable directories
```

Keputusan ini dibuat berdasarkan pertimbangan kompatibilitas runtime aplikasi di lingkungan production.

---

# PHP-FPM

PHP-FPM menggunakan Unix socket.

Contoh:

```text
/run/php/myapp.sock
```

Nginx:

```nginx
fastcgi_pass unix:/run/php/myapp.sock;
```

Tidak diperlukan port TCP PHP-FPM berbeda untuk setiap aplikasi.

Contoh:

```text
/run/php/

├── myapp.sock
├── myapp2.sock
└── myapp3.sock
```

Keuntungan:

- Tidak membuka PHP-FPM ke jaringan
- Mengurangi attack surface
- Tidak membutuhkan port 9001, 9002, 9003, dan seterusnya
- Memudahkan multi-PHP deployment

Socket menggunakan permission:

```text
owner : www-data
group : www-data
mode  : 0660
```

---

# Nginx

Nginx berjalan langsung pada host.

Virtual host:

```text
/etc/nginx/sites-available/
```

Enabled site:

```text
/etc/nginx/sites-enabled/
```

Contoh:

```text
/etc/nginx/sites-available/myapp.conf
/etc/nginx/sites-enabled/myapp.conf
```

Generator otomatis membuat dan mengaktifkan virtual host setelah konfigurasi valid.

---

# Nginx Security

Generated Nginx configuration menyediakan:

- Security headers
- Hidden-file protection
- Sensitive-file protection
- PHP-FPM Unix socket
- `try_files`
- PHP execution restriction pada writable directories

File sensitif yang diblokir meliputi:

```text
.env
.ini
.log
.sql
.bak
.backup
.old
.orig
.save
.swp
```

PHP execution juga diblokir pada writable directory aplikasi.

---

# Validate Nginx

```bash
nginx -t
```

Jika valid:

```bash
systemctl reload nginx
```

Generator juga menjalankan validasi Nginx selama proses pembuatan application.

---

# Validate Docker Compose

```bash
cd /opt/docker-apps/myapp

docker compose config
```

Generator juga menjalankan validasi `docker compose config` sebelum proses pembuatan selesai.

---

# Start Application

Setelah konfigurasi ditinjau:

```bash
cd /opt/docker-apps/myapp

cat docker-compose.yml

docker compose up -d

docker compose ps
```

Expected:

```text
myapp-php    ...    Up
```

---

# PHP-FPM Logs

```bash
docker compose logs --tail=50 php
```

Follow logs:

```bash
docker compose logs -f php
```

Expected:

```text
fpm is running
ready to handle connections
```

---

# PHP Verification

```bash
docker compose exec php php -v
docker compose exec php php -m
docker compose exec php php-fpm -t
```

Composer untuk Laravel:

```bash
docker compose exec php composer --version
```

---

# Database Connection Verification

Database menggunakan TCP melalui Docker gateway.

Cek gateway network:

```bash
docker network inspect myapp-network \
  --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
```

Contoh:

```text
172.24.0.1
```

Tes koneksi dari PHP:

```bash
docker compose exec php php -r '
$pdo = new PDO(
    "mysql:host=172.24.0.1;dbname=myapp;charset=utf8mb4",
    "myapp",
    "DATABASE_PASSWORD"
);
echo "DATABASE CONNECTION: OK\n";
'
```

Jika berhasil:

```text
DATABASE CONNECTION: OK
```

> Gunakan password dari `db-credentials.env` dan jangan memasukkan credential database ke repository Git.

---

# Laravel Deployment

Source:

```text
/var/apps/myapp/htdocs
```

Pastikan source memiliki:

```text
/var/apps/myapp/htdocs/artisan
/var/apps/myapp/htdocs/composer.json
/var/apps/myapp/htdocs/composer.lock
/var/apps/myapp/htdocs/public
/var/apps/myapp/htdocs/vendor
```

Document root:

```text
/var/apps/myapp/htdocs/public
```

Dependency application disiapkan secara terpisah dari runtime image.

Composer tidak termasuk dalam PHP-FPM runtime image.

Composer tersedia melalui:

```text
/var/apps/myapp/composer/composer
```

dan di-mount read-only ke:

```text
/usr/local/bin/composer
```

`vendor/` berada di source/deployment artifact:

```text
/var/apps/myapp/htdocs/vendor
```

Generator tidak membuat:

```text
/var/apps/myapp/data/vendor
```

Setelah dependency tersedia:

```bash
docker compose exec php php artisan --version
```

> Perintah Artisan hanya dapat dijalankan setelah `vendor/autoload.php` tersedia.

## Laravel Application Key

Jika `.env` berada pada application source yang di-mount read-only, `php artisan key:generate` tidak dapat menulis file `.env` melalui container.

Generate key:

```bash
docker compose exec php php artisan key:generate --show
```

Kemudian masukkan nilai `APP_KEY` ke `.env` pada host.

Contoh:

```env
APP_KEY=base64:<generated-key>
```

Setelah `.env` disiapkan, clear configuration cache bila diperlukan:

```bash
docker compose exec php php artisan config:clear
```

---

# CodeIgniter 4 Deployment

Source:

```text
/var/apps/myapp/htdocs
```

Document root:

```text
/var/apps/myapp/htdocs/public
```

Writable:

```text
/var/apps/myapp/data/writable
```

Mapping:

```text
/var/apps/myapp/data/writable
        ↓
/var/www/html/writable
```

---

# Generic PHP Deployment

Source:

```text
/var/apps/myapp/htdocs
```

Document root:

```text
/var/apps/myapp/htdocs
```

Writable:

```text
/var/apps/myapp/data/writable
```

Mapping:

```text
/var/apps/myapp/data/writable
        ↓
/var/www/html/data
```

---

# Application Isolation

Setiap aplikasi mendapatkan environment terisolasi:

```text
Application

├── PHP-FPM Container
├── Docker Network
├── PHP-FPM Socket
├── Docker Compose
├── Nginx Virtual Host
├── Writable Directory
├── Application Logs
├── Backup Directory
└── Database
```

Contoh:

```text
myapp

├── myapp-php
├── myapp-network
├── /run/php/myapp.sock
└── /var/apps/myapp/

myapp2

├── myapp2-php
├── myapp2-network
├── /run/php/myapp2.sock
└── /var/apps/myapp2/
```

---

# Upgrade PHP

Setiap aplikasi dapat menggunakan versi PHP yang berbeda.

Contoh:

```text
myapp   → PHP 8.3
myapp2  → PHP 8.4
myapp3  → PHP 8.5
```

Versi PHP ditentukan pada:

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

Sebelum upgrade production, pastikan dependency aplikasi kompatibel dengan versi PHP target.

---

# Production Deployment Workflow

```text
              SERVER PREPARATION
                       │
                       ▼
             check-requirements.sh
                       │
                       ▼
                Build PHP Images
                       │
                       ▼
                 test-images.sh
                       │
                       ▼
               create-php-app.sh
                       │
              ┌────────┼────────┐
              │        │        │
              ▼        ▼        ▼
           Network  Database   Nginx
              │        │        │
              └────────┼────────┘
                       │
                       ▼
               Deploy Source Code
                       │
                       ▼
             Prepare Dependencies
                       │
                       ▼
               Review Configuration
                       │
                       ▼
                Start PHP-FPM
                       │
                       ▼
                Validate Nginx
                       │
                       ▼
                Application Test
```

---

# Production Deployment Example

## Step 1 — Install Requirements

```bash
cd /opt/docker-php

./scripts/check-requirements.sh
```

## Step 2 — Build PHP Image

```bash
./scripts/build-image.sh 8.4
```

## Step 3 — Test Image

```bash
./scripts/test-images.sh
```

## Step 4 — Create Application

```bash
./create-php-app.sh myapp 8.4 laravel myapp.example.go.id
```

## Step 5 — Review Configuration

```bash
cd /opt/docker-apps/myapp

cat docker-compose.yml
cat db-credentials.env
```

## Step 6 — Deploy Application Source

Copy or clone source code to:

```text
/var/apps/myapp/htdocs
```

Untuk Laravel, pastikan deployment artifact menyediakan:

```text
vendor/
```

di dalam:

```text
/var/apps/myapp/htdocs/vendor
```

## Step 7 — Prepare Application Dependencies

Dependency Laravel harus tersedia sebelum Artisan dijalankan.

Composer tersedia secara terpisah:

```text
/var/apps/myapp/composer/composer
```

dan tidak termasuk dalam image PHP-FPM.

Jika dependency dipersiapkan pada server deployment, jangan mengandalkan source mount read-only untuk membuat `vendor/` dari dalam runtime container.

## Step 8 — Start PHP-FPM

```bash
cd /opt/docker-apps/myapp

docker compose up -d
```

## Step 9 — Verify

```bash
docker compose ps
docker compose logs --tail=50 php
ls -lah /run/php/myapp.sock
```

## Step 10 — Validate Nginx

```bash
nginx -t
systemctl reload nginx
```

## Step 11 — Test Application

```bash
curl -I http://myapp.example.go.id
```

Untuk production, gunakan HTTPS.

---

# Backup

Backup directory tersedia di:

```text
/var/apps/myapp/backup/
```

Dapat digunakan untuk:

- Database backup
- Application backup
- Configuration backup
- Deployment backup

Backup production sebaiknya tidak hanya disimpan pada server yang sama.

Gunakan sistem backup terpisah untuk perlindungan terhadap:

- Hardware failure
- Disk failure
- Accidental deletion
- Ransomware
- Application compromise

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

Status:

```bash
docker compose ps
```

Logs:

```bash
docker compose logs -f
```

Shell:

```bash
docker compose exec php bash
```

---

# Troubleshooting

## Check Container

```bash
docker compose ps
```

## Check PHP-FPM Logs

```bash
docker compose logs --tail=100 php
```

## Check Socket

```bash
ls -lah /run/php/
```

## Check Nginx

```bash
nginx -t
```

## Check Nginx Error Log

```bash
tail -f /var/log/nginx/myapp.error.log
```

## Check Application Logs

```bash
ls -lah /var/apps/myapp/logs/
```

## Check Composer

Untuk Laravel:

```bash
docker compose exec php composer --version
```

Validasi:

```bash
docker compose exec php composer validate
```

## Check Laravel Vendor

```bash
ls -lah /var/apps/myapp/htdocs/vendor/
```

Pastikan:

```text
/var/apps/myapp/htdocs/vendor/autoload.php
```

tersedia sebelum menjalankan:

```bash
docker compose exec php php artisan --version
```

## Check Database

Cek Docker gateway:

```bash
docker network inspect myapp-network \
  --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
```

Cek database user pada server database:

```sql
SELECT User, Host
FROM mysql.user
WHERE User = 'myapp';
```

---

# Security Recommendations

Untuk deployment production:

- Gunakan HTTPS.
- Gunakan firewall.
- Batasi akses database.
- Jangan expose PHP-FPM ke internet.
- Gunakan Unix socket untuk Nginx → PHP-FPM.
- Gunakan TCP untuk PHP → database.
- Gunakan WAF jika diperlukan.
- Pisahkan source code dan writable directory.
- Jangan menyimpan credential di Git.
- Backup database secara berkala.
- Simpan backup pada lokasi terpisah.
- Monitor host dan container.
- Gunakan centralized logging bila diperlukan.
- Update PHP images secara berkala.
- Migrasikan PHP 7.4 legacy application ke versi yang masih didukung.
- Pastikan dependency Composer sesuai dengan versi PHP.

---

# Important Operational Notes

## Database

MariaDB adalah standar database project.

MySQL tetap didukung.

Generator tidak melakukan migrasi otomatis antara MariaDB dan MySQL.

Existing production database tidak diganti secara otomatis.

## Database Root

Application generator tidak mengubah password atau konfigurasi akun root database.

Root database sebaiknya hanya dapat digunakan dari lokasi administrasi yang dipercaya.

## Database Credentials

File:

```text
/opt/docker-apps/<application-name>/db-credentials.env
```

berisi credential database dan harus dijaga:

```text
root:root
0600
```

Jangan commit file tersebut ke Git.

## Docker Network

Setiap aplikasi mendapatkan network sendiri:

```text
<application-name>-network
```

Network menggunakan:

```text
driver: bridge
```

Generator membaca subnet dan gateway aktual dari Docker setelah network dibuat.

Docker Compose dapat menampilkan warning bahwa network telah dibuat di luar Compose:

```text
a network with name <application-name>-network exists but was not created by compose
```

Ini merupakan konsekuensi dari network yang dibuat oleh generator dan tidak mengubah fungsi container.

## Composer

Composer tidak termasuk dalam PHP-FPM runtime image.

Untuk Laravel:

- Composer binary disiapkan secara terpisah.
- Composer binary berada di `/var/apps/<application-name>/composer/composer`.
- Composer binary di-mount read-only ke `/usr/local/bin/composer`.
- Generator tidak membuat `data/vendor`.
- Generator tidak melakukan mount `data/vendor`.
- `vendor/` berada pada `/var/apps/<application-name>/htdocs/vendor`.
- Dependency harus tersedia sebelum Laravel Artisan dijalankan.

## Application Source

Application source di-mount read-only ke container:

```text
/var/apps/<application-name>/htdocs
        ↓
/var/www/html:ro
```

Directory yang membutuhkan write dipisahkan melalui bind mount read-write.

## Laravel Runtime Directories

Laravel menggunakan empat writable mount:

```text
/var/apps/<application-name>/data/storage-app
        ↓
/var/www/html/storage/app

/var/apps/<application-name>/data/storage-framework
        ↓
/var/www/html/storage/framework

/var/apps/<application-name>/data/storage-logs
        ↓
/var/www/html/storage/logs

/var/apps/<application-name>/data/bootstrap-cache
        ↓
/var/www/html/bootstrap/cache
```

Tidak digunakan:

```text
/var/apps/<application-name>/data/writable/storage
/var/apps/<application-name>/data/vendor
```

---

# Project Goals

Project `docker-php` bertujuan menyediakan standar deployment PHP-FPM untuk server yang menjalankan banyak aplikasi web.

Target:

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

# Release

Current release:

```text
1.1.0
```

Release date:

```text
2026-09-18
```

Major changes in 1.1.0:

- PHP 8.2 support
- MariaDB standardized as database platform
- MySQL compatibility retained
- Automatic database creation
- Automatic database user creation
- Automatic secure database password generation
- Automatic database credentials file
- Dynamic Docker subnet detection
- Dynamic database user host restriction
- Domain-aware application generation
- Improved application generator validation
- Improved password generation
- Laravel, CodeIgniter 4, and Generic PHP deployment templates
- Composer separated from the PHP-FPM runtime image
- Laravel writable directories separated into dedicated runtime mounts

See [CHANGELOG.md](CHANGELOG.md) for complete release history.

---

# License

Repository ini merupakan infrastructure dan deployment template.

Lisensi dapat ditentukan sesuai kebutuhan organisasi atau project yang menggunakan repository ini.

---

# Maintainer

**NR Technology**

Infrastructure, DevOps, Cybersecurity, and Web Server Engineering.

---

# Repository

GitHub:

https://github.com/NRTechnology/docker-php
