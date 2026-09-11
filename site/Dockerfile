FROM php:8.3-fpm-alpine
RUN set -eux; \
    { \
      echo "file_uploads = On"; \
      echo "upload_max_filesize = 512M"; \
      echo "post_max_size = 512M"; \
      echo "memory_limit = 256M"; \
      echo "max_execution_time = 300"; \
      echo "expose_php = Off"; \
    } > /usr/local/etc/php/conf.d/zz-uploads.ini
WORKDIR /var/www/site
