#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS=(7.4 8.3 8.4 8.5)

command -v docker >/dev/null 2>&1 || { echo "Docker tidak ditemukan." >&2; exit 1; }

for version in "${VERSIONS[@]}"; do
    echo "============================================================"
    echo "Building local/php:${version}"
    echo "============================================================"
    docker build -t "local/php:${version}" "${ROOT_DIR}/images/${version}"
done

echo
echo "Semua image selesai dibuild."
docker images local/php
