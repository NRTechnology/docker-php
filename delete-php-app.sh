#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${1:-}"
APPS_DIR="/var/apps"
DOCKER_APPS_DIR="/opt/docker-apps"
BACKUP_DIR="/opt/docker-php/appsbackup"

APP_ROOT="${APPS_DIR}/${APP_NAME}"
APP_DOCKER="${DOCKER_APPS_DIR}/${APP_NAME}"

CONTAINER_NAME="${APP_NAME}-php"
NETWORK_NAME="${APP_NAME}-network"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
BACKUP_ROOT="${BACKUP_DIR}/${APP_NAME}/${TIMESTAMP}"

APP_BACKUP="${BACKUP_ROOT}/app.tar.gz"
DB_BACKUP="${BACKUP_ROOT}/database.sql.gz"
INFO_FILE="${BACKUP_ROOT}/backup-info.txt"

if [[ -z "$APP_NAME" ]]; then
    echo "Usage: $0 <app-name>"
    exit 1
fi

if [[ ! -d "$APP_ROOT" ]]; then
    echo "[ERROR] Application tidak ditemukan: $APP_ROOT"
    exit 1
fi

echo "============================================================"
echo " Backup & Delete PHP Application"
echo "============================================================"
echo
echo "Application : $APP_NAME"
echo "App root    : $APP_ROOT"
echo "Docker dir  : $APP_DOCKER"
echo "Backup      : $BACKUP_ROOT"
echo

read -r -p "Ketik '${APP_NAME}' untuk melanjutkan: " CONFIRM

if [[ "$CONFIRM" != "$APP_NAME" ]]; then
    echo "[ABORT] Konfirmasi tidak sesuai."
    exit 1
fi

mkdir -p "$BACKUP_ROOT"

echo
echo "[1/6] Backup application..."

tar \
    --exclude="${APP_ROOT}/data/writable/cache" \
    -czf "$APP_BACKUP" \
    -C "$APPS_DIR" \
    "$APP_NAME"

echo "[OK] Application backup selesai."

echo
echo "[2/6] Mencari konfigurasi database..."

DB_NAME=""

if [[ -f "${APP_ROOT}/htdocs/.env" ]]; then

    DB_NAME="$(grep -E '^[[:space:]]*(database\.default\.database|DB_DATABASE)[[:space:]]*=' \
        "${APP_ROOT}/htdocs/.env" 2>/dev/null \
        | tail -1 \
        | sed -E 's/^[^=]+=[[:space:]]*//; s/[[:space:]]+$//' \
        | sed 's/^["'\'']//; s/["'\'']$//')"

fi

if [[ -z "$DB_NAME" ]]; then
    echo "[ERROR] Nama database tidak ditemukan."
    echo "       Backup database dibatalkan."
    echo "       Tidak ada data yang dihapus."
    exit 1
fi

echo "[OK] Database: $DB_NAME"

echo
echo "[3/6] Backup database..."

mysqldump \
    --single-transaction \
    --routines \
    --triggers \
    "$DB_NAME" | gzip > "$DB_BACKUP"

echo "[OK] Database backup selesai."

echo
echo "[4/6] Validasi backup..."

gzip -t "$DB_BACKUP"
tar -tzf "$APP_BACKUP" >/dev/null

cat > "$INFO_FILE" <<EOF
Application : $APP_NAME
Database    : $DB_NAME
Timestamp   : $TIMESTAMP
Hostname    : $(hostname)

Application backup:
$APP_BACKUP

Database backup:
$DB_BACKUP
EOF

echo "[OK] Backup berhasil divalidasi."

echo
echo "[5/6] Menghapus container dan network..."

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker rm -f "$CONTAINER_NAME"
    echo "[OK] Container $CONTAINER_NAME dihapus."
fi

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
    echo "[OK] Network $NETWORK_NAME dihapus."
fi

echo
echo "[6/6] Menghapus aplikasi..."

rm -rf -- "$APP_DOCKER"
rm -rf -- "$APP_ROOT"

echo
echo "============================================================"
echo "[DONE] Aplikasi berhasil dihapus."
echo "============================================================"
echo
echo "Backup tersedia di:"
echo "  $BACKUP_ROOT"
echo
echo "  Application : $APP_BACKUP"
echo "  Database    : $DB_BACKUP"
echo "  Info        : $INFO_FILE"
echo