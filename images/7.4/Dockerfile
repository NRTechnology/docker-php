FROM php:7.4-fpm-bullseye

ENV DEBIAN_FRONTEND=noninteractive

# Debian Bullseye telah dipindahkan ke Debian Archive.
# Gunakan archive.debian.org untuk menjaga kompatibilitas PHP 7.4.
RUN sed -i \
        -e 's|deb.debian.org/debian|archive.debian.org/debian|g' \
        -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
        -e '/bullseye-updates/d' \
        /etc/apt/sources.list \
    && printf '%s\n' \
        'Acquire::Check-Valid-Until "false";' \
        'Acquire::AllowInsecureRepositories "true";' \
        'Acquire::AllowDowngradeToInsecureRepositories "true";' \
        > /etc/apt/apt.conf.d/99archive \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip zip \
        libzip-dev libicu-dev libonig-dev libxml2-dev \
        libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev \
        libpq-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/99archive

RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp

RUN docker-php-ext-install -j"$(nproc)" \
        bcmath curl exif gd intl mbstring mysqli opcache pcntl \
        pdo pdo_mysql pdo_pgsql xml zip

RUN pecl install redis-5.3.7 \
    && docker-php-ext-enable redis

COPY php.ini /usr/local/etc/php/conf.d/99-custom.ini

WORKDIR /var/www/html

CMD ["php-fpm", "-F"]