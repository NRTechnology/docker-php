#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# docker-php
# System Requirements Checker & Installer
#
# Checks and installs:
#   - Ubuntu/Debian APT requirements
#   - Nginx
#   - Docker Engine
#   - Docker Compose Plugin
#   - MariaDB Server
#   - ClamAV
#   - Linux Malware Detect (LMD)
#   - YARA
#
# Security tools are installed first, then the administrator is asked
# whether each tool should be enabled automatically.
#
# MariaDB Configuration:
#   - bind-address = 0.0.0.0
#   - root access restricted to localhost
#   - root password is NOT configured by this script
#
# Supported:
#   - Ubuntu
#   - Debian
#
# Run as root:
#   sudo ./scripts/check-requirements.sh
# ============================================================

SCRIPT_NAME="$(basename "$0")"

# Repository root and backup directory
APP_ROOT="/opt/docker-php"
APP_BACKUP="${APP_ROOT}/backup"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

section() {
    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

# ------------------------------------------------------------
# Error Handler
# ------------------------------------------------------------

trap 'error "Script gagal pada baris ${LINENO}: ${BASH_COMMAND}"' ERR

# ------------------------------------------------------------
# Root Check
# ------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    error "Script harus dijalankan sebagai root."
    echo
    echo "Gunakan:"
    echo
    echo "    sudo ./${SCRIPT_NAME}"
    echo
    exit 1
fi

# ------------------------------------------------------------
# OS Detection
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    error "Tidak dapat mendeteksi operating system."
    exit 1
fi

source /etc/os-release

OS_ID="${ID:-}"
OS_VERSION="${VERSION_ID:-}"
OS_CODENAME="${VERSION_CODENAME:-}"

case "${OS_ID}" in
    ubuntu|debian)
        ;;
    *)
        error "Operating system tidak didukung: ${OS_ID}"
        error "Script ini hanya mendukung Ubuntu dan Debian."
        exit 1
        ;;
esac

section "SYSTEM INFORMATION"

info "Operating System : ${PRETTY_NAME:-${OS_ID}}"
info "OS ID            : ${OS_ID}"
info "Version          : ${OS_VERSION}"
info "Codename         : ${OS_CODENAME:-unknown}"
info "Architecture     : $(dpkg --print-architecture)"

# ------------------------------------------------------------
# Check Architecture
# ------------------------------------------------------------

ARCH="$(dpkg --print-architecture)"

case "${ARCH}" in
    amd64|arm64|armhf|ppc64el|s390x)
        success "Architecture didukung: ${ARCH}"
        ;;
    *)
        warning "Architecture ${ARCH} belum diverifikasi untuk script ini."
        ;;
esac

# ------------------------------------------------------------
# Ubuntu Main Repository
# ------------------------------------------------------------

configure_ubuntu_repository() {
    if [[ "${OS_ID}" != "ubuntu" ]]; then
        info "OS bukan Ubuntu. Repository Debian tidak diubah."
        return
    fi

    section "UBUNTU MAIN REPOSITORY"

    local codename="${OS_CODENAME}"
    local arch
    local ubuntu_sources="/etc/apt/sources.list.d/ubuntu.sources"
    local legacy_sources="/etc/apt/sources.list"
    local backup_dir="${APP_BACKUP}/apt"
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"

    if [[ -z "${codename}" ]]; then
        error "Ubuntu codename tidak dapat dideteksi."
        exit 1
    fi

    mkdir -p "${backup_dir}"

    info "Ubuntu codename : ${codename}"
    info "Menggunakan official Ubuntu main archive."

    # Ubuntu 24.04+ uses deb822 ubuntu.sources.
    if [[ -f "${ubuntu_sources}" ]]; then
        cp -a "${ubuntu_sources}" \
            "${backup_dir}/ubuntu.sources.${timestamp}.bak"
        success "Backup repository Ubuntu dibuat:"
        info "${backup_dir}/ubuntu.sources.${timestamp}.bak"
    fi

    # Preserve legacy sources.list before changing it.
    if [[ -f "${legacy_sources}" ]]; then
        cp -a "${legacy_sources}" \
            "${backup_dir}/sources.list.${timestamp}.bak"
    fi

    if [[ -f "${ubuntu_sources}" ]] || dpkg --compare-versions "${OS_VERSION}" ge "24.04"; then
        cat > "${ubuntu_sources}" <<EOF
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: ${codename} ${codename}-updates ${codename}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu
Suites: ${codename}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

        # Prevent duplicate/old Ubuntu entries in legacy sources.list
        # from continuing to use an Indonesian mirror.
        if [[ -f "${legacy_sources}" ]]; then
            sed -i -E \
                '/^[[:space:]]*deb(-src)?[[:space:]]+https?:\/\/([^[:space:]]+\.)?ubuntu\.com\/ubuntu/d' \
                "${legacy_sources}"
            sed -i -E \
                '/^[[:space:]]*deb(-src)?[[:space:]]+https?:\/\/[^[:space:]]*ubuntu\.com\/ubuntu/d' \
                "${legacy_sources}"
        fi
    else
        cat > "${legacy_sources}" <<EOF
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
    fi

    success "Repository Ubuntu diarahkan ke official archive."
    info "Main archive : http://archive.ubuntu.com/ubuntu"
    info "Security     : http://security.ubuntu.com/ubuntu"
}

configure_ubuntu_repository

# ------------------------------------------------------------
# APT Update
# ------------------------------------------------------------

section "APT PACKAGE INFORMATION"

info "Updating APT package index..."

if ! apt-get update; then
    error "APT repository tidak dapat diakses."
    error "Periksa koneksi jaringan dan konfigurasi repository."
    exit 1
fi

success "APT package index berhasil diperbarui."

# ------------------------------------------------------------
# Basic Packages
# ------------------------------------------------------------

section "BASIC PACKAGES"

BASIC_PACKAGES=(
    ca-certificates
    curl
    gnupg
    lsb-release
    apt-transport-https
)

info "Memastikan package dasar tersedia..."

apt-get install -y "${BASIC_PACKAGES[@]}"

success "Package dasar tersedia."

# ------------------------------------------------------------
# NGINX
# ------------------------------------------------------------

section "CHECK NGINX"

if command -v nginx >/dev/null 2>&1; then

    NGINX_VERSION="$(nginx -v 2>&1 | sed 's#nginx version: nginx/##')"

    success "Nginx sudah tersedia."
    info "Version: ${NGINX_VERSION}"

else

    warning "Nginx belum tersedia."
    info "Menginstall Nginx..."

    apt-get install -y nginx

    success "Nginx berhasil diinstall."

fi

# ------------------------------------------------------------
# NGINX SERVICE
# ------------------------------------------------------------

if systemctl list-unit-files nginx.service >/dev/null 2>&1; then

    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        success "Nginx sudah enabled."
    else
        info "Mengaktifkan Nginx saat boot..."
        systemctl enable nginx
        success "Nginx berhasil di-enable."
    fi

    if systemctl is-active --quiet nginx; then
        success "Nginx sedang running."
    else
        warning "Nginx belum running."
        info "Menjalankan Nginx..."

        systemctl start nginx

        if systemctl is-active --quiet nginx; then
            success "Nginx berhasil dijalankan."
        else
            error "Nginx gagal dijalankan."
            systemctl status nginx --no-pager || true
            exit 1
        fi
    fi

fi

# ------------------------------------------------------------
# NGINX CONFIG TEST
# ------------------------------------------------------------

info "Testing konfigurasi Nginx..."

if nginx -t; then
    success "Konfigurasi Nginx valid."
else
    error "Konfigurasi Nginx tidak valid."
    exit 1
fi

# ------------------------------------------------------------
# DOCKER
# ------------------------------------------------------------

section "CHECK DOCKER"

if command -v docker >/dev/null 2>&1; then

    DOCKER_VERSION="$(docker --version)"

    success "Docker sudah tersedia."
    info "${DOCKER_VERSION}"

else

    warning "Docker belum tersedia."
    info "Menginstall Docker Engine dari official Docker APT repository..."

    # --------------------------------------------------------
    # Remove conflicting unofficial packages
    # --------------------------------------------------------

    CONFLICTING_PACKAGES=(
        docker.io
        docker-compose
        docker-compose-v2
        docker-doc
        docker-buildx
        podman-docker
        containerd
        runc
    )

    info "Memeriksa package Docker yang berpotensi conflict..."

    apt-get remove -y \
        "${CONFLICTING_PACKAGES[@]}" \
        2>/dev/null || true

    # --------------------------------------------------------
    # Docker GPG Key
    # --------------------------------------------------------

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL \
        "https://download.docker.com/linux/${OS_ID}/gpg" \
        -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    # --------------------------------------------------------
    # Docker Repository
    # --------------------------------------------------------

    if [[ "${OS_ID}" == "ubuntu" ]]; then

        DOCKER_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME}}"

        cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${DOCKER_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    elif [[ "${OS_ID}" == "debian" ]]; then

        DOCKER_CODENAME="${VERSION_CODENAME}"

        cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${DOCKER_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    fi

    info "Docker repository berhasil dikonfigurasi."

    apt-get update

    # --------------------------------------------------------
    # Docker Engine
    # --------------------------------------------------------

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    success "Docker Engine berhasil diinstall."

fi

# ------------------------------------------------------------
# DOCKER SERVICE
# ------------------------------------------------------------

if systemctl list-unit-files docker.service >/dev/null 2>&1; then

    if systemctl is-enabled --quiet docker 2>/dev/null; then
        success "Docker sudah enabled."
    else
        info "Mengaktifkan Docker saat boot..."
        systemctl enable docker
        success "Docker berhasil di-enable."
    fi

    if systemctl is-active --quiet docker; then
        success "Docker sedang running."
    else
        warning "Docker belum running."
        info "Menjalankan Docker..."

        systemctl start docker

        if systemctl is-active --quiet docker; then
            success "Docker berhasil dijalankan."
        else
            error "Docker gagal dijalankan."
            systemctl status docker --no-pager || true
            exit 1
        fi
    fi

fi

# ------------------------------------------------------------
# DOCKER VERSION
# ------------------------------------------------------------

if command -v docker >/dev/null 2>&1; then

    info "Docker version:"
    docker --version

    echo

    info "Docker Compose version:"

    if docker compose version >/dev/null 2>&1; then
        docker compose version
        success "Docker Compose Plugin tersedia."
    else
        error "Docker Compose Plugin tidak tersedia."
        exit 1
    fi

fi

# ------------------------------------------------------------
# DOCKER INFO
# ------------------------------------------------------------

info "Testing Docker daemon..."

if docker info >/dev/null 2>&1; then
    success "Docker daemon dapat diakses."
else
    error "Docker daemon tidak dapat diakses."
    exit 1
fi

# ------------------------------------------------------------
# MARIADB
# ------------------------------------------------------------

section "CHECK MARIADB"

if command -v mariadb >/dev/null 2>&1; then

    MARIADB_VERSION="$(mariadb --version)"

    success "MariaDB command tersedia."
    info "${MARIADB_VERSION}"

else

    warning "MariaDB belum tersedia."
    info "Menginstall MariaDB Server dan Client..."

    apt-get install -y \
        mariadb-server \
        mariadb-client

    success "MariaDB berhasil diinstall."

fi

# ------------------------------------------------------------
# MARIADB SERVICE
# ------------------------------------------------------------

if systemctl list-unit-files mariadb.service >/dev/null 2>&1; then

    if systemctl is-enabled --quiet mariadb 2>/dev/null; then
        success "MariaDB sudah enabled."
    else
        info "Mengaktifkan MariaDB saat boot..."
        systemctl enable mariadb
        success "MariaDB berhasil di-enable."
    fi

    if systemctl is-active --quiet mariadb; then
        success "MariaDB sedang running."
    else
        warning "MariaDB belum running."
        info "Menjalankan MariaDB..."

        systemctl start mariadb

        if systemctl is-active --quiet mariadb; then
            success "MariaDB berhasil dijalankan."
        else
            error "MariaDB gagal dijalankan."
            systemctl status mariadb --no-pager || true
            exit 1
        fi
    fi

else

    error "mariadb.service tidak ditemukan."
    exit 1

fi

# ------------------------------------------------------------
# MARIADB VERSION
# ------------------------------------------------------------

info "MariaDB version:"
mariadb --version

# ------------------------------------------------------------
# MARIADB CONFIGURATION
# ------------------------------------------------------------

section "MARIADB NETWORK CONFIGURATION"

MARIADB_CONFIG=""

if [[ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]]; then
    MARIADB_CONFIG="/etc/mysql/mariadb.conf.d/50-server.cnf"
elif [[ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]]; then
    MARIADB_CONFIG="/etc/mysql/mariadb.conf.d/50-server.cnf"
elif [[ -f /etc/mysql/my.cnf ]]; then
    MARIADB_CONFIG="/etc/mysql/my.cnf"
else
    error "File konfigurasi MariaDB tidak ditemukan."
    exit 1
fi

info "MariaDB configuration:"
info "${MARIADB_CONFIG}"

# ------------------------------------------------------------
# Backup MariaDB Configuration
# ------------------------------------------------------------

MARIADB_BACKUP="${MARIADB_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"

cp -a "${MARIADB_CONFIG}" "${MARIADB_BACKUP}"

success "Backup konfigurasi MariaDB dibuat:"
info "${MARIADB_BACKUP}"

# ------------------------------------------------------------
# Configure bind-address
# ------------------------------------------------------------

info "Mengatur MariaDB bind-address menjadi 0.0.0.0..."

if grep -Eq '^[[:space:]]*bind-address[[:space:]]*=' "${MARIADB_CONFIG}"; then

    sed -i -E \
        's/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' \
        "${MARIADB_CONFIG}"

elif grep -Eq '^[[:space:]]*#?[[:space:]]*bind-address[[:space:]]*=' "${MARIADB_CONFIG}"; then

    sed -i -E \
        's/^[[:space:]]*#?[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' \
        "${MARIADB_CONFIG}"

else

    cat >> "${MARIADB_CONFIG}" <<'EOF'

# ============================================================
# docker-php
# MariaDB network configuration
# ============================================================

bind-address = 0.0.0.0
EOF

fi

success "MariaDB bind-address diset ke 0.0.0.0."

# ------------------------------------------------------------
# Validate MariaDB Configuration
# ------------------------------------------------------------

info "Validating konfigurasi MariaDB..."

if mariadbd --help --verbose >/dev/null 2>&1; then
    success "Konfigurasi MariaDB valid."
elif mysqld --help --verbose >/dev/null 2>&1; then
    success "Konfigurasi MariaDB valid."
else
    error "Konfigurasi MariaDB gagal divalidasi."
    exit 1
fi

# ------------------------------------------------------------
# Restart MariaDB
# ------------------------------------------------------------

info "Restarting MariaDB..."

systemctl restart mariadb

if systemctl is-active --quiet mariadb; then
    success "MariaDB berhasil direstart."
else
    error "MariaDB gagal berjalan setelah restart."
    systemctl status mariadb --no-pager || true
    exit 1
fi

# ------------------------------------------------------------
# Verify MariaDB bind-address
# ------------------------------------------------------------

info "Memeriksa bind-address MariaDB..."

MARIADB_BIND_ADDRESS="$(
    mariadb -N -B \
        -e "SHOW VARIABLES LIKE 'bind_address';" \
        2>/dev/null \
        | awk '{print $2}'
)"

if [[ "${MARIADB_BIND_ADDRESS}" == "0.0.0.0" ]]; then

    success "MariaDB menerima koneksi pada 0.0.0.0."

else

    error "MariaDB bind-address bukan 0.0.0.0."
    error "Current value: ${MARIADB_BIND_ADDRESS:-unknown}"
    exit 1

fi

# ------------------------------------------------------------
# MARIADB ROOT SECURITY
# ------------------------------------------------------------

section "MARIADB ROOT SECURITY"

info "Memeriksa account root MariaDB..."

ROOT_ACCOUNTS="$(
    mariadb -N -B \
        -e "SELECT User, Host FROM mysql.user WHERE User='root' ORDER BY Host;" \
        2>/dev/null || true
)"

echo
echo "Root accounts:"
echo "${ROOT_ACCOUNTS:-Tidak ditemukan}"
echo

REMOTE_ROOT_ACCOUNTS="$(
    mariadb -N -B \
        -e "
            SELECT CONCAT(User, '@', Host)
            FROM mysql.user
            WHERE User = 'root'
              AND Host NOT IN ('localhost', '127.0.0.1', '::1');
        " \
        2>/dev/null || true
)"

if [[ -n "${REMOTE_ROOT_ACCOUNTS}" ]]; then

    error "Ditemukan account root yang dapat digunakan dari luar localhost:"
    echo "${REMOTE_ROOT_ACCOUNTS}"
    echo

    error "Script tidak menghapus account root remote secara otomatis."
    error "Periksa account tersebut secara manual sebelum menghapus atau mengubahnya."
    exit 1

fi

success "Root hanya menerima koneksi dari localhost."

# ------------------------------------------------------------
# ROOT PASSWORD WARNING
# ------------------------------------------------------------

echo

warning "PERINGATAN PASSWORD ROOT"
warning "Script ini TIDAK mengatur password root MariaDB."
warning "Password root dibiarkan sesuai kondisi instalasi/server."
warning "Jangan membuat root@'%' atau account root remote."
warning "Untuk keamanan, root sebaiknya digunakan hanya dari localhost."
warning "Jika root menggunakan authentication socket, pertahankan konfigurasi tersebut."

echo

# ------------------------------------------------------------
# MARIADB SOCKET / PING
# ------------------------------------------------------------

section "MARIADB CONNECTION TEST"

if systemctl is-active --quiet mariadb; then

    if mariadb-admin ping >/dev/null 2>&1; then
        success "MariaDB menerima koneksi."
    else
        error "MariaDB service running tetapi mariadb-admin ping gagal."
        exit 1
    fi

else

    error "MariaDB tidak sedang running."
    exit 1

fi

# ------------------------------------------------------------
# MARIADB LISTENING SOCKET
# ------------------------------------------------------------

info "Memeriksa MariaDB listener TCP/3306..."

if command -v ss >/dev/null 2>&1; then

    if ss -lntp | grep -q ':3306'; then
        ss -lntp | grep ':3306'
        success "MariaDB listener TCP/3306 ditemukan."
    else
        warning "Listener TCP/3306 belum ditemukan."
    fi

fi

# ------------------------------------------------------------
# CLAMAV
# ------------------------------------------------------------

section "CHECK CLAMAV"

if command -v clamscan >/dev/null 2>&1; then
    success "ClamAV sudah tersedia."
    clamscan --version | head -n 1 || true
else
    info "ClamAV belum tersedia."
    info "Menginstall ClamAV, daemon, dan FreshClam..."

    apt-get install -y \
        clamav \
        clamav-daemon \
        clamav-freshclam

    success "ClamAV berhasil diinstall."
fi

# Ensure the signature database is available, but do not start the
# scanning daemon automatically before the administrator decides.
if command -v freshclam >/dev/null 2>&1; then
    info "Memastikan database signature ClamAV tersedia..."

    systemctl stop clamav-freshclam 2>/dev/null || true

    if ! freshclam --stdout >/tmp/docker-php-freshclam.log 2>&1; then
        warning "Update signature ClamAV gagal. Lihat:"
        warning "/tmp/docker-php-freshclam.log"
    else
        success "Database signature ClamAV diperbarui."
    fi
fi

# ------------------------------------------------------------
# LINUX MALWARE DETECT (LMD)
# ------------------------------------------------------------

section "CHECK LINUX MALWARE DETECT"

if command -v maldet >/dev/null 2>&1; then
    success "Linux Malware Detect (LMD) sudah tersedia."
    maldet --version 2>/dev/null | head -n 2 || true
else
    info "Linux Malware Detect (LMD) belum tersedia."
    info "Mengunduh installer resmi LMD..."

    LMD_TMP="$(mktemp -d)"
    trap 'rm -rf "${LMD_TMP}"' EXIT

    curl -fsSL \
        "https://raw.githubusercontent.com/rfxn/linux-malware-detect/master/install.sh" \
        -o "${LMD_TMP}/install.sh"

    chmod 0755 "${LMD_TMP}/install.sh"
    "${LMD_TMP}/install.sh"

    rm -rf "${LMD_TMP}"

    if command -v maldet >/dev/null 2>&1; then
        success "Linux Malware Detect (LMD) berhasil diinstall."
    else
        error "LMD berhasil dijalankan installernya tetapi command maldet tidak ditemukan."
        exit 1
    fi
fi

# ------------------------------------------------------------
# YARA
# ------------------------------------------------------------

section "CHECK YARA"

if command -v yara >/dev/null 2>&1; then
    success "YARA sudah tersedia."
    yara --version || true
else
    info "YARA belum tersedia."
    info "Menginstall YARA dari repository Ubuntu..."

    apt-get install -y yara

    success "YARA berhasil diinstall."
fi

# ------------------------------------------------------------
# SECURITY TOOL ENABLEMENT
# ------------------------------------------------------------

section "SECURITY TOOL ENABLEMENT"

CLAMAV_ENABLED="NO"
LMD_ENABLED="NO"
YARA_ENABLED="NO"

echo
read -r -p "Aktifkan ClamAV otomatis? [y/N]: " ENABLE_CLAMAV
case "${ENABLE_CLAMAV,,}" in
    y|yes)
        CLAMAV_ENABLED="YES"
        ;;
    *)
        CLAMAV_ENABLED="NO"
        ;;
esac

echo
read -r -p "Aktifkan LMD otomatis? [y/N]: " ENABLE_LMD
case "${ENABLE_LMD,,}" in
    y|yes)
        LMD_ENABLED="YES"
        ;;
    *)
        LMD_ENABLED="NO"
        ;;
esac

echo
read -r -p "Aktifkan YARA melalui LMD? [y/N]: " ENABLE_YARA
case "${ENABLE_YARA,,}" in
    y|yes)
        YARA_ENABLED="YES"
        ;;
    *)
        YARA_ENABLED="NO"
        ;;
esac

# ClamAV:
# YES = enable FreshClam and ClamAV daemon.
# NO  = keep the packages installed but do not run the services.
if [[ "${CLAMAV_ENABLED}" == "YES" ]]; then
    info "Mengaktifkan ClamAV daemon dan FreshClam..."

    systemctl enable --now clamav-freshclam 2>/dev/null || true
    systemctl enable --now clamav-daemon 2>/dev/null || true

    success "ClamAV diaktifkan."
else
    info "ClamAV tetap terinstall tetapi tidak diaktifkan."

    systemctl disable --now clamav-daemon 2>/dev/null || true
    systemctl disable --now clamav-freshclam 2>/dev/null || true
fi

# LMD:
# LMD's upstream installer installs cron/systemd integration. To honor
# "install != enable", disable the service and daily scan when declined.
if [[ -f /usr/local/maldetect/conf.maldet ]]; then
    if [[ "${LMD_ENABLED}" == "YES" ]]; then
        sed -i -E 's/^[[:space:]]*cron_daily_scan[[:space:]]*=.*/cron_daily_scan=1/' \
            /usr/local/maldetect/conf.maldet
        sed -i -E 's/^[[:space:]]*default_monitor_mode[[:space:]]*=.*/default_monitor_mode=""/' \
            /usr/local/maldetect/conf.maldet || true

        systemctl enable --now maldet.service 2>/dev/null || true
        success "LMD diaktifkan."
        info "Real-time monitoring LMD belum diarahkan ke directory aplikasi."
    else
        sed -i -E 's/^[[:space:]]*cron_daily_scan[[:space:]]*=.*/cron_daily_scan=0/' \
            /usr/local/maldetect/conf.maldet

        systemctl disable --now maldet.service 2>/dev/null || true
        success "LMD tetap terinstall tetapi scanning otomatis dinonaktifkan."
    fi
fi

# YARA is a scanning engine, not a standalone systemd service.
# Its enablement here controls native YARA scanning from LMD.
if [[ -f /usr/local/maldetect/conf.maldet ]]; then
    if [[ "${YARA_ENABLED}" == "YES" ]]; then
        if grep -Eq '^[[:space:]]*scan_yara[[:space:]]*=' /usr/local/maldetect/conf.maldet; then
            sed -i -E 's/^[[:space:]]*scan_yara[[:space:]]*=.*/scan_yara=1/' \
                /usr/local/maldetect/conf.maldet
        else
            printf '\nscan_yara=1\n' >> /usr/local/maldetect/conf.maldet
        fi
        success "YARA native scanning melalui LMD diaktifkan."
    else
        if grep -Eq '^[[:space:]]*scan_yara[[:space:]]*=' /usr/local/maldetect/conf.maldet; then
            sed -i -E 's/^[[:space:]]*scan_yara[[:space:]]*=.*/scan_yara=0/' \
                /usr/local/maldetect/conf.maldet
        else
            printf '\nscan_yara=0\n' >> /usr/local/maldetect/conf.maldet
        fi
        success "YARA tetap terinstall tetapi native scanning melalui LMD dinonaktifkan."
    fi
fi

# ------------------------------------------------------------
# FINAL CHECK
# ------------------------------------------------------------

section "FINAL CHECK"

printf "%-20s : " "Nginx"

if command -v nginx >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

printf "%-20s : " "Docker"

if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

printf "%-20s : " "Docker Compose"

if docker compose version >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

printf "%-20s : " "MariaDB"

if command -v mariadb >/dev/null 2>&1 && systemctl is-active --quiet mariadb; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

printf "%-20s : " "MariaDB Bind"

if [[ "${MARIADB_BIND_ADDRESS:-}" == "0.0.0.0" ]]; then
    echo -e "${GREEN}0.0.0.0${NC}"
else
    echo -e "${RED}${MARIADB_BIND_ADDRESS:-UNKNOWN}${NC}"
fi

printf "%-20s : " "MariaDB Root"

if [[ -z "${REMOTE_ROOT_ACCOUNTS:-}" ]]; then
    echo -e "${GREEN}LOCALHOST ONLY${NC}"
else
    echo -e "${RED}REMOTE ACCESS${NC}"
fi

printf "%-20s : " "ClamAV"
if command -v clamscan >/dev/null 2>&1; then
    if [[ "${CLAMAV_ENABLED:-NO}" == "YES" ]]; then
        echo -e "${GREEN}INSTALLED / ENABLED${NC}"
    else
        echo -e "${YELLOW}INSTALLED / DISABLED${NC}"
    fi
else
    echo -e "${RED}FAILED${NC}"
fi

printf "%-20s : " "LMD"
if command -v maldet >/dev/null 2>&1; then
    if [[ "${LMD_ENABLED:-NO}" == "YES" ]]; then
        echo -e "${GREEN}INSTALLED / ENABLED${NC}"
    else
        echo -e "${YELLOW}INSTALLED / DISABLED${NC}"
    fi
else
    echo -e "${RED}FAILED${NC}"
fi

printf "%-20s : " "YARA"
if command -v yara >/dev/null 2>&1; then
    if [[ "${YARA_ENABLED:-NO}" == "YES" ]]; then
        echo -e "${GREEN}INSTALLED / ENABLED${NC}"
    else
        echo -e "${YELLOW}INSTALLED / DISABLED${NC}"
    fi
else
    echo -e "${RED}FAILED${NC}"
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

section "INSTALLED VERSIONS"

echo
echo "Operating System:"
echo "  ${PRETTY_NAME:-${OS_ID}}"

echo
echo "Nginx:"
nginx -v 2>&1 || true

echo
echo "Docker:"
docker --version || true

echo
echo "Docker Compose:"
docker compose version || true

echo
echo "MariaDB:"
mariadb --version || true

echo
echo "ClamAV:"
clamscan --version 2>/dev/null | head -n 1 || echo "  Tidak tersedia"

echo
echo "LMD:"
maldet --version 2>/dev/null | head -n 1 || echo "  Tidak tersedia"

echo
echo "YARA:"
yara --version 2>/dev/null || echo "  Tidak tersedia"

echo

success "Pemeriksaan dependency selesai."

echo
echo "Security tools:"
echo "  ClamAV : ${CLAMAV_ENABLED:-NO}"
echo "  LMD    : ${LMD_ENABLED:-NO}"
echo "  YARA   : ${YARA_ENABLED:-NO}"

echo
echo "MariaDB configuration:"
echo "  Bind Address : ${MARIADB_BIND_ADDRESS}"
echo "  Root Access  : localhost only"
echo "  Root Password: tidak diubah oleh script"
echo

echo "Environment siap digunakan untuk repository docker-php."

echo
echo "Repository:"
echo "  /opt/docker-php"

echo
echo "Langkah berikutnya:"
echo
echo "  cd /opt/docker-php"
echo "  ./scripts/build-image.sh"
echo