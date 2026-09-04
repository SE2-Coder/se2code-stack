#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WordPress: Aprovisionador de Sitios
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

# Cargar utilidades si existen
[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

SITE_SLUG="${1:-}"
DOMAIN="${2:-}"
PHP_VERSION="${3:-}"

# Modo interactivo si faltan argumentos
if [ -z "$SITE_SLUG" ]; then
    echo -e "${C_BOLD}${C_CYAN}--- Aprovisionamiento de Nuevo Sitio WordPress ---${C_RESET}"
    read -r -p "Identificador / Slug del sitio (ej: clinicaerika): " SITE_SLUG
fi

if [ -z "$DOMAIN" ]; then
    read -r -p "Dominio principal (ej: skincarebeautyholic.com): " DOMAIN
fi

if [ -z "$PHP_VERSION" ]; then
    echo -e "Selecciona la versión de PHP:"
    echo -e "  1) PHP 8.5 (Última generación - Recomendada)"
    echo -e "  2) PHP 8.4 (Estable)"
    read -r -p "Opción [1-2]: " PHP_OPT
    if [ "$PHP_OPT" = "2" ]; then
        PHP_VERSION="8.4"
    else
        PHP_VERSION="8.5"
    fi
fi

# Sanitizar
SITE_SLUG=$(echo "$SITE_SLUG" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')
DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-')

if [ "$PHP_VERSION" = "8.4" ]; then
    PHP_CONTAINER="wp-php84"
    POOL_DIR="$STACK_ROOT/php/php84/pools"
else
    PHP_CONTAINER="wp-php85"
    POOL_DIR="$STACK_ROOT/php/php85/pools"
fi

log_step "Aprovisionando sitio: $SITE_SLUG ($DOMAIN) en $PHP_CONTAINER..."

# 1. Asignar puerto TCP dinámico
USED_PORTS=$(grep -shoE "listen = 0.0.0.0:[0-9]+" "$STACK_ROOT"/php/php*/pools/*.conf 2>/dev/null | awk -F: '{print $2}' || true)
NEXT_PORT=9001
while echo "$USED_PORTS" | grep -q "^${NEXT_PORT}$"; do
    NEXT_PORT=$((NEXT_PORT + 1))
done
PHP_PORT=$NEXT_PORT
log_ok "Puerto PHP-FPM asignado: $PHP_PORT"

# 2. Generar Pool PHP-FPM
sed -e "s/{{SITE_SLUG}}/$SITE_SLUG/g" \
    -e "s/{{PHP_PORT}}/$PHP_PORT/g" \
    "$STACK_ROOT/templates/php-pool.conf.tpl" > "$POOL_DIR/${SITE_SLUG}.conf"
log_ok "Pool PHP-FPM generado en $POOL_DIR/${SITE_SLUG}.conf"

# 3. Certificados SSL (Pegar Cloudflare o Autofirmado)
CERTS_DIR="$STACK_ROOT/nginx/certs/$DOMAIN"
mkdir -p "$CERTS_DIR"

echo -e "\n${C_BOLD}[?] ¿Cómo deseas configurar el SSL para $DOMAIN?${C_RESET}"
echo -e "    1) Pegar los certificados de Cloudflare ahora mismo"
echo -e "    2) Generar certificados autofirmados temporales (para cambiarlos después)"
read -r -p "Opción [1-2]: " SSL_CHOICE

if [ "$SSL_CHOICE" = "1" ]; then
    echo -e "\n${C_CYAN}Pega el Certificado de Origen (Origin Certificate) y escribe 'EOF' en una línea sola al terminar:${C_RESET}"
    SSL_CERT=""
    while IFS= read -r line; do
        [ "$line" = "EOF" ] && break
        SSL_CERT="${SSL_CERT}${line}\n"
    done
    printf "%b" "$SSL_CERT" > "$CERTS_DIR/fullchain.pem"

    echo -e "\n${C_CYAN}Pega la Llave Privada (Private Key) y escribe 'EOF' en una línea sola al terminar:${C_RESET}"
    SSL_KEY=""
    while IFS= read -r line; do
        [ "$line" = "EOF" ] && break
        SSL_KEY="${SSL_KEY}${line}\n"
    done
    printf "%b" "$SSL_KEY" > "$CERTS_DIR/privkey.pem"
    cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
    log_ok "Certificados SSL de Cloudflare guardados."
else
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERTS_DIR/privkey.pem" \
        -out "$CERTS_DIR/fullchain.pem" \
        -subj "/C=CO/ST=Valle/L=Cali/O=se2Code/CN=$DOMAIN" >/dev/null 2>&1
    cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
    log_warn "Certificados autofirmados temporales generados."
fi

chmod 600 "$CERTS_DIR/privkey.pem"
chmod 644 "$CERTS_DIR"/*.pem

# 4. Generar Virtual Host NGINX
sed -e "s/{{SITE_SLUG}}/$SITE_SLUG/g" \
    -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{PHP_CONTAINER}}/$PHP_CONTAINER/g" \
    -e "s/{{PHP_PORT}}/$PHP_PORT/g" \
    "$STACK_ROOT/templates/nginx-vhost.conf.tpl" > "$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"
log_ok "Virtual Host NGINX generado en $STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"

# 5. Directorio web de WordPress
SITE_WEB_DIR="$STACK_ROOT/wp-data/$SITE_SLUG"
mkdir -p "$SITE_WEB_DIR"

# Descargar WordPress si está vacío
if [ ! -f "$SITE_WEB_DIR/wp-login.php" ]; then
    log_info "Descargando WordPress Core..."
    curl -sSL https://wordpress.org/latest.tar.gz | tar -xz -C "$SITE_WEB_DIR" --strip-components=1
    log_ok "WordPress descargado."
fi

# 6. Crear Base de Datos en MariaDB
DB_NAME="wp_${SITE_SLUG}_db"
DB_USER="wp_${SITE_SLUG}_user"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

# Obtener password root de mariadb
MARIADB_ROOT_PASS=$(grep -E "^MYSQL_ROOT_PASSWORD=" "$STACK_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo "root_secret")

docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;" 2>/dev/null || true
log_ok "Base de Datos '${DB_NAME}' y usuario '${DB_USER}' creados."

# 7. Generar wp-config.php Blindado (Con 1024M, no-concatenate, no-cron)
if [ ! -f "$SITE_WEB_DIR/wp-config.php" ]; then
    SALT_KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ || true)
    cat << WPCONF > "$SITE_WEB_DIR/wp-config.php"
<?php
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASS}' );
define( 'DB_HOST', 'mariadb:3306' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', 'utf8mb4_unicode_ci' );

${SALT_KEYS}

\$table_prefix = 'wp_';

// Optimizaciones Maestras se2Code Stack
define( 'FORCE_SSL_ADMIN', true );
define( 'DISALLOW_FILE_EDIT', true );
define( 'WP_MEMORY_LIMIT', '1024M' );
define( 'WP_MAX_MEMORY_LIMIT', '1024M' );
define( 'CONCATENATE_SCRIPTS', false );
define( 'DISABLE_WP_CRON', true );

// Redis Cache
define( 'WP_CACHE', true );
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PREFIX', '${SITE_SLUG}_' );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
WPCONF
    chmod 600 "$SITE_WEB_DIR/wp-config.php"
    log_ok "wp-config.php optimizado generado."
fi

# Permisos 33:33 (www-data)
sudo chown -R 33:33 "$SITE_WEB_DIR" 2>/dev/null || chown -R 33:33 "$SITE_WEB_DIR" 2>/dev/null || true
find "$SITE_WEB_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
find "$SITE_WEB_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true
[ -f "$SITE_WEB_DIR/wp-config.php" ] && chmod 600 "$SITE_WEB_DIR/wp-config.php"

# 8. Recargar NGINX y Reiniciar PHP
docker exec wp-nginx nginx -s reload 2>/dev/null || true
docker restart "$PHP_CONTAINER" >/dev/null 2>&1 || true

echo -e "\n${C_BOLD}${C_GREEN}✔ SITIO APROVISIONADO EXITOSAMENTE${C_RESET}"
echo -e "  - Dominio       : https://${DOMAIN}"
echo -e "  - Carpeta Web   : ${SITE_WEB_DIR}"
echo -e "  - Base de Datos : ${DB_NAME}"
echo -e "  - Usuario BD    : ${DB_USER}"
echo -e "  - Contraseña BD : ${DB_PASS}"
echo -e "  - Motor PHP     : ${PHP_CONTAINER} (Puerto TCP ${PHP_PORT})"
