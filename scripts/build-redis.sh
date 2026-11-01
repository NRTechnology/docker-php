#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================================== 
# build-redis.sh
# Redis Docker Image Builder for Docker-PHP
# ============================================================================== 
# Build context : images/redis
# Dockerfile    : images/redis/Dockerfile
# Image         : local/redis:7.4
#
# Usage:
#   ./scripts/build-redis.sh
#   ./scripts/build-redis.sh --no-cache
#   ./scripts/build-redis.sh --help
# ============================================================================== 

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_DIR="${ROOT_DIR}/images/redis"
DOCKERFILE="${IMAGE_DIR}/Dockerfile"
IMAGE_NAME="local/redis:7.4"
NO_CACHE=false
FORCE_BUILD=false

# ------------------------------------------------------------------------------
# COLORS
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------
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

usage() {
    cat <<USAGE

Usage:
  $0 [--force] [--no-cache]
  $0 --help

Build Redis image:
  Image       : ${IMAGE_NAME}
  Dockerfile  : images/redis/Dockerfile
  Build context: images/redis

Options:
  --force     Rebuild image even if it already exists
  --no-cache  Rebuild without Docker cache (implies --force)
  -h, --help  Show this help

Examples:
  $0
  $0 --no-cache

USAGE
}

check_requirements() {
    section "CHECK REQUIREMENTS"

    command -v docker >/dev/null 2>&1 \
        || die "Docker tidak ditemukan."
    success "Docker tersedia."

    docker info >/dev/null 2>&1 \
        || die "Docker daemon tidak dapat diakses."
    success "Docker daemon berjalan."

    docker buildx version >/dev/null 2>&1 \
        || die "Docker Buildx tidak tersedia."
    success "Docker Buildx tersedia."

    [[ -f "${DOCKERFILE}" ]] \
        || die "Dockerfile tidak ditemukan: ${DOCKERFILE}"

    success "Dockerfile ditemukan: ${DOCKERFILE}"
    info "Repository root: ${ROOT_DIR}"
}

image_exists() {
    docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1
}

build_image() {
    section "BUILD REDIS IMAGE"

    info "Image       : ${IMAGE_NAME}"
    info "Dockerfile  : ${DOCKERFILE}"
    info "Build path  : ${IMAGE_DIR}"

    if image_exists && [[ "${FORCE_BUILD}" != true && "${NO_CACHE}" != true ]]; then
        success "Image ${IMAGE_NAME} sudah tersedia. Build dilewati."
        info "Gunakan --force untuk membangun ulang image."
        return 0
    fi

    local -a build_args=(build -f "${DOCKERFILE}" -t "${IMAGE_NAME}")

    if [[ "${NO_CACHE}" == true ]]; then
        build_args+=(--no-cache)
        info "Build mode  : no-cache"
    else
        info "Build mode  : cache enabled"
    fi

    build_args+=("${IMAGE_DIR}")

    if docker "${build_args[@]}"; then
        success "Image ${IMAGE_NAME} berhasil dibuild."
    else
        error "Build image ${IMAGE_NAME} gagal."
        return 1
    fi
}

verify_image() {
    section "VERIFY ${IMAGE_NAME}"

    docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1 \
        || die "Image tidak ditemukan setelah build: ${IMAGE_NAME}"
    success "Image tersedia."

    info "Image information:"
    docker image inspect "${IMAGE_NAME}" \
        --format '  ID           : {{.Id}}\n  Created      : {{.Created}}\n  Architecture : {{.Architecture}}\n  OS           : {{.Os}}'

    echo
    info "Redis version:"
    docker run --rm "${IMAGE_NAME}" redis-server --version

    echo
    info "Redis runtime test (PING):"

    verify_redis_runtime() (
        local test_name="docker-php-redis-build-test-$$"
        local ready=false
        local attempt

        cleanup_test_container() {
            docker rm -f "${test_name}" >/dev/null 2>&1 || true
        }
        trap cleanup_test_container EXIT

        if ! docker run -d --name "${test_name}" "${IMAGE_NAME}" >/dev/null; then
            error "Container uji Redis gagal dijalankan."
            return 1
        fi

        for attempt in {1..15}; do
            if docker exec "${test_name}" redis-cli ping 2>/dev/null | grep -qx 'PONG'; then
                ready=true
                break
            fi
            sleep 1
        done

        if [[ "${ready}" != true ]]; then
            docker logs "${test_name}" >&2 || true
            error "Redis tidak memberikan respons PONG."
            return 1
        fi

        success "Redis memberikan respons PONG."
    )

    verify_redis_runtime
}

show_image() {
    section "LOCAL REDIS IMAGE"
    docker images local/redis \
        --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
}

# ------------------------------------------------------------------------------
# PARSE ARGUMENTS
# ------------------------------------------------------------------------------
for arg in "$@"; do
    case "${arg}" in
        --no-cache)
            NO_CACHE=true
            FORCE_BUILD=true
            ;;
        --force)
            FORCE_BUILD=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Argument tidak dikenal: ${arg}"
            usage
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# BUILD PLAN
# ------------------------------------------------------------------------------
section "REDIS BUILD PLAN"
echo "  Image      : ${IMAGE_NAME}"
echo "  Dockerfile : ${DOCKERFILE}"
echo "  Build mode : $([[ "${NO_CACHE}" == true ]] && echo 'no-cache' || echo 'cache enabled')"
echo "  Rebuild    : $([[ "${FORCE_BUILD}" == true ]] && echo 'yes' || echo 'no')"

check_requirements
build_image
verify_image
show_image

success "Redis image berhasil dibuild dan diverifikasi."
