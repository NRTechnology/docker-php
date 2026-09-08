FROM php:8.3-fpm-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip zip \
        libzip-dev libicu-dev libonig-dev libxml2-dev \
        libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev \
        libpq-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp

RUN docker-php-ext-install -j"$(nproc)" \
        bcmath curl exif gd intl mbstring mysqli opcache pcntl \
        pdo pdo_mysql pdo_pgsql xml zip

RUN pecl install redis-6.2.0 \
    && docker-php-ext-enable redis

COPY php.ini /usr/local/etc/php/conf.d/99-custom.ini

WORKDIR /var/www/html

CMD ["php-fpm", "-F"]
