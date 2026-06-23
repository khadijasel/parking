# Backend Laravel 12 + MongoDB — image de déploiement (Render, Koyeb, Railway…)
#
# IMPORTANT : on utilise Apache (php:8.2-apache) et PAS `php artisan serve`.
# `php artisan serve` est un serveur de dev mono-thread (1 requête à la fois) :
# l'app et le site se bloqueraient mutuellement. Apache lance plusieurs workers
# et traite donc app + site + plusieurs utilisateurs EN MÊME TEMPS.
FROM php:8.2-apache

# Dépendances système + extension mongodb (requise par mongodb/laravel-mongodb)
RUN apt-get update && apt-get install -y \
        git unzip libzip-dev libssl-dev \
    && pecl install mongodb-1.21.0 \
    && docker-php-ext-enable mongodb \
    && docker-php-ext-install zip \
    && a2enmod rewrite \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Document root Apache = dossier public/ de Laravel
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Dépendances PHP (couche cachée tant que composer.* ne change pas)
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

# Code applicatif + finalisation
COPY . .
RUN composer dump-autoload --optimize --no-dev \
    && (php artisan package:discover --ansi || true) \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# L'hébergeur (Render/Koyeb) fournit le port via $PORT : on l'applique au démarrage
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8000
CMD ["docker-entrypoint.sh"]
