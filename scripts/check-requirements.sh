#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# docker-php
# System Requirements Checker & Installer
#
# Checks and installs:
#   - Nginx
#   - Docker Engine
#   - Docker Compose Plugin
#   - MariaDB Server
#
# Supported:
#   - Ubuntu
#   - Debian
#
# Run as root:
#   sudo ./scripts/check-requirements.sh
# ============================================================

SCRIPT_NAME="$(basename "$0")"

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
# APT Update
# ------------------------------------------------------------

section "APT PACKAGE INFORMATION"

info "Updating APT package index..."

apt-get update

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
        https://download.docker.com/linux/${OS_ID}/gpg \
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

if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then

    if command -v mariadb >/dev/null 2>&1; then
        MARIADB_VERSION="$(mariadb --version)"
    else
        MARIADB_VERSION="$(mysql --version)"
    fi

    success "MariaDB client/server command tersedia."
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

fi

# ------------------------------------------------------------
# MARIADB VERSION
# ------------------------------------------------------------

if command -v mariadb >/dev/null 2>&1; then

    info "MariaDB version:"
    mariadb --version

fi

# ------------------------------------------------------------
# MARIADB SOCKET
# ------------------------------------------------------------

if systemctl is-active --quiet mariadb; then

    if mariadb-admin ping >/dev/null 2>&1; then
        success "MariaDB menerima koneksi."
    else
        warning "MariaDB service running tetapi mariadb-admin ping gagal."
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
mariadb --version 2>/dev/null || mysql --version 2>/dev/null || true

echo

success "Pemeriksaan dependency selesai."

echo
echo "Environment siap digunakan untuk repository docker-php."
echo
echo "Repository:"
echo "  /opt/docker-php"
echo
echo "Langkah berikutnya:"
echo
echo "  cd /opt/docker-php"
echo "  ./scripts/build-all.sh"
echo