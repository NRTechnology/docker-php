#!/usr/bin/env bash
#
# create-redis.sh
# Redis Server Instance Manager for Docker-PHP
#

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"

REDIS_IMAGE="local/redis:7.4"
BASE_DIR="/opt/docker-redis"
DATA_DIR="/var/lib/docker-redis"
REDIS_NETWORK="docker-php-redis"

DEFAULT_MEMORY="512mb"
DEFAULT_MEM_LIMIT="768m"
DEFAULT_CPUS="1.0"
DEFAULT_POLICY="noeviction"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

success() {
    echo -e "${GREEN}[ OK ]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $*"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $*" >&2
}

die() {
    error "$*"
    exit 1
}

usage() {
    cat <<EOF

Redis Instance Manager - Docker-PHP

Usage:
  $SCRIPT_NAME create <name> [options]
  $SCRIPT_NAME list
  $SCRIPT_NAME status <name>
  $SCRIPT_NAME logs <name> [--follow]
  $SCRIPT_NAME start <name>
  $SCRIPT_NAME stop <name>
  $SCRIPT_NAME restart <name>
  $SCRIPT_NAME backup <name>
  $SCRIPT_NAME remove <name> [--purge]

Create options:
  --memory <size>       Redis maxmemory (default: 512mb)
  --mem-limit <size>    Container memory limit (default: 768m)
  --cpus <number>       CPU limit (default: 1.0)
  --policy <policy>     Redis eviction policy (default: noeviction)
  --port <port>         Publish to localhost only (optional)
  --password <password> Set Redis password manually
  --help                Show help

Remove options:
  --purge               Delete persistent data permanently

Examples:
  $SCRIPT_NAME create shared
  $SCRIPT_NAME create cache --memory 1gb --policy allkeys-lru
  $SCRIPT_NAME create puskesmas --memory 512mb
  $SCRIPT_NAME create test --port 16379
  $SCRIPT_NAME list
  $SCRIPT_NAME status shared
  $SCRIPT_NAME backup shared
  $SCRIPT_NAME remove test
  $SCRIPT_NAME remove test --purge

EOF
}

require_root() {
    [[ "$EUID" -eq 0 ]] || die "Jalankan script sebagai root."
}

check_dependencies() {
    command -v docker >/dev/null 2>&1 || die "Docker tidak ditemukan."
    command -v openssl >/dev/null 2>&1 || die "openssl tidak ditemukan."

    docker info >/dev/null 2>&1 || die "Docker daemon tidak berjalan."
    docker compose version >/dev/null 2>&1 || die "Docker Compose plugin tidak tersedia."
}

valid_name() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$ ]]
}

valid_size() {
    [[ "$1" =~ ^[1-9][0-9]*(k|m|g|kb|mb|gb)?$ ]]
}

valid_number() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] &&
    (( "$1" >= 1 && "$1" <= 65535 ))
}

instance_dir() {
    echo "${BASE_DIR}/$1"
}

instance_data() {
    echo "${DATA_DIR}/$1"
}

compose() {
    local name="$1"
    shift

    local dir
    dir="$(instance_dir "$name")"

    [[ -f "$dir/docker-compose.yml" ]] ||
        die "Instance Redis '$name' tidak ditemukan."

    docker compose \
        --project-name "redis-${name}" \
        --env-file "$dir/.env" \
        -f "$dir/docker-compose.yml" \
        "$@"
}

ensure_network() {
    if docker network inspect "$REDIS_NETWORK" >/dev/null 2>&1; then
        success "Network $REDIS_NETWORK tersedia."
    else
        info "Membuat Docker network $REDIS_NETWORK..."

        docker network create \
            --driver bridge \
            "$REDIS_NETWORK" >/dev/null

        success "Network berhasil dibuat."
    fi
}

generate_password() {
    openssl rand -hex 32
}

create_instance() {
    [[ $# -ge 1 ]] || {
        usage
        exit 1
    }

    local name="$1"
    shift

    valid_name "$name" ||
        die "Nama instance tidak valid."

    local memory="$DEFAULT_MEMORY"
    local mem_limit="$DEFAULT_MEM_LIMIT"
    local cpus="$DEFAULT_CPUS"
    local policy="$DEFAULT_POLICY"
    local port=""
    local password=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --memory)
                memory="$2"
                shift 2
                ;;
            --mem-limit)
                mem_limit="$2"
                shift 2
                ;;
            --cpus)
                cpus="$2"
                shift 2
                ;;
            --policy)
                policy="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Opsi tidak dikenal: $1"
                ;;
        esac
    done

    valid_size "$memory" || die "Nilai memory tidak valid."
    valid_size "$mem_limit" || die "Nilai mem-limit tidak valid."
    valid_number "$cpus" || die "Nilai CPU tidak valid."

    [[ "$policy" =~ ^(noeviction|allkeys-lru|allkeys-lfu|volatile-lru|volatile-lfu|volatile-random|allkeys-random|volatile-ttl)$ ]] ||
        die "Redis eviction policy tidak valid."

    if [[ -n "$port" ]]; then
        valid_port "$port" || die "Port tidak valid."
    fi

    local dir
    local data

    dir="$(instance_dir "$name")"
    data="$(instance_data "$name")"

    [[ ! -e "$dir" ]] ||
        die "Instance sudah ada: $dir"

    [[ ! -e "$data" ]] ||
        die "Direktori data sudah ada: $data. Tidak akan ditimpa."

    docker image inspect "$REDIS_IMAGE" >/dev/null 2>&1 ||
        die "Image $REDIS_IMAGE tidak ditemukan. Jalankan build-redis.sh terlebih dahulu."

    ensure_network

    [[ -n "$password" ]] ||
        password="$(generate_password)"

    [[ ${#password} -ge 16 ]] ||
        die "Password minimal 16 karakter."

    [[ "$password" != *$'\n'* && "$password" != *$'\r'* ]] ||
        die "Password tidak boleh mengandung newline."

    info "Membuat direktori instance..."

    mkdir -p "$dir"
    mkdir -p "$data/data"

    chmod 750 "$dir" "$data"
    chmod 700 "$data/data"

    cat > "$dir/.env" <<EOF
REDIS_PASSWORD=${password}
REDIS_IMAGE=${REDIS_IMAGE}
REDIS_MEMORY=${memory}
REDIS_POLICY=${policy}
EOF

    chmod 600 "$dir/.env"

    cat > "$dir/docker-compose.yml" <<EOF
services:

  redis:
    image: \${REDIS_IMAGE}
    container_name: redis-${name}
    hostname: redis-${name}

    restart: unless-stopped

    command:
      - redis-server
      - --appendonly
      - "yes"
      - --appendfsync
      - everysec
      - --maxmemory
      - \${REDIS_MEMORY}
      - --maxmemory-policy
      - \${REDIS_POLICY}
      - --requirepass
      - \${REDIS_PASSWORD}

    environment:
      TZ: Asia/Jakarta
      REDIS_PASSWORD: \${REDIS_PASSWORD}

    read_only: true

    tmpfs:
      - /tmp:rw,noexec,nosuid,size=64m

    security_opt:
      - no-new-privileges:true

    volumes:
      - ${data}/data:/data:rw

    cpus: "${cpus}"
    mem_limit: "${mem_limit}"
    pids_limit: 100

    ulimits:
      nofile:
        soft: 65535
        hard: 65535

    stop_grace_period: 60s

    healthcheck:
      test:
        - CMD-SHELL
        - 'redis-cli -a "\$\$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG'
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

    networks:
      - redis-shared

EOF

    if [[ -n "$port" ]]; then
        cat >> "$dir/docker-compose.yml" <<EOF
    ports:
      - "127.0.0.1:${port}:6379"

EOF
    fi

    cat >> "$dir/docker-compose.yml" <<EOF
networks:

  redis-shared:
    external: true
    name: ${REDIS_NETWORK}
EOF

    info "Validasi Docker Compose..."

    docker compose \
        --project-name "redis-${name}" \
        --env-file "$dir/.env" \
        -f "$dir/docker-compose.yml" \
        config >/dev/null ||
        die "Validasi Docker Compose gagal."

    info "Menjalankan Redis instance..."

    docker compose \
        --project-name "redis-${name}" \
        --env-file "$dir/.env" \
        -f "$dir/docker-compose.yml" \
        up -d || die "Gagal menjalankan Redis."

    success "Redis instance '$name' berhasil dibuat."

    echo
    echo "============================================"
    echo " REDIS INSTANCE INFORMATION"
    echo "============================================"
    echo "Instance       : $name"
    echo "Container      : redis-$name"
    echo "Image          : $REDIS_IMAGE"
    echo "Network        : $REDIS_NETWORK"
    echo "Endpoint       : redis-$name:6379"
    echo "Max memory     : $memory"
    echo "Memory limit   : $mem_limit"
    echo "CPU limit      : $cpus"
    echo "Policy         : $policy"
    echo "Data directory : $data/data"
    echo "Compose file   : $dir/docker-compose.yml"

    if [[ -n "$port" ]]; then
        echo "Host endpoint  : 127.0.0.1:$port"
    else
        echo "Host port      : Not published"
    fi

    echo "============================================"
    echo
    warn "Simpan password berikut di password manager."
    echo "Redis password : $password"
    echo
}

list_instances() {
    printf "%-20s %-22s %-15s %s\n" \
        "INSTANCE" "CONTAINER" "STATUS" "DATA"

    printf "%-20s %-22s %-15s %s\n" \
        "--------" "---------" "------" "----"

    [[ -d "$BASE_DIR" ]] || return 0

    local file
    local name
    local state

    shopt -s nullglob

    for file in "$BASE_DIR"/*/docker-compose.yml; do
        name="$(basename "$(dirname "$file")")"

        state="$(docker inspect \
            -f '{{.State.Status}}' \
            "redis-$name" 2>/dev/null || echo "not-created")"

        printf "%-20s %-22s %-15s %s\n" \
            "$name" \
            "redis-$name" \
            "$state" \
            "$(instance_data "$name")/data"
    done

    shopt -u nullglob
}

status_instance() {
    local name="$1"

    compose "$name" ps

    echo

    docker exec "redis-$name" \
        sh -c 'redis-cli -a "$REDIS_PASSWORD" ping' 2>/dev/null ||
        warn "Redis belum merespons PING."
}

logs_instance() {
    local name="$1"
    shift

    if [[ "${1:-}" == "--follow" ]]; then
        compose "$name" logs --tail 100 -f
    else
        compose "$name" logs --tail 100
    fi
}

backup_instance() {
    local name="$1"

    local data
    data="$(instance_data "$name")"

    [[ -d "$data/data" ]] ||
        die "Data Redis tidak ditemukan."

    local backup_dir="/var/backups/docker-redis"
    local archive

    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"

    archive="${backup_dir}/redis-${name}-$(date +%Y%m%d-%H%M%S).tar.gz"

    info "Menghentikan Redis sementara untuk backup..."

    compose "$name" stop

    if tar -czf "$archive" -C "$data" data; then
        chmod 600 "$archive"
        success "Backup berhasil: $archive"
    else
        compose "$name" start || true
        die "Backup gagal."
    fi

    compose "$name" start

    success "Redis instance '$name' dijalankan kembali."
}

remove_instance() {
    local name="$1"
    shift

    local purge=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --purge)
                purge=true
                shift
                ;;
            *)
                die "Opsi remove tidak dikenal: $1"
                ;;
        esac
    done

    local dir
    local data

    dir="$(instance_dir "$name")"
    data="$(instance_data "$name")"

    [[ -f "$dir/docker-compose.yml" ]] ||
        die "Instance '$name' tidak ditemukan."

    if [[ "$purge" == true ]]; then
        warn "Data Redis akan dihapus permanen!"
        read -r -p "Ketik '$name' untuk konfirmasi: " confirm

        [[ "$confirm" == "$name" ]] ||
            die "Konfirmasi tidak sesuai."
    else
        warn "Data Redis akan tetap dipertahankan."
        read -r -p "Lanjutkan penghapusan container? [y/N] " confirm

        [[ "$confirm" =~ ^[Yy]$ ]] ||
            die "Penghapusan dibatalkan."
    fi

    compose "$name" down

    rm -rf -- "$dir"

    if [[ "$purge" == true ]]; then
        rm -rf -- "$data"
        success "Instance, konfigurasi, dan data '$name' dihapus."
    else
        success "Container dan konfigurasi '$name' dihapus."
        info "Data tetap tersimpan di: $data/data"
    fi
}

main() {
    require_root
    check_dependencies

    local action="${1:-}"

    [[ -n "$action" ]] || {
        usage
        exit 1
    }

    shift || true

    case "$action" in

        create)
            create_instance "$@"
            ;;

        list|ls)
            list_instances
            ;;

        status)
            [[ $# -eq 1 ]] || die "Gunakan: $SCRIPT_NAME status <name>"
            valid_name "$1" || die "Nama instance tidak valid."
            status_instance "$1"
            ;;

        logs)
            [[ $# -ge 1 ]] || die "Gunakan: $SCRIPT_NAME logs <name> [--follow]"
            valid_name "$1" || die "Nama instance tidak valid."
            logs_instance "$@"
            ;;

        start|stop|restart)
            [[ $# -eq 1 ]] || die "Gunakan: $SCRIPT_NAME $action <name>"
            valid_name "$1" || die "Nama instance tidak valid."

            compose "$1" "$action"
            success "Perintah $action selesai."
            ;;

        backup)
            [[ $# -eq 1 ]] || die "Gunakan: $SCRIPT_NAME backup <name>"
            valid_name "$1" || die "Nama instance tidak valid."
            backup_instance "$1"
            ;;

        remove|delete)
            [[ $# -ge 1 ]] || die "Gunakan: $SCRIPT_NAME remove <name> [--purge]"
            valid_name "$1" || die "Nama instance tidak valid."

            local name="$1"
            shift

            remove_instance "$name" "$@"
            ;;

        help|-h|--help)
            usage
            ;;

        *)
            usage
            die "Perintah tidak dikenal: $action"
            ;;
    esac
}

main "$@"