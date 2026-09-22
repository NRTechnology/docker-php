#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# CSIRT LAB END-TO-END TEST SETUP
# ============================================================
#
# Repository:
#   /opt/docker-php
#
# Struktur script:
#   /opt/docker-php/
#   ├── test-csirtlab.sh
#   ├── create-php-app.sh
#   └── scripts/
#       ├── install-requirements.sh
#       ├── build-image.sh
#       └── enable-malware-protection.sh
#
# Tujuan:
#   Menyiapkan VM fresh install menjadi environment
#   pengujian:
#
#   Nginx
#      ↓
#   PHP-FPM Docker
#      ↓
#   writable/uploads
#      ↓
#   ClamAV On-Access
#      ↓
#   LMD + YARA
#
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="csirtlab"
PHP_VERSION="8.3"
DOMAIN="csirtlab.brebeskab.go.id"

APP_ROOT="/var/apps/${APP_NAME}"
HTDOCS="${APP_ROOT}/htdocs"
DATA_DIR="${APP_ROOT}/data"
WRITABLE_DIR="${DATA_DIR}/writable"
UPLOAD_DIR="${WRITABLE_DIR}/uploads"

INDEX_PHP="${HTDOCS}/index.php"
UPLOAD_PHP="${HTDOCS}/upload.php"

NGINX_SNIPPET="/etc/nginx/snippets/${APP_NAME}-upload-security.conf"

info() {
    echo
    echo "[INFO] $*"
}

success() {
    echo "[ OK ] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
}

die() {
    error "$*"
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Script harus dijalankan sebagai root."
    fi
}

require_repository() {
    [[ -d "${SCRIPT_DIR}" ]] || die "Repository tidak ditemukan: ${SCRIPT_DIR}"

    [[ -f "${SCRIPT_DIR}/create-php-app.sh" ]] \
        || die "create-php-app.sh tidak ditemukan."

    [[ -f "${SCRIPT_DIR}/scripts/install-requirements.sh" ]] \
        || die "scripts/install-requirements.sh tidak ditemukan."

    [[ -f "${SCRIPT_DIR}/scripts/build-image.sh" ]] \
        || die "scripts/build-image.sh tidak ditemukan."

    [[ -f "${SCRIPT_DIR}/scripts/enable-malware-protection.sh" ]] \
        || die "scripts/enable-malware-protection.sh tidak ditemukan."
}

prepare_permissions() {
    info "Memastikan script memiliki permission executable..."

    chmod +x \
        "${SCRIPT_DIR}/create-php-app.sh" \
        "${SCRIPT_DIR}/scripts/install-requirements.sh" \
        "${SCRIPT_DIR}/scripts/build-image.sh" \
        "${SCRIPT_DIR}/scripts/enable-malware-protection.sh"

    success "Permission script siap."
}

run_install_requirements() {
    info "Menjalankan install-requirements.sh..."

    "${SCRIPT_DIR}/scripts/install-requirements.sh"

    success "install-requirements.sh selesai."
}

run_build_image() {
    info "Build PHP ${PHP_VERSION}..."

    "${SCRIPT_DIR}/scripts/build-image.sh" "${PHP_VERSION}"

    success "PHP ${PHP_VERSION} image berhasil dibuat."
}

run_enable_malware_protection() {
    info "Menjalankan enable-malware-protection.sh..."

    "${SCRIPT_DIR}/scripts/enable-malware-protection.sh"

    success "Malware protection selesai dikonfigurasi."
}

run_create_php_app() {
    info "Membuat aplikasi ${APP_NAME}..."

    "${SCRIPT_DIR}/create-php-app.sh" \
        "${APP_NAME}" \
        "${PHP_VERSION}" \
        "generic" \
        "${DOMAIN}"

    success "Aplikasi ${APP_NAME} berhasil dibuat."
}

create_upload_directories() {
    info "Membuat struktur upload..."

    install -d -m 0755 "${APP_ROOT}"
    install -d -m 0755 "${DATA_DIR}"
    install -d -m 0750 "${WRITABLE_DIR}"
    install -d -m 0750 "${UPLOAD_DIR}"

    chown www-data:www-data "${DATA_DIR}"
    chown www-data:www-data "${WRITABLE_DIR}"
    chown www-data:www-data "${UPLOAD_DIR}"

    success "Upload directory siap:"
    echo "       ${UPLOAD_DIR}"
}

configure_clamav_acl() {
    info "Mengkonfigurasi ACL ClamAV..."

    command -v setfacl >/dev/null 2>&1 \
        || die "setfacl tidak ditemukan."

    command -v getfacl >/dev/null 2>&1 \
        || die "getfacl tidak ditemukan."

    id clamav >/dev/null 2>&1 \
        || die "User clamav tidak ditemukan."

    id www-data >/dev/null 2>&1 \
        || die "User www-data tidak ditemukan."

    #
    # ClamAV harus dapat melakukan traversal dari /var/apps
    # sampai ke upload directory.
    #
    setfacl -m u:clamav:--x /var/apps
    setfacl -m u:clamav:--x "${APP_ROOT}"
    setfacl -m u:clamav:--x "${DATA_DIR}"

    #
    # Pada writable dan uploads ClamAV membutuhkan:
    #   r = read
    #   x = traverse
    #
    setfacl -m u:clamav:r-x "${WRITABLE_DIR}"
    setfacl -m u:clamav:r-x "${UPLOAD_DIR}"

    #
    # www-data tetap mempunyai akses penuh terhadap
    # directory writable.
    #
    setfacl -m u:www-data:rwx "${WRITABLE_DIR}"
    setfacl -m u:www-data:rwx "${UPLOAD_DIR}"

    #
    # Default ACL untuk file baru yang dibuat di upload directory.
    #
    setfacl -d -m u:www-data:rwx "${UPLOAD_DIR}"
    setfacl -d -m u:clamav:r-x "${UPLOAD_DIR}"

    success "ACL ClamAV berhasil dikonfigurasi."
}

create_index_php() {
    info "Membuat index.php..."

    cat > "${INDEX_PHP}" <<'PHP'
<?php
declare(strict_types=1);
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CSIRT Lab - Upload Test</title>
</head>

<body>

<h1>CSIRT Lab - Upload Test</h1>

<p>
    Gunakan halaman ini untuk menguji mekanisme upload
    dan ClamAV On-Access.
</p>

<form
    action="upload.php"
    method="post"
    enctype="multipart/form-data"
>

    <p>
        <label for="file">Pilih file:</label>
    </p>

    <p>
        <input
            type="file"
            name="file"
            id="file"
            required
        >
    </p>

    <p>
        <button type="submit">
            Upload
        </button>
    </p>

</form>

</body>
</html>
PHP

    chown www-data:www-data "${INDEX_PHP}"
    chmod 0644 "${INDEX_PHP}"

    success "index.php dibuat."
}

create_upload_php() {
    info "Membuat upload.php..."

    cat > "${UPLOAD_PHP}" <<'PHP'
<?php
declare(strict_types=1);

const UPLOAD_DIR = '/var/apps/csirtlab/data/writable/uploads';
const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

function failUpload(string $message, int $status = 400): never
{
    http_response_code($status);

    echo '<!DOCTYPE html>';
    echo '<html lang="id">';
    echo '<head>';
    echo '<meta charset="UTF-8">';
    echo '<title>Upload Error</title>';
    echo '</head>';
    echo '<body>';

    echo '<h1>Upload gagal</h1>';

    echo '<p>' .
        htmlspecialchars(
            $message,
            ENT_QUOTES | ENT_SUBSTITUTE,
            'UTF-8'
        ) .
        '</p>';

    echo '<p>';
    echo '<a href="index.php">Kembali</a>';
    echo '</p>';

    echo '</body>';
    echo '</html>';

    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    failUpload('Method Not Allowed', 405);
}

if (!isset($_FILES['file'])) {
    failUpload('File tidak ditemukan.');
}

$file = $_FILES['file'];

if (!is_array($file)) {
    failUpload('Format upload tidak valid.');
}

if (!isset(
    $file['error'],
    $file['size'],
    $file['tmp_name']
)) {
    failUpload('Informasi upload tidak lengkap.');
}

if ($file['error'] !== UPLOAD_ERR_OK) {
    failUpload(
        'PHP upload error code: ' .
        (int) $file['error']
    );
}

if (!is_uploaded_file($file['tmp_name'])) {
    failUpload('File upload tidak valid.');
}

if ((int) $file['size'] > MAX_FILE_SIZE) {
    failUpload(
        'Ukuran file melebihi batas 10 MB.',
        413
    );
}

if (!is_dir(UPLOAD_DIR)) {
    failUpload(
        'Directory upload tidak tersedia.',
        500
    );
}

if (!is_writable(UPLOAD_DIR)) {
    failUpload(
        'Directory upload tidak writable.',
        500
    );
}

/*
 * Nama file asli dari client tidak dipercaya.
 *
 * File disimpan menggunakan random filename
 * dengan extension .upload agar test tidak
 * bergantung pada extension file.
 */
$filename = bin2hex(random_bytes(16)) . '.upload';

$destination = UPLOAD_DIR . '/' . $filename;

if (!move_uploaded_file(
    $file['tmp_name'],
    $destination
)) {
    failUpload(
        'Gagal menyimpan file upload.',
        500
    );
}

/*
 * File upload tidak membutuhkan execute permission.
 */
chmod($destination, 0640);

echo '<!DOCTYPE html>';
echo '<html lang="id">';
echo '<head>';
echo '<meta charset="UTF-8">';
echo '<meta name="viewport" content="width=device-width, initial-scale=1.0">';
echo '<title>Upload Result</title>';
echo '</head>';
echo '<body>';

echo '<h1>Upload berhasil</h1>';

echo '<p>File berhasil diterima oleh aplikasi.</p>';

echo '<p>Nama file:</p>';

echo '<pre>' .
    htmlspecialchars(
        $filename,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    ) .
    '</pre>';

echo '<p>Lokasi:</p>';

echo '<pre>' .
    htmlspecialchars(
        $destination,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    ) .
    '</pre>';

echo '<p>';
echo '<a href="index.php">Upload file lain</a>';
echo '</p>';

echo '</body>';
echo '</html>';
PHP

    chown www-data:www-data "${UPLOAD_PHP}"
    chmod 0644 "${UPLOAD_PHP}"

    success "upload.php dibuat."
}

configure_nginx_upload_protection() {
    info "Mengkonfigurasi proteksi upload directory pada Nginx..."

    command -v nginx >/dev/null 2>&1 \
        || die "Nginx tidak ditemukan."

    local vhost="/etc/nginx/sites-available/${DOMAIN}"

    if [[ ! -f "${vhost}" ]]; then
        die "Virtual host tidak ditemukan: ${vhost}"
    fi

    install -d -m 0755 /etc/nginx/snippets

    cat > "${NGINX_SNIPPET}" <<'NGINX'
#
# CSIRT Lab upload security
#
# Directory upload diperlakukan sebagai data.
# PHP tidak boleh dieksekusi dari directory ini.
#

location ^~ /data/writable/uploads/ {
    autoindex off;

    location ~ \.php$ {
        return 403;
    }

    try_files $uri =404;
}

location ~* ^/data/writable/uploads/.*\.(php|phtml|php[0-9]?|phar|cgi|pl|py|sh)$ {
    return 403;
}
NGINX

    #
    # Include hanya ditambahkan satu kali.
    #
    if ! grep -Fq \
        "include ${NGINX_SNIPPET};" \
        "${vhost}"; then

        cp "${vhost}" \
            "${vhost}.bak.$(date +%Y%m%d-%H%M%S)"

        #
        # Insert sebelum closing server block terakhir.
        #
        awk -v snippet="${NGINX_SNIPPET}" '
        BEGIN {
            inserted = 0
        }

        {
            if (!inserted && $0 ~ /^[[:space:]]*}[[:space:]]*$/) {
                print "    include " snippet ";"
                inserted = 1
            }

            print
        }
        ' "${vhost}" > "${vhost}.new"

        mv "${vhost}.new" "${vhost}"
    fi

    success "Proteksi upload Nginx dikonfigurasi."
}

validate_nginx() {
    info "Memvalidasi konfigurasi Nginx..."

    nginx -t

    systemctl reload nginx

    success "Nginx valid dan berhasil di-reload."
}

validate_php_files() {
    info "Memvalidasi file PHP..."

    if command -v php >/dev/null 2>&1; then
        php -l "${INDEX_PHP}"
        php -l "${UPLOAD_PHP}"
    else
        warn "PHP CLI host tidak tersedia."
        warn "Syntax PHP akan diverifikasi dari container saat diperlukan."
    fi

    success "File PHP selesai dibuat."
}

show_configuration() {
    echo
    echo "============================================================"
    echo " CSIRT LAB TEST ENVIRONMENT READY"
    echo "============================================================"
    echo
    echo "Repository:"
    echo "  ${SCRIPT_DIR}"
    echo
    echo "Application:"
    echo "  ${APP_ROOT}"
    echo
    echo "Domain:"
    echo "  ${DOMAIN}"
    echo
    echo "Document Root:"
    echo "  ${HTDOCS}"
    echo
    echo "Upload Directory:"
    echo "  ${UPLOAD_DIR}"
    echo
    echo "PHP:"
    echo "  ${INDEX_PHP}"
    echo "  ${UPLOAD_PHP}"
    echo
    echo "============================================================"
    echo " ACL"
    echo "============================================================"
    echo

    getfacl -p "${UPLOAD_DIR}"

    echo
    echo "============================================================"
    echo " NEXT TEST"
    echo "============================================================"
    echo
    echo "1. Buka:"
    echo "   https://${DOMAIN}/"
    echo
    echo "2. Upload file benign."
    echo
    echo "3. Monitor ClamAV:"
    echo "   journalctl -u clamav-daemon -f"
    echo
    echo "4. Lihat upload directory:"
    echo "   ls -lah ${UPLOAD_DIR}"
    echo
    echo "5. Setelah test benign berhasil,"
    echo "   lakukan test signature malware/YARA."
    echo
    echo "============================================================"
}

main() {

    require_root

    cd "${SCRIPT_DIR}"

    info "Repository root: ${SCRIPT_DIR}"

    require_repository

    prepare_permissions

    run_install_requirements

    run_build_image

    run_enable_malware_protection

    run_create_php_app

    create_upload_directories

    configure_clamav_acl

    create_index_php

    create_upload_php

    validate_php_files

    configure_nginx_upload_protection

    validate_nginx

    show_configuration
}

main "$@"