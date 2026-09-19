**# Docker PHP**

Production-ready PHP-FPM Docker deployment standard for multi-application production servers.

Repository ini menyediakan standar deployment PHP-FPM berbasis Docker dengan:

\- Nginx sebagai web server pada host

\- MariaDB sebagai database standar pada host

\- MySQL tetap didukung

\- PHP-FPM berjalan di dalam container

\- Isolasi container per aplikasi

\- Read-only application source

\- Writable directory terpisah

\- PHP-FPM menggunakan Unix socket

\- Docker container hardening

\- Dukungan Laravel, CodeIgniter 4, dan Generic PHP

\- Dukungan multiple PHP versions dalam satu server

**\*\*Current Release: `1.1.0`\*\***

**---**

**## Architecture**

```text

                         PRODUCTION SERVER

┌───────────────────────────────────────────────────────────────┐

│                                                               │

│                           NGINX                               │

│                         Host Server                           │

│                              │                                │

│                              │ Unix Socket                    │

│                              ▼                                │

│                     /run/php/\*.sock                           │

│                              │                                │

│             ┌────────────────┼────────────────┐               │

│             │                │                │               │

│             ▼                ▼                ▼               │

│        PHP-FPM            PHP-FPM          PHP-FPM             │

│        Container          Container        Container           │

│                                                               │

│        PHP 8.2            PHP 8.4          PHP 8.5             │

│                                                               │

│             │                │                │               │

│             └────────────────┼────────────────┘               │

│                              │                                │

│                              │ TCP :3306                      │

│                              ▼                                │

│                       MariaDB / MySQL                         │

│                         Host Server                           │

│                                                               │

└───────────────────────────────────────────────────────────────┘

```

Setiap aplikasi memiliki:

\- PHP-FPM container sendiri

\- Docker bridge network sendiri

\- PHP-FPM Unix socket sendiri

\- Docker Compose configuration sendiri

\- Nginx virtual host sendiri

\- Writable directory sendiri

\- Application log directory sendiri

\- Backup directory sendiri

\- Database dan database user sendiri

Dengan arsitektur ini, satu server dapat menjalankan beberapa aplikasi dengan versi PHP yang berbeda.

Contoh:

```text

myapp   → PHP 8.3

myapp2  → PHP 8.4

myapp3  → PHP 8.5

legacy  → PHP 7.4

```

**---**

**# Supported PHP Versions**

\| PHP Version | Docker Image | Recommended Use |

\|---|---|---|

\| PHP 7.4 | `local/php:7.4` | Legacy application |

\| PHP 8.2 | `local/php:8.2` | Application compatible with PHP 8.2 |

\| PHP 8.3 | `local/php:8.3` | Production |

\| PHP 8.4 | `local/php:8.4` | Production |

\| PHP 8.5 | `local/php:8.5` | Production |

\> **\*\*Note:\*\*** PHP 7.4 sudah End-of-Life dan hanya dipertahankan untuk kompatibilitas aplikasi legacy. Jangan gunakan PHP 7.4 untuk aplikasi baru.

Versi PHP yang digunakan aplikasi harus sesuai dengan requirement aplikasi dan dependency lock file.

**---**

**# Supported Frameworks**

Application generator mendukung:

```text

laravel

ci

generic

```

**## Laravel**

Document root:

```text

/var/apps/<application-name>/htdocs/public

```

Writable/runtime directories:

```text

/var/apps/<application-name>/data/

├── vendor/
├── storage-app/
│   └── public/
├── storage-framework/
│   └── views/
├── storage-logs/
└── bootstrap-cache/

```

Mapping ke container:

```text

data/vendor
    ↓
/var/www/html/vendor

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

Laravel source tetap read-only. Directory vendor, storage, dan bootstrap cache dipisahkan sebagai writable mount.

**## CodeIgniter 4**

Document root:

```text

/var/apps/\<application-name>/htdocs/public

```

Writable directory:

```text

/var/apps/\<application-name>/data/writable/

├── cache/

├── logs/

├── session/

└── uploads/

```

Mapping ke container:

```text

/var/apps/\<application-name>/data/writable

        ↓

/var/www/html/writable

```

**## Generic PHP**

Untuk aplikasi PHP custom atau legacy:

Document root:

```text

/var/apps/\<application-name>/htdocs

```

Writable directory:

```text

/var/apps/\<application-name>/data/writable/

├── cache/

├── logs/

├── session/

└── uploads/

```

Mapping ke container:

```text

/var/apps/\<application-name>/data/writable

        ↓

/var/www/html/data

```

**---**

**# Repository Structure**

```text

/opt/docker-php/

├── README.md

├── CHANGELOG.md

├── create-php-app.sh

├── .gitignore

│

├── images/

│   ├── 7.4/

│   │   ├── Dockerfile

│   │   └── php.ini

│   ├── 8.2/

│   │   ├── Dockerfile

│   │   └── php.ini

│   ├── 8.3/

│   │   ├── Dockerfile

│   │   └── php.ini

│   ├── 8.4/

│   │   ├── Dockerfile

│   │   └── php.ini

│   └── 8.5/

│       ├── Dockerfile

│       └── php.ini

│

├── templates/

│   ├── docker/

│   │   └── docker-compose.yml

│   ├── nginx/

│   │   └── app.conf

│   └── php-fpm/

│       └── zz-custom.conf

│

└── scripts/

    ├── build-image.sh

    ├── install-requirements.sh

    └── test-images.sh

```

**---**

**# Production Directory Layout**

```text

/opt/

├── docker-php/

└── docker-apps/

/var/

└── apps/

```

**## `/opt/docker-php`**

Repository utama yang berisi:

\- Dockerfile PHP

\- PHP configuration

\- PHP-FPM configuration

\- Application generator

\- Docker Compose template

\- Nginx template

\- Requirement checker

\- Image build script

\- Image test script

\- Documentation

**## `/opt/docker-apps`**

Berisi konfigurasi deployment Docker untuk masing-masing aplikasi.

Contoh:

```text

/opt/docker-apps/myapp/

├── docker-compose.yml

├── zz-custom.conf

└── db-credentials.env

```

Database credentials dibuat otomatis oleh `create-php-app.sh`.

**## `/var/apps`**

Berisi source code dan runtime data aplikasi.

Laravel:

```text

/var/apps/myapp/

├── htdocs/
│   └── vendor/              ← mount point
├── data/
│   ├── vendor/
│   ├── storage-app/
│   ├── storage-framework/
│   ├── storage-logs/
│   └── bootstrap-cache/
├── logs/
├── backup/
└── composer/

```

CodeIgniter 4 / Generic PHP:

```text

/var/apps/myapp/

├── htdocs/
├── data/
│   └── writable/
│       ├── cache/
│       ├── logs/
│       ├── session/
│       └── uploads/
├── logs/
└── backup/

```

| Directory | Fungsi | Access |
|---|---|---|
| `htdocs/` | Application source | Read Only |
| `data/vendor/` | Laravel Composer dependencies | Read/Write |
| `data/storage-*` | Laravel runtime/storage | Read/Write |
| `data/bootstrap-cache/` | Laravel bootstrap cache | Read/Write |
| `data/writable/` | CI4/Generic runtime data | Read/Write |
| `logs/` | Application logs | Read/Write |
| `backup/` | Application backup | Read/Write |
| `composer/` | Composer binary | Read Only |

**---**

**# Installation**

**## 1. Prepare Server**

Repository dirancang untuk server Linux production dengan:

\- Nginx

\- Docker Engine

\- Docker Compose Plugin

\- MariaDB

MariaDB merupakan database standar project.

MySQL tetap dapat digunakan apabila server telah menggunakan MySQL.

**## 2. Clone Repository**

```bash

mkdir -p /opt

cd /opt

git clone https\://github.com/NRTechnology/docker-php.git docker-php

cd /opt/docker-php

```

**## 3. Make Scripts Executable**

```bash

chmod +x create-php-app.sh

chmod +x scripts/\*.sh

```

Verify:

```bash

ls -lah create-php-app.sh scripts/

```

**---**

**# Install Requirements**

Requirement installation dilakukan menggunakan:

```text

scripts/install-requirements.sh

```

Script digunakan untuk memeriksa dan memasang komponen dasar:

\- Nginx

\- Docker Engine

\- Docker Compose Plugin

\- MariaDB Server

\- MariaDB Client

Jalankan:

```bash

cd /opt/docker-php

./scripts/install-requirements.sh

```

Verifikasi:

```bash

nginx -v

docker --version

docker compose version

mariadb --version

```

Verifikasi service:

```bash

systemctl status nginx

systemctl status docker

systemctl status mariadb

```

\> **\*\*Important:\*\*** Script requirement tidak secara otomatis mengganti konfigurasi production yang sudah ada.

Script juga tidak secara otomatis mengubah:

\- Firewall

\- Database network binding

\- Docker daemon configuration

\- DNS

\- TLS/SSL

\- Reverse proxy

\- Production-specific network policy

**### MariaDB Security**

`mariadb-secure-installation` tidak dijalankan otomatis karena merupakan proses interaktif.

Setelah instalasi MariaDB, administrator disarankan melakukan hardening secara manual.

**---**

**# Database Standard**

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

**---**

**# Build PHP Images**

Image PHP harus tersedia sebelum membuat application environment.

Build script:

```text

scripts/build-image.sh

```

**## Interactive Mode**

```bash

cd /opt/docker-php

./scripts/build-image.sh

```

Menu menyediakan pilihan:

```text

1\. PHP 7.4

2\. PHP 8.2

3\. PHP 8.3

4\. PHP 8.4

5\. PHP 8.5

6\. Build All

7\. Show Images

0\. Exit

```

**## Build Specific Version**

```bash

./scripts/build-image.sh 8.2

./scripts/build-image.sh 8.3

./scripts/build-image.sh 8.4

./scripts/build-image.sh 8.5

./scripts/build-image.sh 7.4

```

**## Build All Images**

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

**---**

**# Verify PHP Images**

Image dapat diverifikasi menggunakan:

```bash

./scripts/test-images.sh

```

Pemeriksaan meliputi:

\- PHP version

\- PHP modules

\- PHP configuration

\- PHP-FPM configuration

Manual verification:

```bash

docker run --rm local/php:8.4 php -v

docker run --rm local/php:8.4 php -m

docker run --rm local/php:8.4 php-fpm -t

```

**---**

**# Create Application**

Application generator:

```text

create-php-app.sh

```

Syntax:

```bash

./create-php-app.sh \<application-name> \<php-version> \<framework> \<domain-name>

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

**## Laravel**

```bash

./create-php-app.sh myapp 8.3 laravel myapp.example.go.id

```

**## CodeIgniter 4**

```bash

./create-php-app.sh myapp2 8.4 ci myapp2.example.go.id

```

**## Generic PHP**

```bash

./create-php-app.sh myapp3 8.5 generic myapp3.example.go.id

```

**## Legacy Application**

```bash

./create-php-app.sh legacy-app 7.4 generic legacy.example.go.id

```

**---**

**# What `create-php-app.sh` Does**

Generator melakukan beberapa proses secara otomatis.

**## 1. Validate Input**

Memvalidasi:

\- Application name

\- Domain name

\- PHP version

\- Framework

\- Docker

\- Docker Compose

\- Nginx

\- PHP image

Generator juga melakukan database preflight sebelum membuat resource deployment:

- Memastikan root MySQL/MariaDB dapat login tanpa password.
- Memeriksa apakah database aplikasi sudah ada.
- Memeriksa apakah database user sudah ada.
- Jika user sudah ada, seluruh Host yang terkait user tersebut ditampilkan.
- Jika database atau user sudah ada, proses dihentikan sebelum membuat Docker network, directory aplikasi, atau resource deployment lainnya.
- Generator tidak menghapus atau mengubah database/user existing secara otomatis.

Contoh pemeriksaan:

```bash
mysql -u root -e "SELECT 1;"
```

**## 2. Create Application Directories**

```text

/var/apps/myapp/

├── htdocs/

├── data/

│   └── writable/

├── logs/

└── backup/

```

**## 3. Create Docker Network**

Setiap aplikasi mendapatkan network sendiri:

```text

myapp-network

```

Network menggunakan:

```yaml

driver: bridge

```

Generator membuat network setelah database preflight berhasil dan membaca subnet serta gateway aktual setelah network dibuat.

Jika network dengan nama yang sama sudah ada, generator **menghentikan proses** dan tidak menggunakan kembali network tersebut secara otomatis.

**## 4. Create Database**

Generator secara otomatis membuat database:

```text

myapp

```

Database menggunakan:

```text

utf8mb4

utf8mb4_unicode_ci

```

**## 5. Create Database User**

Generator membuat user:

```text

myapp

```

User hanya diberikan privilege terhadap database aplikasi:

```text

myapp.\*

```

**## 6. Generate Database Password**

Password database dibuat otomatis menggunakan random generator:

```text

openssl rand -hex

```

atau fallback:

```text

/dev/urandom

```

Password tidak menggunakan password default.

**## 7. Restrict Database User Host**

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

**---**

**# Database Credentials**

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

DB_PASSWORD=\<generated-password>

```

Permission:

```text

0600

```

Owner:

```text

root\:root

```

Periksa:

```bash

cat /opt/docker-apps/myapp/db-credentials.env

```

\> Jangan memasukkan file `db-credentials.env` ke Git repository.

`DB_CONNECTION=mysql` digunakan karena nama driver database Laravel adalah `mysql`,

baik ketika backend database menggunakan MySQL maupun MariaDB.

**---**

**# Generated Docker Configuration**

Generator membuat:

```text

/opt/docker-apps/myapp/

├── docker-compose.yml

├── zz-custom.conf

└── db-credentials.env

```

Docker Compose menggunakan:

```yaml

image: local/php:\<version>

```

Contoh:

```yaml

image: local/php:8.4

```

**---**

**# Docker Security**

Container menggunakan beberapa lapisan hardening.

**## Read-Only Root Filesystem**

```yaml

read_only: true

```

**## Read-Only Application Source**

```yaml

volumes:

  - /var/apps/myapp/htdocs\:/var/www/html\:ro

```

Source code tidak dapat ditulis langsung oleh PHP-FPM.

**## Writable Runtime Directory**

Directory yang membutuhkan write dipisahkan.

Laravel:

```text

storage

bootstrap/cache

```

CodeIgniter:

```text

writable

```

Generic:

```text

data

```

**## No New Privileges**

```yaml

security_opt:

  - no-new-privileges\:true

```

**## Temporary Filesystem**

```yaml

tmpfs:

  - /tmp\:rw,noexec,nosuid,size=128m

```

**## Resource Limits**

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

**---**

**# Container Capabilities**

Project ini **\*\*tidak menggunakan\*\***:

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

**---**

**# PHP-FPM**

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

\- Tidak membuka PHP-FPM ke jaringan

\- Mengurangi attack surface

\- Tidak membutuhkan port 9001, 9002, 9003, dan seterusnya

\- Memudahkan multi-PHP deployment

**---**

**# Nginx**

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

Generator otomatis membuat dan mengaktifkan virtual host.

Untuk PHP-FPM container, `SCRIPT_FILENAME` menggunakan path filesystem di dalam container:

```nginx
fastcgi_param SCRIPT_FILENAME /var/www/html/public$fastcgi_script_name;
fastcgi_param DOCUMENT_ROOT /var/www/html/public;
```

Path source pada host:

```text
/var/apps/myapp/htdocs/public
```

dipetakan ke container:

```text
/var/www/html/public
```

Dengan demikian Nginx host tidak mengirim path host ke PHP-FPM container.

**---**

**# Nginx Security**

Generated Nginx configuration menyediakan:

\- Security headers

\- Hidden-file protection

\- Sensitive file protection

\- PHP-FPM Unix socket

\- `try_files`

\- PHP execution restriction pada writable directories

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

**---**

**# Validate Nginx**

```bash

nginx -t

```

Jika valid:

```bash

systemctl reload nginx

```

Generator juga menjalankan validasi Nginx selama proses pembuatan application.

**---**

**# Validate Docker Compose**

```bash

cd /opt/docker-apps/myapp

docker compose config

```

Generator juga menjalankan validasi `docker compose config` sebelum deployment selesai.

**---**

**# Start Application**

```bash

cd /opt/docker-apps/myapp

cat docker-compose.yml

docker compose up -d

docker compose ps

```

Expected:

```text

myapp-php    ...    Up

```

**---**

**# PHP-FPM Logs**

```bash

docker compose logs --tail=50 php

docker compose logs -f php

```

Expected:

```text

fpm is running

ready to handle connections

```

**---**

**# PHP Verification**

```bash

docker compose exec php php -v

docker compose exec php php -m

docker compose exec php php-fpm -t

```

**---**

**# Laravel Deployment**

Source:

```text

/var/apps/myapp/htdocs

```

Pastikan:

```text

/var/apps/myapp/htdocs/artisan
/var/apps/myapp/htdocs/composer.json
/var/apps/myapp/htdocs/public
/var/apps/myapp/htdocs/vendor

```

`htdocs/vendor` digunakan sebagai mount point. Dependency Composer sebenarnya disimpan di:

```text

/var/apps/myapp/data/vendor

```

Document root:

```text

/var/apps/myapp/htdocs/public

```

Composer tidak termasuk dalam PHP-FPM runtime image. Generator menyiapkan binary Composer di:

```text

/var/apps/myapp/composer/composer

```

dan me-mount-nya read-only ke:

```text

/usr/local/bin/composer

```

Install dependency dari container sebagai `www-data`:

```bash
cd /opt/docker-apps/myapp

docker compose exec --user www-data php composer install \
  --no-dev \
  --no-interaction \
  --prefer-dist \
  --optimize-autoloader
```

Verifikasi Laravel:

```bash
docker compose exec --user www-data php php artisan --version
```

Migration production:

```bash
docker compose exec --user www-data php php artisan migrate --force
```

Optimasi Laravel:

```bash
docker compose exec --user www-data php php artisan optimize
```

Untuk aplikasi baru yang belum memiliki application key:

```bash
docker compose exec --user www-data php php artisan key:generate
```

Public storage:

```text
/var/apps/myapp/htdocs/public/storage
        ↓
../storage/app/public
        ↓
/var/apps/myapp/data/storage-app/public
```

**# CodeIgniter 4 Deployment**

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

**---**

**# Generic PHP Deployment**

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

**---**

**# Application Isolation**

Setiap aplikasi mendapatkan environment terisolasi:

```text

Application

│

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

**---**

**# Upgrade PHP**

Setiap aplikasi dapat menggunakan versi PHP yang berbeda.

Contoh:

```text

myapp   → PHP 8.3

myapp2  → PHP 8.4

myapp3  → PHP 8.5

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

**---**

**# Production Deployment Workflow**

```text

             SERVER PREPARATION

                     │

                     ▼

        install-requirements.sh

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

          ┌──────────┼──────────┐

          │          │          │

          ▼          ▼          ▼

       Network     Database   Nginx

          │          │          │

          └──────────┼──────────┘

                     │

                     ▼

             Deploy Source Code

                     │

                     ▼

            Install Dependencies

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

**---**

**# Production Deployment Example**

**## Step 1 — Install Requirements**

```bash

cd /opt/docker-php

./scripts/install-requirements.sh

```

**## Step 2 — Build PHP Image**

```bash

./scripts/build-image.sh 8.4

```

**## Step 3 — Test Image**

```bash

./scripts/test-images.sh

```

**## Step 4 — Create Application**

```bash

./create-php-app.sh myapp 8.4 laravel myapp.example.go.id

```

**## Step 5 — Review Configuration**

```bash

cd /opt/docker-apps/myapp

cat docker-compose.yml

cat db-credentials.env

```

**## Step 6 — Deploy Application Source**

Copy or clone source code to:

```text

/var/apps/myapp/htdocs

```

**## Step 7 — Install Application Dependencies**

Dependency installation dilakukan terpisah dari runtime image.

**## Step 8 — Start PHP-FPM**

```bash

docker compose up -d

```

**## Step 9 — Verify**

```bash

docker compose ps

docker compose logs --tail=50 php

ls -lah /run/php/myapp.sock

```

**## Step 10 — Validate Nginx**

```bash

nginx -t

systemctl reload nginx

```

**## Step 11 — Test Application**

```bash

curl -I http\://myapp.example.go.id

```

**---**

**# Backup**

Backup directory tersedia di:

```text

/var/apps/myapp/backup/

```

Dapat digunakan untuk:

\- Database backup

\- Application backup

\- Configuration backup

\- Deployment backup

Backup production sebaiknya tidak hanya disimpan pada server yang sama.

Gunakan sistem backup terpisah untuk perlindungan terhadap:

\- Hardware failure

\- Disk failure

\- Accidental deletion

\- Ransomware

\- Application compromise

**---**

**# Container Management**

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

**---**

**# Cleanup / Remove Failed Application**

Jika proses deployment berhenti karena error setelah sebagian resource dibuat, bersihkan resource deployment sebelum mencoba kembali dengan nama aplikasi yang sama.

Contoh untuk `myapp`:

```bash
APP_NAME="myapp"
DB_NAME="myapp"
DB_USER="myapp"
NETWORK="${APP_NAME}-network"

docker rm -f "${APP_NAME}-php" 2>/dev/null || true
docker rm -f "${APP_NAME}-composer-bootstrap" 2>/dev/null || true

docker network rm "${NETWORK}" 2>/dev/null || true

mysql -u root -e "DROP DATABASE IF EXISTS `${DB_NAME}`;"

mysql -u root <<SQL
SET @sql = NULL;

SELECT GROUP_CONCAT(
    CONCAT('DROP USER IF EXISTS ''', User, '''@''', Host, ''';')
    SEPARATOR ' '
)
INTO @sql
FROM mysql.user
WHERE User = '${DB_USER}';

SET @sql = IFNULL(@sql, 'SELECT 1;');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

FLUSH PRIVILEGES;
SQL

rm -rf "/var/apps/${APP_NAME}"
rm -rf "/opt/docker-apps/${APP_NAME}"

rm -f "/run/php/${APP_NAME}.sock"

rm -f "/etc/nginx/sites-enabled/${APP_NAME}.conf"
rm -f "/etc/nginx/sites-available/${APP_NAME}.conf"

nginx -t && systemctl reload nginx
```

> Jalankan cleanup hanya setelah memastikan nama aplikasi, database, user, network, dan konfigurasi Nginx memang milik deployment yang gagal. Perintah `DROP USER` menghapus seluruh account dengan username tersebut pada semua `Host`.

---

**# Troubleshooting**

**## Check Container**

```bash

docker compose ps

```

**## Check PHP-FPM Logs**

```bash

docker compose logs --tail=100 php

```

**## Check Socket**

```bash

ls -lah /run/php/

```

**## Check Nginx**

```bash

nginx -t

```

**## Check Nginx Error Log**

```bash

tail -f /var/log/nginx/myapp.error.log

```

**## Check Application Logs**

```bash

ls -lah /var/apps/myapp/logs/

```

**---**

**# Security Recommendations**

Untuk deployment production:

\- Gunakan HTTPS.

\- Gunakan firewall.

\- Batasi akses database.

\- Jangan expose PHP-FPM ke internet.

\- Gunakan Unix socket untuk Nginx → PHP-FPM.

\- Gunakan TCP untuk PHP → database.

\- Gunakan WAF jika diperlukan.

\- Pisahkan source code dan writable directory.

\- Jangan menyimpan credential di Git.

\- Backup database secara berkala.

\- Simpan backup pada lokasi terpisah.

\- Monitor host dan container.

\- Gunakan centralized logging bila diperlukan.

\- Update PHP images secara berkala.

\- Migrasikan PHP 7.4 legacy application ke versi yang masih didukung.

\- Pastikan dependency Composer sesuai dengan versi PHP.

**---**

**# Important Operational Notes**

**## Database**

MariaDB adalah standar database project.

MySQL tetap didukung.

Generator tidak melakukan migrasi otomatis antara MariaDB dan MySQL.

Existing production database tidak diganti secara otomatis.

**## Database Root**

Application generator tidak mengubah password atau konfigurasi akun root database.

Root database sebaiknya hanya dapat digunakan dari lokasi administrasi yang dipercaya.

**## Database Credentials**

File:

```text

/opt/docker-apps/\<application-name>/db-credentials.env

```

berisi credential database dan harus dijaga:

```text

root\:root

0600

```

Jangan commit file tersebut ke Git.

**## Docker Network**

Setiap aplikasi mendapatkan network sendiri:

```text

\<application-name>-network

```

Network menggunakan:

```text

driver: bridge

```

Generator membaca subnet dan gateway aktual dari Docker setelah network dibuat.

Docker Compose dapat menampilkan warning bahwa network telah dibuat di luar Compose.

Ini merupakan konsekuensi dari network yang dibuat oleh generator dan tidak mengubah fungsi container.

**## Composer**

Composer tidak termasuk dalam PHP-FPM runtime image.

Dependency aplikasi harus dipasang menggunakan environment build/deployment yang sesuai.

Hal ini menjaga runtime image tetap fokus pada PHP-FPM dan mengurangi komponen yang tidak diperlukan di production runtime.

**---**

**# Project Goals**

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

**---**

**# Release**

Current release:

```text

1.2.0

```

Release date:

```text

2026-09-19

```

Major changes in 1.2.0:

- Database preflight sebelum resource deployment dibuat
- Verifikasi root MySQL/MariaDB dapat login tanpa password
- Pemeriksaan existing database
- Pemeriksaan existing database user pada seluruh `Host`
- Deployment berhenti jika database/user sudah ada
- Tidak mengubah atau menghapus database/user existing secara otomatis
- Docker network dibuat setelah database preflight berhasil
- Laravel vendor dipisahkan ke dedicated writable `data/vendor`
- Laravel storage dipisahkan menjadi writable mounts
- Laravel bootstrap cache dipisahkan menjadi writable mount
- Composer binary disiapkan di luar PHP-FPM runtime image
- Composer dependency installation menggunakan user `www-data`
- Laravel public storage symlink didokumentasikan
- Path `SCRIPT_FILENAME` PHP-FPM menggunakan path filesystem container
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

See [CHANGELOG.md]\(CHANGELOG.md) for complete release history.

**---**

**# License**

Repository ini merupakan infrastructure dan deployment template.

Lisensi dapat ditentukan sesuai kebutuhan organisasi atau project yang menggunakan repository ini.

**---**

**# Maintainer**

**\*\*NR Technology\*\***

Infrastructure, DevOps, Cybersecurity, and Web Server Engineering.

**---**

**# Repository**

GitHub:

https\://github.com/NRTechnology/docker-php