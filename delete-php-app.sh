#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# delete-php-app.sh
# Backup and delete PHP application
# ============================================================

SCRIPT_NAME="delete-php-app.sh"
SCRIPT_VERSION="1.2.0"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

APPS_DIR="/var/apps"
DOCKER_APPS_DIR="/opt/docker-apps"
BACKUP_DIR="/opt/docker-php/appsbackup"

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

# ------------------------------------------------------------
# Input
# ------------------------------------------------------------

APP_NAME="${1:-}"

if [[ -z "$APP_NAME" ]]; then
    echo "Usage: $0 <app-name>"
    echo
    echo "Example:"
    echo "  $0 testa"
    exit 1
fi

# Prevent dangerous path traversal / absolute path input
if [[ ! "$APP_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "[ERROR] Nama aplikasi tidak valid: $APP_NAME"
    echo "[ERROR] Gunakan hanya huruf, angka, titik, underscore, dan dash."
    exit 1
fi

# ------------------------------------------------------------
# Application paths
# ------------------------------------------------------------

APP_ROOT="${APPS_DIR}/${APP_NAME}"
APP_DOCKER="${DOCKER_APPS_DIR}/${APP_NAME}"

NGINX_AVAILABLE="${NGINX_SITES_AVAILABLE}/${APP_NAME}.conf"
NGINX_ENABLED="${NGINX_SITES_ENABLED}/${APP_NAME}.conf"

CONTAINER_NAME="${APP_NAME}-php"
NETWORK_NAME="${APP_NAME}-network"

# Database name follows application name
DB_NAME="${APP_NAME}"

# ------------------------------------------------------------
# Backup paths
# ------------------------------------------------------------

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"

BACKUP_ROOT="${BACKUP_DIR}/${APP_NAME}/${TIMESTAMP}"

APP_BACKUP="${BACKUP_ROOT}/app.tar.gz"
DB_BACKUP="${BACKUP_ROOT}/database.sql.gz"
INFO_FILE="${BACKUP_ROOT}/backup-info.txt"

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

if [[ ! -d "$APP_ROOT" ]]; then
    echo "[ERROR] Application tidak ditemukan:"
    echo "        $APP_ROOT"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] Docker tidak ditemukan."
    exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
    echo "[ERROR] tar tidak ditemukan."
    exit 1
fi

if ! command -v mysqldump >/dev/null 2>&1; then
    echo "[ERROR] mysqldump tidak ditemukan."
    exit 1
fi

if ! command -v mariadb >/dev/null 2>&1; then
    echo "[ERROR] mariadb client tidak ditemukan."
    exit 1
fi

if ! command -v gzip >/dev/null 2>&1; then
    echo "[ERROR] gzip tidak ditemukan."
    exit 1
fi

# ------------------------------------------------------------
# Header
# ------------------------------------------------------------

echo "============================================================"
echo " Backup & Delete PHP Application"
echo "============================================================"
echo
echo "Script      : ${SCRIPT_NAME}"
echo "Version     : ${SCRIPT_VERSION}"
echo
echo "Application : ${APP_NAME}"
echo "App root    : ${APP_ROOT}"
echo "Docker dir  : ${APP_DOCKER}"
echo "Container   : ${CONTAINER_NAME}"
echo "Network     : ${NETWORK_NAME}"
echo "Database    : ${DB_NAME}"
echo
echo "Nginx:"
echo "  Available : ${NGINX_AVAILABLE}"
echo "  Enabled   : ${NGINX_ENABLED}"
echo
echo "Backup      : ${BACKUP_ROOT}"
echo

echo "PERINGATAN:"
echo "Aplikasi, database, MariaDB user, Docker resources,"
echo "dan konfigurasi Nginx akan dihapus setelah backup berhasil."
echo
echo "Yang akan dihapus:"
echo "  - Database         : ${DB_NAME}"
echo "  - MariaDB user     : ${APP_NAME}"
echo "  - Docker container : ${CONTAINER_NAME}"
echo "  - Docker network   : ${NETWORK_NAME}"
echo "  - Docker config    : ${APP_DOCKER}"
echo "  - Application      : ${APP_ROOT}"
echo "  - Nginx available  : ${NGINX_AVAILABLE}"
echo "  - Nginx enabled    : ${NGINX_ENABLED}"
echo
echo "Database akan dibackup terlebih dahulu."
echo

# ------------------------------------------------------------
# First confirmation
# ------------------------------------------------------------

read -r -p "Ketik '${APP_NAME}' untuk melanjutkan: " CONFIRM

if [[ "$CONFIRM" != "$APP_NAME" ]]; then
    echo
    echo "[ABORT] Konfirmasi tidak sesuai."
    exit 1
fi

# ------------------------------------------------------------
# Prepare backup directory
# ------------------------------------------------------------

mkdir -p "$BACKUP_ROOT"

echo
echo "============================================================"
echo "[1/7] Backup application"
echo "============================================================"

# Backup seluruh /var/apps/<app>
tar \
    -czf "$APP_BACKUP" \
    -C "$APPS_DIR" \
    "$APP_NAME"

echo "[OK] Application backup selesai."
echo "     $APP_BACKUP"

# ------------------------------------------------------------
# Check database
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[2/7] Memeriksa database"
echo "============================================================"

if ! mariadb \
    --batch \
    --skip-column-names \
    -e "SELECT SCHEMA_NAME
        FROM INFORMATION_SCHEMA.SCHEMATA
        WHERE SCHEMA_NAME='${DB_NAME}';" \
    | grep -Fxq "$DB_NAME"; then

    echo "[ERROR] Database '${DB_NAME}' tidak ditemukan."
    echo
    echo "Backup database dibatalkan."
    echo "Tidak ada data yang dihapus."
    echo
    echo "Application backup yang sudah dibuat:"
    echo "  $APP_BACKUP"
    echo
    exit 1
fi

echo "[OK] Database ditemukan: ${DB_NAME}"

# ------------------------------------------------------------
# Backup database
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[3/7] Backup database"
echo "============================================================"

mysqldump \
    --single-transaction \
    --routines \
    --triggers \
    "$DB_NAME" \
    | gzip > "$DB_BACKUP"

echo "[OK] Database backup selesai."
echo "     $DB_BACKUP"

# ------------------------------------------------------------
# Validate backup
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[4/7] Validasi backup"
echo "============================================================"

echo "[CHECK] Application backup..."

if ! tar -tzf "$APP_BACKUP" >/dev/null 2>&1; then
    echo "[ERROR] Application backup tidak valid."
    echo "Tidak ada data yang dihapus."
    exit 1
fi

echo "[OK] Application backup valid."

echo
echo "[CHECK] Database backup..."

if ! gzip -t "$DB_BACKUP" >/dev/null 2>&1; then
    echo "[ERROR] Database backup tidak valid."
    echo "Tidak ada data yang dihapus."
    exit 1
fi

echo "[OK] Database backup valid."

# ------------------------------------------------------------
# Collect MariaDB users
# ------------------------------------------------------------

echo
echo "[CHECK] Memeriksa MariaDB user '${APP_NAME}'..."

DB_USER_HOSTS="$(
    mariadb \
        --batch \
        --skip-column-names \
        -e "SELECT Host
            FROM mysql.user
            WHERE User='${APP_NAME}'
            ORDER BY Host;"
)"

if [[ -n "$DB_USER_HOSTS" ]]; then
    echo "[INFO] MariaDB user ditemukan:"
    while IFS= read -r HOST; do
        [[ -z "$HOST" ]] && continue
        echo "  - ${APP_NAME}@${HOST}"
    done <<< "$DB_USER_HOSTS"
else
    echo "[INFO] MariaDB user '${APP_NAME}' tidak ditemukan."
fi

# ------------------------------------------------------------
# Backup information
# ------------------------------------------------------------

cat > "$INFO_FILE" <<EOF
Application : ${APP_NAME}
Database    : ${DB_NAME}
Timestamp   : ${TIMESTAMP}
Hostname    : $(hostname)

Application root:
${APP_ROOT}

Docker configuration:
${APP_DOCKER}

Container:
${CONTAINER_NAME}

Network:
${NETWORK_NAME}

Nginx sites-available:
${NGINX_AVAILABLE}

Nginx sites-enabled:
${NGINX_ENABLED}

MariaDB user:
${APP_NAME}

MariaDB user hosts:
${DB_USER_HOSTS:-NONE}

Application backup:
${APP_BACKUP}

Database backup:
${DB_BACKUP}

Database and MariaDB user will be dropped after backup validation.
EOF

echo
echo "[OK] Backup metadata dibuat:"
echo "     $INFO_FILE"

# ------------------------------------------------------------
# Final confirmation before deletion
# ------------------------------------------------------------

echo
echo "============================================================"
echo " BACKUP BERHASIL"
echo "============================================================"
echo
echo "Backup aplikasi : OK"
echo "Backup database : OK"
echo
echo "PERINGATAN FINAL:"
echo
echo "Aplikasi akan dihapus:"
echo "  ${APP_ROOT}"
echo
echo "Konfigurasi Docker akan dihapus:"
echo "  ${APP_DOCKER}"
echo
echo "Konfigurasi Nginx akan dihapus:"
echo "  ${NGINX_AVAILABLE}"
echo "  ${NGINX_ENABLED}"
echo
echo "Database akan DIHAPUS:"
echo "  ${DB_NAME}"
echo
echo "MariaDB user akan DIHAPUS:"
if [[ -n "$DB_USER_HOSTS" ]]; then
    while IFS= read -r HOST; do
        [[ -z "$HOST" ]] && continue
        echo "  ${APP_NAME}@${HOST}"
    done <<< "$DB_USER_HOSTS"
else
    echo "  Tidak ditemukan"
fi
echo
echo "Backup tetap tersedia di:"
echo "  ${BACKUP_ROOT}"
echo

read -r -p "Ketik 'DELETE' untuk menghapus aplikasi, database, dan user MariaDB: " DELETE_CONFIRM

if [[ "$DELETE_CONFIRM" != "DELETE" ]]; then
    echo
    echo "[ABORT] Penghapusan dibatalkan."
    echo
    echo "Backup tetap tersedia di:"
    echo "  $BACKUP_ROOT"
    exit 0
fi

# ------------------------------------------------------------
# Drop database
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[5/7] Menghapus database dan MariaDB user"
echo "============================================================"

if mariadb \
    -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"; then

    echo "[OK] Database dihapus:"
    echo "     ${DB_NAME}"

else

    echo "[ERROR] Gagal menghapus database:"
    echo "        ${DB_NAME}"
    echo
    echo "Application dan Docker resources BELUM dihapus."
    echo
    echo "Backup tetap tersedia di:"
    echo "  ${BACKUP_ROOT}"

    exit 1
fi

# ------------------------------------------------------------
# Drop MariaDB users
# ------------------------------------------------------------

if [[ -n "$DB_USER_HOSTS" ]]; then

    while IFS= read -r HOST; do

        [[ -z "$HOST" ]] && continue

        # Escape backticks in host just in case
        ESCAPED_HOST="${HOST//\`/\`\`}"

        if mariadb \
            -e "DROP USER IF EXISTS '${APP_NAME}'@'${ESCAPED_HOST}';"; then

            echo "[OK] MariaDB user dihapus:"
            echo "     ${APP_NAME}@${HOST}"

        else

            echo "[ERROR] Gagal menghapus MariaDB user:"
            echo "        ${APP_NAME}@${HOST}"
            echo
            echo "Application dan Docker resources BELUM dihapus."
            echo
            echo "Backup tetap tersedia di:"
            echo "  ${BACKUP_ROOT}"

            exit 1
        fi

    done <<< "$DB_USER_HOSTS"

else

    echo "[INFO] MariaDB user '${APP_NAME}' tidak ditemukan."

fi

# ------------------------------------------------------------
# Remove Docker resources
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[6/7] Menghapus Docker resources"
echo "============================================================"

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then

    docker rm -f "$CONTAINER_NAME"

    echo "[OK] Container dihapus:"
    echo "     ${CONTAINER_NAME}"

else

    echo "[INFO] Container tidak ditemukan:"
    echo "       ${CONTAINER_NAME}"

fi

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then

    if docker network rm "$NETWORK_NAME" >/dev/null 2>&1; then

        echo "[OK] Network dihapus:"
        echo "     ${NETWORK_NAME}"

    else

        echo "[WARNING] Network tidak dapat dihapus:"
        echo "          ${NETWORK_NAME}"
        echo
        echo "[INFO] Network mungkin masih digunakan container lain."
        echo "[INFO] Proses dilanjutkan."

    fi

else

    echo "[INFO] Network tidak ditemukan:"
    echo "       ${NETWORK_NAME}"

fi

# ------------------------------------------------------------
# Remove Nginx configuration
# ------------------------------------------------------------

echo
echo "[INFO] Menghapus konfigurasi Nginx..."

if [[ -f "$NGINX_ENABLED" || -L "$NGINX_ENABLED" ]]; then

    rm -f -- "$NGINX_ENABLED"

    echo "[OK] Nginx sites-enabled dihapus:"
    echo "     ${NGINX_ENABLED}"

else

    echo "[INFO] Nginx sites-enabled tidak ditemukan:"
    echo "       ${NGINX_ENABLED}"

fi

if [[ -f "$NGINX_AVAILABLE" || -L "$NGINX_AVAILABLE" ]]; then

    rm -f -- "$NGINX_AVAILABLE"

    echo "[OK] Nginx sites-available dihapus:"
    echo "     ${NGINX_AVAILABLE}"

else

    echo "[INFO] Nginx sites-available tidak ditemukan:"
    echo "       ${NGINX_AVAILABLE}"

fi

# ------------------------------------------------------------
# Remove application files
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[7/7] Menghapus application files"
echo "============================================================"

if [[ -d "$APP_DOCKER" ]]; then

    rm -rf -- "$APP_DOCKER"

    echo "[OK] Docker configuration dihapus:"
    echo "     ${APP_DOCKER}"

else

    echo "[INFO] Docker configuration tidak ditemukan:"
    echo "       ${APP_DOCKER}"

fi

if [[ -d "$APP_ROOT" ]]; then

    rm -rf -- "$APP_ROOT"

    echo "[OK] Application dihapus:"
    echo "     ${APP_ROOT}"

else

    echo "[INFO] Application directory tidak ditemukan:"
    echo "       ${APP_ROOT}"

fi

# ------------------------------------------------------------
# Final
# ------------------------------------------------------------

echo
echo "============================================================"
echo "[DONE] Aplikasi dan seluruh resource berhasil dihapus"
echo "============================================================"
echo
echo "Application : ${APP_NAME}"
echo "Database    : ${DB_NAME}"
echo "MariaDB user: ${APP_NAME}"
echo
echo "Nginx:"
echo "  Available : ${NGINX_AVAILABLE}"
echo "  Enabled   : ${NGINX_ENABLED}"
echo
echo "Backup tersedia di:"
echo "  ${BACKUP_ROOT}"
echo
echo "  Application : ${APP_BACKUP}"
echo "  Database    : ${DB_BACKUP}"
echo "  Info        : ${INFO_FILE}"
echo