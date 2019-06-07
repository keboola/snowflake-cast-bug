FROM ubuntu:18.04
RUN apt-get update
RUN apt-get install \
                curl \
                mc \
                -y

RUN /usr/bin/curl https://sfc-repo.snowflakecomputing.com/odbc/linux/2.19.3/snowflake-odbc-2.19.3.x86_64.deb -o /tmp/snowflake-odbc.deb

FROM php:7.1-apache
MAINTAINER Ondřej Jodas <ondrej.jodas@keboola.com>


# snowflake - charset settings
# ENV LANGUAGE=en_US.UTF-8
# ENV LANG=en_US.UTF-8
# ENV LC_ALL=en_US.UTF-8

# New Relic
RUN echo 'deb http://apt.newrelic.com/debian/ newrelic non-free' | tee /etc/apt/sources.list.d/newrelic.list

RUN apt-get update -q \
   && apt-get install gnupg -y --no-install-recommends \
   && curl -sS https://download.newrelic.com/548C16BF.gpg | apt-key add - \
   && apt-get update -q \
   && apt-get install \
    libmcrypt-dev \
    zlib1g-dev \
    mysql-client \
    gnupg \
    newrelic-php5 \
    git \
    libpq-dev \
    unixodbc-dev \
    unixodbc \
    python-setuptools \
    -y --no-install-recommends \
   && easy_install supervisor \
   &&  newrelic-install install

RUN docker-php-ext-install mcrypt zip pdo_mysql pdo_pgsql pcntl \
  && printf 'y\nn\n' | pecl install apcu \
  && docker-php-ext-enable apcu opcache

RUN a2enmod rewrite headers

RUN echo  "newrelic.license = 50cd0bf7c4d3a616d0a74e64e7a129f50b85d70f" >> /usr/local/etc/php/conf.d/newrelic.ini
RUN echo  "newrelic.distributed_tracing_enabled = false" >> /usr/local/etc/php/conf.d/newrelic.ini
RUN echo  "newrelic.cross_application_tracer.enabled = false" >> /usr/local/etc/php/conf.d/newrelic.ini

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