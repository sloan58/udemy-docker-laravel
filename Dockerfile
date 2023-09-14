###########################################
# Build front-end assets
###########################################

FROM node:18 as node

WORKDIR /usr/app

COPY ./package*.json ./
COPY ./vite.config.js ./
COPY ./resources ./resources
COPY ./public ./public

RUN npm install && npm run build

###########################################
# Install PHP dependencies
###########################################

FROM composer:2 as composer

WORKDIR /usr/app

COPY ./composer* ./
RUN composer install \
#  --no-dev \
  --no-interaction \
  --prefer-dist \
  --ignore-platform-reqs \
  --optimize-autoloader \
  --apcu-autoloader \
  --ansi \
  --no-scripts \
  --audit

###########################################
# Build application image
###########################################

FROM php:8.2-cli-bullseye

LABEL maintainer="Marty Sloan"

ENV WWWUSER=1000 \
    WWWGROUP=1000 \
    TZ=UTC \
    DEBIAN_FRONTEND=noninteractive \
    TERM=xterm-color

WORKDIR /var/www/html

SHELL ["/bin/bash", "-eou", "pipefail", "-c"]

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update; \
    apt-get upgrade -yqq; \
    pecl -q channel-update pecl.php.net; \
    apt-get install -yqq --no-install-recommends --show-progress \
          apt-utils \
          gnupg \
          gosu \
          git \
          curl \
          wget \
          expect \
          build-essential  \
          libncurses5 \
          libcurl4-openssl-dev \
          ca-certificates \
          supervisor \
          libmemcached-dev \
          libz-dev \
          libbrotli-dev \
          libpq-dev \
          libjpeg-dev \
          libpng-dev \
          libfreetype6-dev \
          libssl-dev \
          libwebp-dev \
          libmcrypt-dev \
          libonig-dev \
          libzip-dev zip unzip \
          libargon2-1 \
          libidn2-0 \
          libpcre2-8-0 \
          libpcre3 \
          libxml2 \
          libzstd1 \
          procps \
          libbz2-dev \
          libldap2-dev \
          libxml2-dev


RUN docker-php-ext-install bz2 pdo_mysql mbstring soap opcache pcntl bcmath
RUN docker-php-ext-configure zip && docker-php-ext-install zip
RUN docker-php-ext-configure ldap && docker-php-ext-install ldap
RUN docker-php-ext-configure gd \
            --prefix=/usr \
            --with-jpeg \
            --with-webp \
            --with-freetype \
    && docker-php-ext-install gd

RUN pecl -q install -o -f redis \
      && rm -rf /tmp/pear \
      && docker-php-ext-enable redis

RUN apt-get install -yqq --no-install-recommends --show-progress libc-ares-dev \
      && pecl -q install -o -f -D 'enable-openssl="yes" enable-http2="yes" enable-swoole-curl="yes" enable-mysqlnd="yes" enable-cares="yes"' swoole \
      && docker-php-ext-enable swoole

RUN apt-get install -yqq --no-install-recommends --show-progress zlib1g-dev libicu-dev g++ \
      && docker-php-ext-configure intl \
      && docker-php-ext-install intl

RUN apt-get install -yqq --no-install-recommends --show-progress default-mysql-client

COPY ./ ./
COPY --from=node /usr/app/public ./public
COPY --from=composer /usr/app/vendor ./vendor
COPY ./docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY ./docker/php.ini /usr/local/etc/php/conf.d/octane.ini
COPY ./docker/opcache.ini /usr/local/etc/php/conf.d/opcache.ini
COPY ./docker/start-container /

RUN groupadd --force -g $WWWGROUP octane \
    && useradd -ms /bin/bash --no-log-init --no-user-group -g $WWWGROUP -u $WWWUSER octane

RUN mkdir -p \
  storage/framework/{sessions,views,cache} \
  storage/logs \
  bootstrap/cache \
  && chown -R octane:octane \
  storage \
  bootstrap/cache \
  && chmod -R ug+rwx storage bootstrap/cache

RUN apt-get clean \
    && docker-php-source delete \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && rm /var/log/lastlog /var/log/faillog

EXPOSE 8000

CMD ["/bin/bash", "/start-container"]
