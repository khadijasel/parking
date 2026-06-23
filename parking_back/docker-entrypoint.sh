#!/bin/sh
set -e

# L'hébergeur (Render, etc.) impose le port via la variable $PORT.
# Apache doit écouter dessus, sinon l'hébergeur ne détecte pas le service.
PORT="${PORT:-8000}"
sed -ri "s!^Listen .*!Listen ${PORT}!g" /etc/apache2/ports.conf
sed -ri "s!<VirtualHost \*:[0-9]+>!<VirtualHost *:${PORT}>!g" /etc/apache2/sites-available/000-default.conf

exec apache2-foreground
