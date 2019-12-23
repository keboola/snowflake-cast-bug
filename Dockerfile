FROM ubuntu:18.04
RUN apt-get update
RUN apt-get install \
        curl \
        mc \
        -y

RUN /usr/bin/curl https://sfc-repo.snowflakecomputing.com/odbc/linux/2.20.2/snowflake-odbc-2.20.2.x86_64.deb -o /tmp/snowflake-odbc.deb

FROM php:7.1-apache
MAINTAINER Ondřej Jodas <ondrej.jodas@keboola.com>

ARG COMPOSER_FLAGS="--prefer-dist --no-interaction --classmap-authoritative"

ENV LANG en_US.UTF-8

RUN apt-get update -q \
   && apt-get install \
    gnupg \
    libmcrypt-dev \
    zlib1g-dev \
    git \
    libpq-dev \
    unixodbc-dev \
    unixodbc \
    python-setuptools \
    python3-pip \
    -y --no-install-recommends \
   && pip3 install -U setuptools \
   && easy_install supervisor

RUN docker-php-ext-install mcrypt zip pdo_mysql pdo_pgsql pcntl \
  && printf 'y\nn\n' | pecl install apcu \
  && docker-php-ext-enable apcu opcache

RUN a2enmod rewrite headers

## SNFLK drivers are storing OCSP cache in $HOME directory
## https://github.com/keboola/connection/issues/1065
RUN usermod -m -d /home/www-data www-data  \
    && chown -R www-data:www-data /home/www-data \
    && chmod u+rwx,g+rwx,o+rx /home/www-data \
    && echo "export HOME=/home/www-data" >> /etc/apache2/envvars

# Snowflake ODBC
# https://github.com/docker-library/php/issues/103#issuecomment-353674490
RUN set -ex; \
    docker-php-source extract; \
    { \
        echo '# https://github.com/docker-library/php/issues/103#issuecomment-353674490'; \
        echo 'AC_DEFUN([PHP_ALWAYS_SHARED],[])dnl'; \
        echo; \
        cat /usr/src/php/ext/odbc/config.m4; \
    } > temp.m4; \
    mv temp.m4 /usr/src/php/ext/odbc/config.m4; \
    docker-php-ext-configure odbc --with-unixODBC=shared,/usr; \
    docker-php-ext-install odbc; \
    docker-php-source delete

COPY --from=0 /tmp/snowflake-odbc.deb /tmp/snowflake-odbc.deb
RUN dpkg -i /tmp/snowflake-odbc.deb
ADD ./docker/php-apache/snowflake/simba.snowflake.ini /usr/lib/snowflake/odbc/lib/simba.snowflake.ini

WORKDIR /var/www/html

## Composer - deps always cached unless changed
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin/ --filename=composer

# First copy only composer files

COPY composer.* ./
# Download dependencies, but don't run scripts or init autoloaders as the app is missing
RUN composer install