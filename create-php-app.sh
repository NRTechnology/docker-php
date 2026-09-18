#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# create-php-app.sh
# Standard PHP-FPM Docker application generator
# ==============================================================================

DOCKER_APPS_DIR="/opt/docker-apps"
APPS_DIR="/var/apps"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
PHP_RUN_DIR="/run/php"


# ==============================================================================
# USAGE
# ==============================================================================

usage() {
    cat <<USAGE

Usage:
  $0 <app-name> <php-version> <framework> <domain-name>

PHP versions:
  7.4 | 8.2 | 8.3 | 8.4 | 8.5

Frameworks:
  laravel | ci | generic

Examples:
  $0 myapp 8.2 laravel myapp.example.go.id
  $0 myapp 8.3 laravel myapp.example.go.id
  $0 myapp2 8.4 ci myapp2.example.go.id
  $0 myapp3 8.5 generic myapp3.example.go.id
  $0 legacy-app 7.4 generic legacy.example.go.id

Description:
  app-name      Nama aplikasi / identifier internal.
  php-version   Versi PHP-FPM yang digunakan.
  framework     Framework aplikasi.
  domain-name   Domain yang digunakan oleh Nginx.

Database:
  Script mendukung MySQL maupun MariaDB.
  Client yang tersedia digunakan secara otomatis:
    mariadb
    mysql

  Driver aplikasi tetap:
    DB_CONNECTION=mysql

USAGE
    exit 1
}


# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}


# ==============================================================================
# ARGUMENTS
# ==============================================================================

[[ $# -eq 4 ]] || usage

APP_NAME="$1"
PHP_VERSION="$2"
FRAMEWORK="$3"
DOMAIN_NAME="$4"

[[ "$EUID" -eq 0 ]] || die "Script harus dijalankan sebagai root."


# ==============================================================================
# VALIDATE APPLICATION NAME
# ==============================================================================

[[ "$APP_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] \
    || die "Nama aplikasi tidak valid: $APP_NAME"

[[ "$APP_NAME" != "." && "$APP_NAME" != ".." ]] \
    || die "Nama aplikasi tidak valid."

[[ "$APP_NAME" != */* ]] \
    || die "Nama aplikasi tidak boleh mengandung '/'."


# ==============================================================================
# VALIDATE DOMAIN NAME
# ==============================================================================

# Format:
#   example.com
#   myapp.example.go.id
#   app.internal.local
#
# Tidak mengizinkan:
#   http://example.com
#   https://example.com
#   example.com/path
#   *.example.com

DOMAIN_REGEX='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$'

[[ "$DOMAIN_NAME" =~ $DOMAIN_REGEX ]] \
    || die "Domain tidak valid: $DOMAIN_NAME"

# Domain dinormalisasi ke lowercase.
DOMAIN_NAME="$(printf '%s' "$DOMAIN_NAME" | tr '[:upper:]' '[:lower:]')"


# ==============================================================================
# VALIDATE PHP VERSION
# ==============================================================================

case "$PHP_VERSION" in
    7.4|8.2|8.3|8.4|8.5)
        ;;
    *)
        die "PHP version tidak didukung: $PHP_VERSION"
        ;;
esac


# ==============================================================================
# VALIDATE FRAMEWORK
# ==============================================================================

case "$FRAMEWORK" in
    laravel|ci|generic)
        ;;
    *)
        die "Framework tidak didukung: $FRAMEWORK"
        ;;
esac


# ==============================================================================
# CHECK REQUIREMENTS
# ==============================================================================

command -v docker >/dev/null 2>&1 \
    || die "Docker tidak ditemukan."

command -v nginx >/dev/null 2>&1 \
    || die "Nginx tidak ditemukan."

docker compose version >/dev/null 2>&1 \
    || die "Docker Compose plugin tidak ditemukan."


# ==============================================================================
# DATABASE CLIENT DETECTION
# ==============================================================================

DATABASE_CLIENT=""

if command -v mariadb >/dev/null 2>&1; then

    DATABASE_CLIENT="mariadb"

elif command -v mysql >/dev/null 2>&1; then

    DATABASE_CLIENT="mysql"

else

    die "Database client tidak ditemukan. Install mariadb-client atau mysql-client."
fi

log "Database client : ${DATABASE_CLIENT}"


# ==============================================================================
# APPLICATION PATHS
# ==============================================================================

APP_ROOT="${APPS_DIR}/${APP_NAME}"
APP_HTDOCS="${APP_ROOT}/htdocs"
APP_WRITABLE="${APP_ROOT}/data/writable"
APP_LOGS="${APP_ROOT}/logs"
APP_BACKUP="${APP_ROOT}/backup"

DOCKER_APP_ROOT="${DOCKER_APPS_DIR}/${APP_NAME}"

FPM_CONFIG="${DOCKER_APP_ROOT}/zz-custom.conf"
COMPOSE_FILE="${DOCKER_APP_ROOT}/docker-compose.yml"

NGINX_FILE="${NGINX_AVAILABLE}/${APP_NAME}.conf"
NGINX_LINK="${NGINX_ENABLED}/${APP_NAME}.conf"

SOCKET_PATH="${PHP_RUN_DIR}/${APP_NAME}.sock"

IMAGE_NAME="local/php:${PHP_VERSION}"
NETWORK_NAME="${APP_NAME}-network"
CONTAINER_NAME="${APP_NAME}-php"


# ==============================================================================
# DATABASE SETTINGS
# ==============================================================================

DB_NAME="${APP_NAME}"
DB_USER="${APP_NAME}"
DB_CREDENTIALS_FILE="${DOCKER_APP_ROOT}/db-credentials.env"


# ==============================================================================
# CHECK EXISTING TARGETS
# ==============================================================================

for path in \
    "$APP_ROOT" \
    "$DOCKER_APP_ROOT" \
    "$NGINX_FILE" \
    "$NGINX_LINK"
do
    [[ ! -e "$path" && ! -L "$path" ]] \
        || die "Target sudah ada: $path"
done


# ==============================================================================
# CHECK PHP IMAGE
# ==============================================================================

docker image inspect "$IMAGE_NAME" >/dev/null 2>&1 \
    || die "Image tidak ditemukan: $IMAGE_NAME"

if [[ "$PHP_VERSION" == "7.4" ]]; then
    warn "PHP 7.4 adalah versi legacy/EOL."
fi


# ==============================================================================
# FRAMEWORK CONFIGURATION
# ==============================================================================

case "$FRAMEWORK" in

    laravel)

        DOCUMENT_ROOT="/var/apps/${APP_NAME}/htdocs/public"

        WRITABLE_MOUNTS="\
      - ${APP_WRITABLE}/storage:/var/www/html/storage:rw
      - ${APP_WRITABLE}/bootstrap-cache:/var/www/html/bootstrap/cache:rw"

        WRITABLE_DIRS="storage bootstrap-cache"

        WRITABLE_DENY='    location ~ ^/(storage|bootstrap/cache)/.*\.php$ {
        deny all;
    }'

        ;;

    ci)

        DOCUMENT_ROOT="/var/apps/${APP_NAME}/htdocs/public"

        WRITABLE_MOUNTS="\
      - ${APP_WRITABLE}:/var/www/html/writable:rw"

        WRITABLE_DIRS="cache logs session uploads"

        WRITABLE_DENY='    location ~ ^/writable/.*\.php$ {
        deny all;
    }'

        ;;

    generic)

        DOCUMENT_ROOT="/var/apps/${APP_NAME}/htdocs"

        WRITABLE_MOUNTS="\
      - ${APP_WRITABLE}:/var/www/html/data:rw"

        WRITABLE_DIRS="cache logs session uploads"

        WRITABLE_DENY='    location ~ ^/data/.*\.php$ {
        deny all;
    }'

        ;;

esac


# ==============================================================================
# CREATE DIRECTORIES
# ==============================================================================

log "Membuat directory aplikasi..."

mkdir -p \
    "$APP_HTDOCS" \
    "$APP_WRITABLE" \
    "$APP_LOGS" \
    "$APP_BACKUP" \
    "$DOCKER_APP_ROOT" \
    "$PHP_RUN_DIR"

for dir in $WRITABLE_DIRS; do
    mkdir -p "${APP_WRITABLE}/${dir}"
done


# ==============================================================================
# SET PERMISSIONS
# ==============================================================================

log "Mengatur permission directory..."

# Application source
chown root:root "$APP_HTDOCS"
chmod 0755 "$APP_HTDOCS"

# Writable runtime
chown -R www-data:www-data "$APP_WRITABLE"

find "$APP_WRITABLE" \
    -type d \
    -exec chmod 0750 {} \;

find "$APP_WRITABLE" \
    -type f \
    -exec chmod 0640 {} \;

# Application logs
chown -R www-data:www-data "$APP_LOGS"

find "$APP_LOGS" \
    -type d \
    -exec chmod 0750 {} \;

find "$APP_LOGS" \
    -type f \
    -exec chmod 0640 {} \;

# Backup
chown root:root "$APP_BACKUP"
chmod 0750 "$APP_BACKUP"

# PHP-FPM socket directory
chown root:www-data "$PHP_RUN_DIR"
chmod 0775 "$PHP_RUN_DIR"


# ==============================================================================
# DOCKER NETWORK
# ==============================================================================

log "Membuat Docker network..."

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    die "Docker network sudah ada: $NETWORK_NAME"
fi

docker network create \
    --driver bridge \
    "$NETWORK_NAME" >/dev/null \
    || die "Gagal membuat Docker network: $NETWORK_NAME"

log "Docker network berhasil dibuat: $NETWORK_NAME"


# ==============================================================================
# GET ACTUAL DOCKER NETWORK INFORMATION
# ==============================================================================

# Ambil subnet aktual yang diberikan Docker.
NETWORK_SUBNET="$(
    docker network inspect "$NETWORK_NAME" \
        --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
)"

# Ambil gateway aktual yang diberikan Docker.
NETWORK_GATEWAY="$(
    docker network inspect "$NETWORK_NAME" \
        --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
)"

[[ -n "$NETWORK_SUBNET" ]] \
    || die "Subnet Docker network tidak dapat ditentukan."

[[ -n "$NETWORK_GATEWAY" ]] \
    || die "Gateway Docker network tidak dapat ditentukan."

log "Docker subnet  : $NETWORK_SUBNET"
log "Docker gateway : $NETWORK_GATEWAY"


# ==============================================================================
# GENERATE DATABASE HOST PATTERN
# ==============================================================================

NETWORK_CIDR="${NETWORK_SUBNET#*/}"
NETWORK_BASE="${NETWORK_SUBNET%/*}"

IFS='.' read -r OCT1 OCT2 OCT3 OCT4 <<< "$NETWORK_BASE"

case "$NETWORK_CIDR" in

    8)
        DB_HOST_PATTERN="${OCT1}.%"
        ;;

    16)
        DB_HOST_PATTERN="${OCT1}.${OCT2}.%"
        ;;

    24)
        DB_HOST_PATTERN="${OCT1}.${OCT2}.${OCT3}.%"
        ;;

    *)
        die "Subnet Docker tidak didukung untuk automatic database host restriction: ${NETWORK_SUBNET}"
        ;;

esac

log "Database allowed host: ${DB_HOST_PATTERN}"


# ==============================================================================
# MYSQL / MARIADB DATABASE
# ==============================================================================

log "Memeriksa koneksi database..."

"${DATABASE_CLIENT}" -e "SELECT 1;" >/dev/null 2>&1 \
    || die "Tidak dapat terhubung ke MySQL/MariaDB menggunakan akun saat ini."

log "Koneksi database berhasil."


# ==============================================================================
# CHECK EXISTING DATABASE
# ==============================================================================

DB_EXISTS="$(
    "${DATABASE_CLIENT}" -Nse \
        "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}';"
)"

[[ "$DB_EXISTS" == "0" ]] \
    || die "Database sudah ada: ${DB_NAME}"


# ==============================================================================
# CHECK EXISTING DATABASE USER
# ==============================================================================

DB_USER_EXISTS="$(
    "${DATABASE_CLIENT}" -Nse \
        "SELECT COUNT(*) FROM mysql.user WHERE User='${DB_USER}' AND Host='${DB_HOST_PATTERN}';"
)"

[[ "$DB_USER_EXISTS" == "0" ]] \
    || die "Database user sudah ada: '${DB_USER}'@'${DB_HOST_PATTERN}'"


# ==============================================================================
# GENERATE DATABASE PASSWORD
# ==============================================================================

log "Generate password database..."

if command -v openssl >/dev/null 2>&1; then

    DB_PASSWORD="$(
        openssl rand -base64 48 \
        | tr -dc 'A-Za-z0-9_@%+=-' \
        | head -c 32
    )

else

    DB_PASSWORD="$(
        tr -dc 'A-Za-z0-9_@%+=-' < /dev/urandom \
        | head -c 32
    )

fi

[[ ${#DB_PASSWORD} -ge 24 ]] \
    || die "Gagal membuat password database yang cukup kuat."


# ==============================================================================
# ESCAPE DATABASE PASSWORD
# ==============================================================================

DB_PASSWORD_SQL="$(
    printf '%s' "$DB_PASSWORD" \
    | sed "s/'/''/g"
)"


# ==============================================================================
# CREATE DATABASE
# ==============================================================================

log "Membuat database: ${DB_NAME}..."

"${DATABASE_CLIENT}" <<SQL
CREATE DATABASE \`${DB_NAME}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
SQL

log "Database berhasil dibuat: ${DB_NAME}"


# ==============================================================================
# CREATE DATABASE USER
# ==============================================================================

log "Membuat database user..."

"${DATABASE_CLIENT}" <<SQL
CREATE USER '${DB_USER}'@'${DB_HOST_PATTERN}'
    IDENTIFIED BY '${DB_PASSWORD_SQL}';

GRANT ALL PRIVILEGES
    ON \`${DB_NAME}\`.*
    TO '${DB_USER}'@'${DB_HOST_PATTERN}';

FLUSH PRIVILEGES;
SQL

log "Database user berhasil dibuat:"
log "  User : ${DB_USER}"
log "  Host : ${DB_HOST_PATTERN}"


# ==============================================================================
# SAVE DATABASE CREDENTIALS
# ==============================================================================

log "Menyimpan database credentials..."

cat > "$DB_CREDENTIALS_FILE" <<EOF
# Database credentials generated by create-php-app.sh
# Application: ${APP_NAME}

# Compatible with MySQL and MariaDB
DB_CONNECTION=mysql
DB_HOST=${NETWORK_GATEWAY}
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
EOF

chown root:root "$DB_CREDENTIALS_FILE"
chmod 0600 "$DB_CREDENTIALS_FILE"

log "Database credentials disimpan:"
log "  ${DB_CREDENTIALS_FILE}"


# ==============================================================================
# PHP-FPM POOL CONFIGURATION
# ==============================================================================

log "Membuat PHP-FPM pool configuration..."

cat > "$FPM_CONFIG" <<EOF
[${APP_NAME}]

user = www-data
group = www-data

listen = /run/php/${APP_NAME}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 20
pm.start_servers = 3
pm.min_spare_servers = 2
pm.max_spare_servers = 5
pm.max_requests = 500

request_terminate_timeout = 120s
request_slowlog_timeout = 10s
slowlog = /proc/self/fd/2

catch_workers_output = yes

php_admin_flag[log_errors] = on
php_admin_value[error_log] = /proc/self/fd/2

clear_env = no

php_admin_flag[expose_php] = off
EOF


# ==============================================================================
# DOCKER COMPOSE
# ==============================================================================

log "Membuat Docker Compose configuration..."

cat > "$COMPOSE_FILE" <<EOF
services:

  php:
    image: ${IMAGE_NAME}
    container_name: ${CONTAINER_NAME}

    restart: unless-stopped

    working_dir: /var/www/html

    read_only: true

    security_opt:
      - no-new-privileges:true

    tmpfs:
      - /tmp:rw,noexec,nosuid,size=128m

    volumes:

      # Application source code - READ ONLY
      - ${APP_HTDOCS}:/var/www/html:ro

${WRITABLE_MOUNTS}

      # PHP-FPM Unix socket
      - ${PHP_RUN_DIR}:/run/php:rw

      # Application logs
      - ${APP_LOGS}:/var/log/app:rw

      # PHP-FPM pool configuration
      - ${FPM_CONFIG}:/usr/local/etc/php-fpm.d/zz-custom.conf:ro

    environment:
      TZ: Asia/Jakarta

    cpus: "2.0"
    mem_limit: 1g
    pids_limit: 100

    ulimits:
      nofile:
        soft: 65535
        hard: 65535

    stop_grace_period: 30s

    networks:
      - ${NETWORK_NAME}

networks:

  ${NETWORK_NAME}:
    name: ${NETWORK_NAME}
    driver: bridge
EOF


# ==============================================================================
# NGINX CONFIGURATION
# ==============================================================================

log "Membuat Nginx virtual host..."

cat > "$NGINX_FILE" <<EOF
server {

    listen 80;

    server_name ${DOMAIN_NAME};

    root ${DOCUMENT_ROOT};

    index index.php index.html;

    charset utf-8;


    # --------------------------------------------------------------------------
    # LOGGING
    # --------------------------------------------------------------------------

    access_log /var/log/nginx/${APP_NAME}.access.log;
    error_log /var/log/nginx/${APP_NAME}.error.log warn;


    # --------------------------------------------------------------------------
    # SECURITY HEADERS
    # --------------------------------------------------------------------------

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;


    # --------------------------------------------------------------------------
    # APPLICATION
    # --------------------------------------------------------------------------

    location / {

        try_files \$uri \$uri/ /index.php?\$query_string;

    }


    # --------------------------------------------------------------------------
    # PHP-FPM
    # --------------------------------------------------------------------------

    location ~ \.php$ {

        try_files \$uri =404;

        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$document_root;

        fastcgi_param HTTP_PROXY "";

        fastcgi_pass unix:${SOCKET_PATH};

        fastcgi_connect_timeout 10s;
        fastcgi_send_timeout 120s;
        fastcgi_read_timeout 120s;

    }


    # --------------------------------------------------------------------------
    # HIDDEN FILE PROTECTION
    # --------------------------------------------------------------------------

    location ~ /\.(?!well-known).* {

        deny all;

    }


    # --------------------------------------------------------------------------
    # SENSITIVE FILE PROTECTION
    # --------------------------------------------------------------------------

    location ~* \.(env|ini|log|sql|bak|backup|old|orig|save|swp)$ {

        deny all;

    }


    # --------------------------------------------------------------------------
    # WRITABLE DIRECTORY PHP EXECUTION PROTECTION
    # --------------------------------------------------------------------------

${WRITABLE_DENY}

}
EOF


# ==============================================================================
# FILE OWNERSHIP / PERMISSIONS
# ==============================================================================

chmod 0644 \
    "$FPM_CONFIG" \
    "$COMPOSE_FILE" \
    "$NGINX_FILE"

chown root:root \
    "$FPM_CONFIG" \
    "$COMPOSE_FILE" \
    "$NGINX_FILE"


# ==============================================================================
# VALIDATE DOCKER COMPOSE
# ==============================================================================

log "Testing Docker Compose configuration..."

if ! docker compose -f "$COMPOSE_FILE" config >/dev/null; then

    die "Docker Compose configuration tidak valid."

fi

log "Docker Compose configuration valid."


# ==============================================================================
# VALIDATE NGINX
# ==============================================================================

log "Testing konfigurasi Nginx..."

if ! nginx -t; then

    die "nginx -t gagal. Nginx symlink belum diaktifkan."

fi

log "Konfigurasi Nginx valid."


# ==============================================================================
# ENABLE NGINX SITE
# ==============================================================================

log "Mengaktifkan Nginx virtual host..."

ln -s "$NGINX_FILE" "$NGINX_LINK"


# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

cat <<SUMMARY

Application berhasil dibuat.

============================================================
Application
============================================================

Application : ${APP_NAME}
Domain      : ${DOMAIN_NAME}
PHP         : ${PHP_VERSION}
Framework   : ${FRAMEWORK}

============================================================
Application Directory
============================================================

Source      : ${APP_HTDOCS}
Writable    : ${APP_WRITABLE}
Logs        : ${APP_LOGS}
Backup      : ${APP_BACKUP}

============================================================
Docker
============================================================

Docker      : ${DOCKER_APP_ROOT}
Compose     : ${COMPOSE_FILE}
FPM Pool    : ${FPM_CONFIG}
Container   : ${CONTAINER_NAME}
Network     : ${NETWORK_NAME}
Subnet      : ${NETWORK_SUBNET}
Gateway     : ${NETWORK_GATEWAY}
Image       : ${IMAGE_NAME}

============================================================
Database
============================================================

Client      : ${DATABASE_CLIENT}
Database    : ${DB_NAME}
Username    : ${DB_USER}
Host        : ${NETWORK_GATEWAY}
Port        : 3306
Allowed     : ${DB_HOST_PATTERN}
Credentials : ${DB_CREDENTIALS_FILE}

============================================================
Nginx
============================================================

Config      : ${NGINX_FILE}
Enabled     : ${NGINX_LINK}
Domain      : ${DOMAIN_NAME}

============================================================
PHP-FPM Socket
============================================================

Socket      : ${SOCKET_PATH}

============================================================
Next Steps
============================================================

1. Upload/copy application source code:

   ${APP_HTDOCS}

2. Check database credentials:

   cat ${DB_CREDENTIALS_FILE}

3. Configure Laravel .env / application configuration
   menggunakan database credentials tersebut.

4. Install application dependencies separately.
   Composer TIDAK termasuk dalam PHP-FPM runtime image.

5. Check Docker Compose:

   cd ${DOCKER_APP_ROOT}
   docker compose config

6. Start PHP-FPM container:

   docker compose up -d

7. Check container:

   docker compose ps

8. Check PHP-FPM logs:

   docker compose logs -f php

9. Reload Nginx:

   systemctl reload nginx

10. Test domain:

   curl -I http://${DOMAIN_NAME}

============================================================

SUMMARY