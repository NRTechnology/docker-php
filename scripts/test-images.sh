#!/usr/bin/env bash
set -Eeuo pipefail

VERSIONS=(7.4 8.3 8.4 8.5)

for version in "${VERSIONS[@]}"; do
    image="local/php:${version}"

    echo "============================================================"
    echo "Testing ${image}"
    echo "============================================================"

    docker image inspect "${image}" >/dev/null
    docker run --rm "${image}" php -v
    docker run --rm "${image}" php -m
    docker run --rm "${image}" php -i | grep -E 'memory_limit|upload_max_filesize|post_max_size|opcache.enable|date.timezone'
    docker run --rm "${image}" php-fpm -t

done

echo
echo "Semua image lulus pengujian dasar."
