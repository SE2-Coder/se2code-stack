FROM php:8.4-fpm-alpine

ENV PHP_EXTENSIONS="mysqli pdo_mysql gd intl zip exif bcmath soap sockets mbstring"

# Instalar dependencias del sistema y WP-CLI
RUN apk add --no-cache \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libwebp-dev \
    libzip-dev \
    icu-dev \
    libxml2-dev \
    imagemagick \
    imagemagick-dev \
    libtool \
    autoconf \
    build-base \
    linux-headers \
    curl \
    bash \
    unzip \
    oniguruma-dev \
    mariadb-client

# Configurar GD
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp
RUN docker-php-ext-install -j$(nproc) ${PHP_EXTENSIONS}

# Redis e Imagick
RUN pecl download imagick && \
    tar -xzf imagick-*.tgz && \
    cd imagick-* && \
    phpize && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf imagick-* && \
    docker-php-ext-enable imagick && \
    pecl install redis && docker-php-ext-enable redis

# Alineación UID/GID 33 (www-data) en Alpine
RUN deluser xfs 2>/dev/null || true && \
    sed -i 's/:82:82:/:33:33:/' /etc/passwd 2>/dev/null || true && \
    sed -i 's/:82:/:33:/' /etc/group 2>/dev/null || true

# Configurar OPcache con JIT
RUN echo "opcache.enable=1" > /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo "opcache.memory_consumption=256" >> /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo "opcache.interned_strings_buffer=16" >> /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo "opcache.max_accelerated_files=20000" >> /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo "opcache.validate_timestamps=1" >> /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo "opcache.revalidate_freq=60" >> /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo "opcache.save_comments=1" >> /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo "opcache.jit=1255" >> /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo "opcache.jit_buffer_size=128M" >> /usr/local/etc/php/conf.d/opcache-recommended.ini

# Instalar WP-CLI
RUN curl -sSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp

# Wrappers para MariaDB con --skip-ssl permanente (Bypass de Error 2026)
RUN printf '#!/bin/sh\nexec /usr/bin/mariadb-dump --skip-ssl "$@"\n' > /usr/local/bin/mariadb-dump && \
    chmod +x /usr/local/bin/mariadb-dump && \
    ln -sf /usr/local/bin/mariadb-dump /usr/local/bin/mysqldump && \
    printf '#!/bin/sh\nexec /usr/bin/mariadb --skip-ssl "$@"\n' > /usr/local/bin/mariadb && \
    chmod +x /usr/local/bin/mariadb && \
    ln -sf /usr/local/bin/mariadb /usr/local/bin/mysql

WORKDIR /var/www/html
CMD ["php-fpm"]
