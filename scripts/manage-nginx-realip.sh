#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# manage-nginx-realip.sh
# Manage Nginx Trusted Reverse Proxy / Real IP configuration
# ==============================================================================

SCRIPT_NAME="manage-nginx-realip.sh"
SCRIPT_VERSION="1.0.0"

NGINX_CONF_DIR="/etc/nginx/conf.d"
REALIP_CONFIG="${NGINX_CONF_DIR}/realip-trusted-proxies.conf"
BACKUP_DIR="/var/backups/nginx-realip"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"

# ==============================================================================
# COLORS
# ==============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi


# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    error "$*"
    exit 1
}


# ==============================================================================
# USAGE
# ==============================================================================

usage() {
    cat <<USAGE

${SCRIPT_NAME} v${SCRIPT_VERSION}
Manage Nginx Trusted Reverse Proxy / Real IP configuration

Usage:

  ${SCRIPT_NAME} init
  ${SCRIPT_NAME} add <IP-or-CIDR>
  ${SCRIPT_NAME} remove <IP-or-CIDR>
  ${SCRIPT_NAME} list
  ${SCRIPT_NAME} show
  ${SCRIPT_NAME} status
  ${SCRIPT_NAME} --version
  ${SCRIPT_NAME} --help


Commands:

  init
      Membuat file konfigurasi jika belum ada.

  add <IP-or-CIDR>
      Menambahkan trusted reverse proxy.

      Contoh:
        ${SCRIPT_NAME} add 15.0.1.10
        ${SCRIPT_NAME} add 15.0.1.20
        ${SCRIPT_NAME} add 10.10.10.0/24
        ${SCRIPT_NAME} add 2001:db8::1
        ${SCRIPT_NAME} add 2001:db8:1234::/48

  remove <IP-or-CIDR>
      Menghapus trusted reverse proxy.

  list
      Menampilkan daftar trusted reverse proxy.

  show
      Menampilkan isi konfigurasi lengkap.

  status
      Menampilkan status konfigurasi dan validasi nginx.


Configuration:

  ${REALIP_CONFIG}

Backup:

  ${BACKUP_DIR}


Nginx Real IP:

  real_ip_header X-Forwarded-For;
  real_ip_recursive on;

USAGE
}


# ==============================================================================
# ROOT CHECK
# ==============================================================================

require_root() {
    [[ "$EUID" -eq 0 ]] \
        || die "Script harus dijalankan sebagai root."
}


# ==============================================================================
# REQUIREMENTS
# ==============================================================================

check_requirements() {

    command -v nginx >/dev/null 2>&1 \
        || die "Nginx tidak ditemukan."

    command -v ip >/dev/null 2>&1 \
        || die "Command 'ip' tidak ditemukan."

    mkdir -p "$NGINX_CONF_DIR"
}


# ==============================================================================
# INITIAL CONFIGURATION CONTENT
# ==============================================================================

create_initial_config() {

    cat > "$REALIP_CONFIG" <<'EOF'
# ==============================================================================
# TRUSTED REVERSE PROXIES
# Managed by manage-nginx-realip.sh
#
# DO NOT add arbitrary client IPs here.
# Only add IP/CIDR addresses belonging to trusted reverse proxies.
# ==============================================================================

# Example:
# set_real_ip_from 15.0.1.10;
# set_real_ip_from 15.0.1.0/24;

real_ip_header X-Forwarded-For;
real_ip_recursive on;
EOF

    chown root:root "$REALIP_CONFIG"
    chmod 0644 "$REALIP_CONFIG"
}


# ==============================================================================
# INITIAL FILE CHECK
# ==============================================================================

check_config_file() {

    echo
    echo "============================================================"
    echo "Real IP Configuration Check"
    echo "============================================================"
    echo
    echo "File:"
    echo "  ${REALIP_CONFIG}"
    echo

    if [[ -f "$REALIP_CONFIG" ]]; then
        log "File konfigurasi sudah ada."

        echo
        echo "Permission:"
        stat -c '  %U:%G %a' "$REALIP_CONFIG"

        echo
        echo "Status:"
        echo "  EXISTING"

        return 0
    fi

    warn "File konfigurasi belum ada."
    echo "  Status: NOT FOUND"

    return 1
}


# ==============================================================================
# INIT
# ==============================================================================

init_config() {

    if [[ -e "$REALIP_CONFIG" || -L "$REALIP_CONFIG" ]]; then

        if [[ -f "$REALIP_CONFIG" ]]; then
            warn "File sudah ada:"
            echo "  ${REALIP_CONFIG}"
            echo
            echo "Script tidak akan menimpa konfigurasi yang sudah ada."
            return 0
        fi

        die "Path sudah ada tetapi bukan regular file: ${REALIP_CONFIG}"
    fi

    log "Membuat konfigurasi Real IP..."

    create_initial_config

    log "File berhasil dibuat:"
    echo "  ${REALIP_CONFIG}"

    echo
    log "Validasi Nginx..."

    if nginx -t; then
        log "Konfigurasi Nginx valid."
    else
        rm -f -- "$REALIP_CONFIG"
        die "nginx -t gagal. File baru telah dihapus."
    fi
}


# ==============================================================================
# IP VALIDATION
# ==============================================================================

is_valid_ipv4() {

    local ip="$1"
    local octet

    IFS='.' read -r -a octets <<< "$ip"

    [[ "${#octets[@]}" -eq 4 ]] || return 1

    for octet in "${octets[@]}"; do

        [[ "$octet" =~ ^[0-9]+$ ]] || return 1

        (( octet >= 0 && octet <= 255 )) || return 1

        # Hindari angka seperti 001 yang dapat membingungkan.
        [[ "$octet" == "0" || "$octet" != 0* ]] || return 1
    done

    return 0
}


is_valid_ipv6() {

    local ip="$1"

    # Linux ip command menjadi validator utama.
    ip -6 route get "$ip" >/dev/null 2>&1
}


is_valid_ip_or_cidr() {

    local value="$1"
    local address
    local prefix

    [[ -n "$value" ]] || return 1

    # --------------------------------------------------------------------------
    # IPv4 / IPv4 CIDR
    # --------------------------------------------------------------------------

    if [[ "$value" == */* ]]; then

        address="${value%%/*}"
        prefix="${value##*/}"

        if is_valid_ipv4 "$address"; then

            [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
            (( prefix >= 0 && prefix <= 32 )) || return 1

            # Jangan percaya seluruh IPv4 Internet.
            [[ "$value" != "0.0.0.0/0" ]] || return 1

            return 0
        fi

        # IPv6 CIDR.
        if [[ "$address" == *:* ]]; then

            [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
            (( prefix >= 0 && prefix <= 128 )) || return 1

            [[ "$value" != "::/0" ]] || return 1

            # iproute2 validation.
            ip -6 route get "$address" >/dev/null 2>&1 \
                || true

            return 0
        fi

        return 1
    fi

    # --------------------------------------------------------------------------
    # Plain IPv4
    # --------------------------------------------------------------------------

    if is_valid_ipv4 "$value"; then
        return 0
    fi

    # --------------------------------------------------------------------------
    # Plain IPv6
    # --------------------------------------------------------------------------

    if [[ "$value" == *:* ]]; then

        # Basic IPv6 syntax validation.
        [[ "$value" =~ ^[0-9A-Fa-f:]+$ ]] \
            || return 1

        [[ "$value" != "::" ]] || return 1

        return 0
    fi

    return 1
}


# ==============================================================================
# SECURITY VALIDATION
# ==============================================================================

validate_proxy() {

    local proxy="$1"

    is_valid_ip_or_cidr "$proxy" \
        || die "IP/CIDR tidak valid: ${proxy}"

    case "$proxy" in
        0.0.0.0/0|::/0)
            die "Tidak diizinkan menggunakan ${proxy} sebagai trusted proxy."
            ;;
    esac
}


# ==============================================================================
# BACKUP
# ==============================================================================

backup_config() {

    local backup_file

    mkdir -p "$BACKUP_DIR"

    backup_file="${BACKUP_DIR}/realip-trusted-proxies-${TIMESTAMP}.conf"

    cp -a -- "$REALIP_CONFIG" "$backup_file"

    chown root:root "$backup_file"
    chmod 0600 "$backup_file"

    echo "$backup_file"
}


# ==============================================================================
# RESTORE
# ==============================================================================

restore_backup() {

    local backup_file="$1"

    [[ -f "$backup_file" ]] \
        || die "Backup tidak ditemukan: ${backup_file}"

    cp -a -- "$backup_file" "$REALIP_CONFIG"

    chown root:root "$REALIP_CONFIG"
    chmod 0644 "$REALIP_CONFIG"

    log "Konfigurasi dikembalikan dari backup:"
    echo "  ${backup_file}"
}


# ==============================================================================
# NGINX VALIDATION
# ==============================================================================

validate_nginx() {

    nginx -t >/dev/null 2>&1
}


# ==============================================================================
# NGINX RELOAD
# ==============================================================================

reload_nginx() {

    log "Reload Nginx..."

    systemctl reload nginx \
        || die "Gagal reload Nginx."

    log "Nginx berhasil di-reload."
}


# ==============================================================================
# CHECK REAL IP DIRECTIVES
# ==============================================================================

check_realip_directives() {

    grep -Eq '^[[:space:]]*real_ip_header[[:space:]]+X-Forwarded-For;' \
        "$REALIP_CONFIG" \
        || return 1

    grep -Eq '^[[:space:]]*real_ip_recursive[[:space:]]+on;' \
        "$REALIP_CONFIG" \
        || return 1

    return 0
}


# ==============================================================================
# ADD TRUSTED PROXY
# ==============================================================================

add_proxy() {

    local proxy="$1"
    local backup_file
    local temp_file

    validate_proxy "$proxy"

    # File harus sudah ada.
    if [[ ! -f "$REALIP_CONFIG" ]]; then
        warn "File konfigurasi belum ada:"
        echo "  ${REALIP_CONFIG}"
        echo
        echo "Jalankan:"
        echo "  ${SCRIPT_NAME} init"
        exit 1
    fi

    # Cek apakah sudah ada.
    if grep -Eq \
        "^[[:space:]]*set_real_ip_from[[:space:]]+${proxy//./\\.};[[:space:]]*$" \
        "$REALIP_CONFIG"; then

        warn "Trusted proxy sudah terdaftar:"
        echo "  ${proxy}"

        return 0
    fi

    backup_file="$(backup_config)"

    temp_file="$(mktemp)"

    trap 'rm -f -- "$temp_file"' RETURN

    awk -v proxy="$proxy" '
        BEGIN {
            added = 0
        }

        /^real_ip_header[[:space:]]+X-Forwarded-For;/ && added == 0 {
            print "set_real_ip_from " proxy ";"
            print ""
            added = 1
        }

        {
            print
        }

        END {
            if (added == 0) {
                print ""
                print "set_real_ip_from " proxy ";"
            }
        }
    ' "$REALIP_CONFIG" > "$temp_file"

    cp -a -- "$temp_file" "$REALIP_CONFIG"

    chown root:root "$REALIP_CONFIG"
    chmod 0644 "$REALIP_CONFIG"

    log "Trusted proxy ditambahkan:"
    echo "  ${proxy}"

    log "Backup:"
    echo "  ${backup_file}"

    log "Testing Nginx..."

    if validate_nginx; then

        log "nginx -t: PASS"

        reload_nginx

    else

        error "nginx -t: FAILED"

        warn "Mengembalikan konfigurasi dari backup..."

        restore_backup "$backup_file"

        validate_nginx \
            || die "Konfigurasi backup juga gagal nginx -t."

        die "Perubahan dibatalkan."
    fi
}


# ==============================================================================
# REMOVE TRUSTED PROXY
# ==============================================================================

remove_proxy() {

    local proxy="$1"
    local backup_file
    local temp_file

    validate_proxy "$proxy"

    [[ -f "$REALIP_CONFIG" ]] \
        || die "File konfigurasi belum ada: ${REALIP_CONFIG}"

    if ! grep -Eq \
        "^[[:space:]]*set_real_ip_from[[:space:]]+${proxy//./\\.};[[:space:]]*$" \
        "$REALIP_CONFIG"; then

        warn "Trusted proxy tidak ditemukan:"
        echo "  ${proxy}"

        return 0
    fi

    backup_file="$(backup_config)"

    temp_file="$(mktemp)"

    trap 'rm -f -- "$temp_file"' RETURN

    grep -Ev \
        "^[[:space:]]*set_real_ip_from[[:space:]]+${proxy//./\\.};[[:space:]]*$" \
        "$REALIP_CONFIG" > "$temp_file"

    cp -a -- "$temp_file" "$REALIP_CONFIG"

    chown root:root "$REALIP_CONFIG"
    chmod 0644 "$REALIP_CONFIG"

    log "Trusted proxy dihapus:"
    echo "  ${proxy}"

    log "Backup:"
    echo "  ${backup_file}"

    log "Testing Nginx..."

    if validate_nginx; then

        log "nginx -t: PASS"

        reload_nginx

    else

        error "nginx -t: FAILED"

        warn "Mengembalikan konfigurasi dari backup..."

        restore_backup "$backup_file"

        validate_nginx \
            || die "Konfigurasi backup juga gagal nginx -t."

        die "Perubahan dibatalkan."
    fi
}


# ==============================================================================
# LIST
# ==============================================================================

list_proxies() {

    [[ -f "$REALIP_CONFIG" ]] \
        || die "File konfigurasi belum ada: ${REALIP_CONFIG}"

    echo
    echo "============================================================"
    echo "Trusted Reverse Proxies"
    echo "============================================================"
    echo

    local found=0

    while IFS= read -r line; do

        [[ -n "$line" ]] || continue

        echo "  ${line}"

        found=1

    done < <(
        sed -n \
            -E \
            's/^[[:space:]]*set_real_ip_from[[:space:]]+([^;]+);.*$/\1/p' \
            "$REALIP_CONFIG"
    )

    if [[ "$found" -eq 0 ]]; then
        echo "  (belum ada trusted proxy)"
    fi

    echo
}


# ==============================================================================
# SHOW
# ==============================================================================

show_config() {

    [[ -f "$REALIP_CONFIG" ]] \
        || die "File konfigurasi belum ada: ${REALIP_CONFIG}"

    echo
    echo "============================================================"
    echo "Configuration"
    echo "============================================================"
    echo
    echo "File:"
    echo "  ${REALIP_CONFIG}"
    echo

    cat "$REALIP_CONFIG"

    echo
}


# ==============================================================================
# STATUS
# ==============================================================================

status_config() {

    echo
    echo "============================================================"
    echo "Nginx Real IP Status"
    echo "============================================================"
    echo

    echo "Configuration:"
    echo "  ${REALIP_CONFIG}"
    echo

    if [[ -f "$REALIP_CONFIG" ]]; then
        echo "  File       : PRESENT"
    else
        echo "  File       : NOT FOUND"
        return 1
    fi

    if check_realip_directives; then
        echo "  Header     : X-Forwarded-For"
        echo "  Recursive  : on"
    else
        warn "Directive Real IP tidak lengkap."
    fi

    echo

    if validate_nginx; then
        log "nginx -t: PASS"
    else
        error "nginx -t: FAILED"
        return 1
    fi

    echo

    list_proxies
}


# ==============================================================================
# MAIN
# ==============================================================================

require_root
check_requirements

echo
echo "============================================================"
echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
echo "============================================================"

# ------------------------------------------------------------------------------
# INITIAL FILE CHECK
# ------------------------------------------------------------------------------

if check_config_file; then
    CONFIG_EXISTS=1
else
    CONFIG_EXISTS=0
fi

echo


# ==============================================================================
# ARGUMENTS
# ==============================================================================

COMMAND="${1:-}"

case "$COMMAND" in

    init)

        init_config
        ;;

    add)

        [[ $# -eq 2 ]] \
            || die "Usage: ${SCRIPT_NAME} add <IP-or-CIDR>"

        add_proxy "$2"
        ;;

    remove)

        [[ $# -eq 2 ]] \
            || die "Usage: ${SCRIPT_NAME} remove <IP-or-CIDR>"

        remove_proxy "$2"
        ;;

    list)

        list_proxies
        ;;

    show)

        show_config
        ;;

    status)

        status_config
        ;;

    --version|-V)

        echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
        ;;

    --help|-h|"")
        usage
        ;;

    *)

        die "Command tidak dikenal: ${COMMAND}. Gunakan --help."
        ;;

esac

exit 0