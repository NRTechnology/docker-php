#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# build-image.sh
#
# Standard PHP-FPM Docker Image Builder
#
# Supported PHP versions:
#   7.4
#   8.3
#   8.4
#   8.5
#
# Usage:
#   ./build-image.sh
#   ./build-image.sh all
#   ./build-image.sh 8.3
#   ./build-image.sh 8.3 8.4
#   ./build-image.sh 8.3 --no-cache
#   ./build-image.sh all --no-cache
#
# ==============================================================================

set +e
trap - ERR
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSIONS=(
    "7.4"
    "8.3"
    "8.4"
    "8.5"
)

NO_CACHE=false


# ==============================================================================
# COLORS
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


# ==============================================================================
# FUNCTIONS
# ==============================================================================

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
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

section() {
    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

die() {
    error "$*"
    exit 1
}


# ==============================================================================
# USAGE
# ==============================================================================

usage() {
    cat <<EOF

Usage:
  $0
  $0 all
  $0 <php-version>
  $0 <php-version> [php-version ...]
  $0 [all|php-version] --no-cache

Supported PHP versions:
  7.4
  8.3
  8.4
  8.5

Examples:

  Build melalui menu:
    $0

  Build semua image:
    $0 all

  Build PHP 8.3:
    $0 8.3

  Build PHP 8.3 dan 8.4:
    $0 8.3 8.4

  Build PHP 8.3 tanpa cache:
    $0 8.3 --no-cache

  Build semua image tanpa cache:
    $0 all --no-cache

EOF
}


# ==============================================================================
# CHECK PHP VERSION
# ==============================================================================

is_supported_version() {

    local version="$1"

    case "$version" in
        7.4|8.3|8.4|8.5)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


# ==============================================================================
# CHECK REQUIREMENTS
# ==============================================================================

check_requirements() {

    section "CHECK REQUIREMENTS"

    command -v docker >/dev/null 2>&1 \
        || die "Docker tidak ditemukan."

    success "Docker tersedia."

    if ! docker info >/dev/null 2>&1; then
        die "Docker daemon tidak dapat diakses."
    fi

    success "Docker daemon berjalan."

    if ! docker buildx version >/dev/null 2>&1; then
        die "Docker Buildx tidak tersedia."
    fi

    success "Docker Buildx tersedia."

    info "Repository root:"
    echo "  ${ROOT_DIR}"

}


# ==============================================================================
# CHECK DOCKERFILE
# ==============================================================================

check_dockerfile() {

    local version="$1"

    local image_dir="${ROOT_DIR}/images/${version}"
    local dockerfile="${image_dir}/Dockerfile"

    if [[ ! -d "$image_dir" ]]; then
        die "Directory image tidak ditemukan: ${image_dir}"
    fi

    if [[ ! -f "$dockerfile" ]]; then
        die "Dockerfile tidak ditemukan: ${dockerfile}"
    fi

    if [[ ! -f "${image_dir}/php.ini" ]]; then
        warning "php.ini tidak ditemukan: ${image_dir}/php.ini"
    fi

}


# ==============================================================================
# BUILD IMAGE
# ==============================================================================

build_image() {

    local version="$1"

    local image_name="local/php:${version}"
    local image_dir="${ROOT_DIR}/images/${version}"

    check_dockerfile "$version"

    section "BUILD PHP ${version}"

    info "Image      : ${image_name}"
    info "Build path : ${image_dir}"

    if [[ "$NO_CACHE" == true ]]; then
        info "Build mode : --no-cache"
    else
        info "Build mode : cache enabled"
    fi

    echo

    BUILD_ARGS=(
        build
        -t "$image_name"
    )

    if [[ "$NO_CACHE" == true ]]; then
        BUILD_ARGS+=("--no-cache")
    fi

    BUILD_ARGS+=("$image_dir")

    if docker "${BUILD_ARGS[@]}"; then
        success "Image ${image_name} berhasil dibuild."
    else
        error "Build image ${image_name} gagal."
        return 1
    fi

}


# ==============================================================================
# VERIFY IMAGE
# ==============================================================================

verify_image() {

    local version="$1"
    local image_name="local/php:${version}"

    section "VERIFY ${image_name}"

    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        error "Image tidak ditemukan setelah build: ${image_name}"
        return 1
    fi

    success "Image tersedia."

    echo
    info "Image information:"

    docker image inspect "$image_name" \
        --format '  ID          : {{.Id}}
  Created     : {{.Created}}
  Architecture: {{.Architecture}}
  OS          : {{.Os}}'

    echo
    info "PHP version:"

    docker run --rm \
        "$image_name" \
        php -v | head -n 1

    echo
    info "PHP-FPM configuration test:"

    docker run --rm \
        "$image_name" \
        php-fpm -t

    success "Image ${image_name} berhasil diverifikasi."

}


# ==============================================================================
# SHOW IMAGES
# ==============================================================================

show_images() {

    section "LOCAL PHP IMAGES"

    docker images local/php \
        --format 'table {{.Repository}}\t{{.Tag}}\t{{.ImageID}}\t{{.CreatedSince}}\t{{.Size}}'

}


# ==============================================================================
# INTERACTIVE MENU
# ==============================================================================

interactive_menu() {

    while true; do

        section "PHP-FPM IMAGE BUILDER"

        echo "Repository:"
        echo "  ${ROOT_DIR}"

        echo
        echo "Pilih image yang ingin dibuild:"
        echo
        echo "  1) PHP 7.4"
        echo "  2) PHP 8.3"
        echo "  3) PHP 8.4"
        echo "  4) PHP 8.5"
        echo "  5) Semua versi"
        echo "  6) Tampilkan image yang tersedia"
        echo "  0) Keluar"

        echo
        read -r -p "Pilihan [0-6]: " choice

        case "$choice" in

            1)
                SELECTED_VERSIONS=("7.4")
                break
                ;;

            2)
                SELECTED_VERSIONS=("8.3")
                break
                ;;

            3)
                SELECTED_VERSIONS=("8.4")
                break
                ;;

            4)
                SELECTED_VERSIONS=("8.5")
                break
                ;;

            5)
                SELECTED_VERSIONS=("${VERSIONS[@]}")
                break
                ;;

            6)
                show_images
                echo
                read -r -p "Tekan ENTER untuk kembali ke menu..."
                ;;

            0)
                echo
                info "Dibatalkan."
                exit 0
                ;;

            *)
                warning "Pilihan tidak valid."
                ;;

        esac

    done

}


# ==============================================================================
# PARSE ARGUMENTS
# ==============================================================================

SELECTED_VERSIONS=()

if [[ $# -eq 0 ]]; then

    interactive_menu

else

    for arg in "$@"; do

        case "$arg" in

            --no-cache)
                NO_CACHE=true
                ;;

            -h|--help)
                usage
                exit 0
                ;;

            all)
                SELECTED_VERSIONS=("${VERSIONS[@]}")
                ;;

            7.4|8.3|8.4|8.5)
                SELECTED_VERSIONS+=("$arg")
                ;;

            *)
                error "Argument tidak dikenal: $arg"
                usage
                exit 1
                ;;

        esac

    done

fi


# ==============================================================================
# REMOVE DUPLICATES
# ==============================================================================

if [[ ${#SELECTED_VERSIONS[@]} -gt 0 ]]; then

    mapfile -t SELECTED_VERSIONS < <(
        printf '%s\n' "${SELECTED_VERSIONS[@]}" | awk '!seen[$0]++'
    )

else

    die "Tidak ada PHP version yang dipilih."

fi


# ==============================================================================
# PHP 7.4 WARNING
# ==============================================================================

for version in "${SELECTED_VERSIONS[@]}"; do

    if [[ "$version" == "7.4" ]]; then
        warning "PHP 7.4 adalah versi legacy/EOL."
    fi

done


# ==============================================================================
# CONFIRMATION
# ==============================================================================

section "BUILD PLAN"

echo "Selected PHP versions:"
echo

for version in "${SELECTED_VERSIONS[@]}"; do
    echo "  - PHP ${version}"
done

echo

if [[ "$NO_CACHE" == true ]]; then
    echo "Build cache: DISABLED"
else
    echo "Build cache: ENABLED"
fi

echo


# ==============================================================================
# CHECK REQUIREMENTS
# ==============================================================================

check_requirements


# ==============================================================================
# BUILD
# ==============================================================================

FAILED_VERSIONS=()
SUCCESS_VERSIONS=()

for version in "${SELECTED_VERSIONS[@]}"; do

    if build_image "$version"; then

        if verify_image "$version"; then
            SUCCESS_VERSIONS+=("$version")
        else
            FAILED_VERSIONS+=("$version")
        fi

    else

        FAILED_VERSIONS+=("$version")

    fi

done


# ==============================================================================
# FINAL RESULT
# ==============================================================================

section "BUILD SUMMARY"

echo

if [[ ${#SUCCESS_VERSIONS[@]} -gt 0 ]]; then

    success "Build berhasil:"

    for version in "${SUCCESS_VERSIONS[@]}"; do
        echo "  - local/php:${version}"
    done

fi

if [[ ${#FAILED_VERSIONS[@]} -gt 0 ]]; then

    echo
    error "Build gagal:"

    for version in "${FAILED_VERSIONS[@]}"; do
        echo "  - local/php:${version}"
    done

fi

echo

show_images

echo

if [[ ${#FAILED_VERSIONS[@]} -gt 0 ]]; then
    error "Sebagian image gagal dibuild."
    exit 1
fi

success "Semua image yang dipilih berhasil dibuild dan diverifikasi."