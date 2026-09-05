#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Asistente Automatizado de Migración WordPress
# Importación limpia de archivos (.tar.gz) + Base de Datos (.sql / .sql.gz)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "  ${C_BOLD}📥 ASISTENTE DE MIGRACIÓN AUTOMATIZADA WORDPRESS (.tar.gz + .sql)${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}\n"

# 1. Solicitar Dominio Destino
while true; do
    read -r -p "Ingresa el dominio a configurar en este servidor (ej: misitio.com o staging.misitio.com): " DOMAIN
    DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | xargs)
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        log_error "Formato de dominio no válido. Intenta de nuevo."
    fi
done

SITE_SLUG=$(echo "$DOMAIN" | tr -cd 'a-zA-Z0-9')
SITE_WEB_DIR="$STACK_ROOT/wp-data/$SITE_SLUG"
CONTAINER_PATH="/var/www/html/$SITE_SLUG"
VHOST_FILE="$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"

# Verificar si el sitio ya existe
if [ -d "$SITE_WEB_DIR" ] || [ -f "$VHOST_FILE" ]; then
    log_warn "Ya existe una configuración o directorio para '$DOMAIN' ($SITE_SLUG)."
    read -r -p "¿Deseas sobrescribir esta instalación existente? [s/N]: " OVERWRITE
    if [[ ! "$OVERWRITE" =~ ^[Ss]$ ]]; then
        log_info "Migración cancelada."
        exit 0
    fi
    rm -rf "$SITE_WEB_DIR" "$VHOST_FILE" 2>/dev/null || true
fi

# 2. Rutas de los Archivos de Migración
echo -e "\n${C_BOLD}--- Archivos de Respaldo a Migrar ---${C_RESET}"

while true; do
    read -r -p "Ruta absoluta del archivo de archivos (.tar.gz / .tar / .zip) [ej: /root/sitio.tar.gz]: " TAR_FILE
    TAR_FILE=$(echo "$TAR_FILE" | xargs)
    if [ -f "$TAR_FILE" ]; then
        log_ok "Archivo de archivos detectado: $TAR_FILE"
        break
    else
        log_error "El archivo '$TAR_FILE' no existe en el servidor. Verifica la ruta."
    fi
done

while true; do
    read -r -p "Ruta absoluta de la Base de Datos (.sql / .sql.gz) [ej: /root/bd.sql]: " SQL_FILE
    SQL_FILE=$(echo "$SQL_FILE" | xargs)
    if [ -f "$SQL_FILE" ]; then
        log_ok "Archivo de Base de Datos detectado: $SQL_FILE"
        break
    else
        log_error "El archivo '$SQL_FILE' no existe en el servidor. Verifica la ruta."
    fi
done

# 3. Selección de Motor PHP
echo -e "\n${C_BOLD}--- Selección de Motor PHP ---${C_RESET}"
echo -e "  1) ${C_GREEN}PHP 8.4 (Estable - Recomendado para producción y compatibilidad con Elementor)${C_RESET}"
echo -e "  2) ${C_YELLOW}PHP 8.5 (Preview de última generación)${C_RESET}"
read -r -p "Selecciona versión [1-2, por defecto 1]: " PHP_CHOICE
PHP_CHOICE=${PHP_CHOICE:-1}

if [ "$PHP_CHOICE" = "2" ]; then
    PHP_CONTAINER="wp-php85"
    PHP_PORT="9002"
    PHP_POOLS_DIR="$STACK_ROOT/php/pools-85"
else
    PHP_CONTAINER="wp-php84"
    PHP_PORT="9001"
    PHP_POOLS_DIR="$STACK_ROOT/php/pools-84"
fi
log_ok "Motor asignado: $PHP_CONTAINER (Puerto TCP $PHP_PORT)"

# 4. Certificados SSL de Cloudflare
CERTS_DIR="$STACK_ROOT/nginx/certs/$DOMAIN"
mkdir -p "$CERTS_DIR"

echo -e "\n${C_BOLD}--- Certificados SSL (Cloudflare Origin Certificate) ---${C_RESET}"
read -r -p "¿Deseas pegar ahora los certificados de Cloudflare? [S/n]: " HAS_SSL
HAS_SSL=${HAS_SSL:-S}

if [[ "$HAS_SSL" =~ ^[Ss]$ ]]; then
    echo -e "\n${C_CYAN}Pega el Certificado de Origen (Origin Certificate) y escribe 'EOF' en una línea nueva:${C_RESET}"
    SSL_CERT=""
    while IFS= read -r line; do
        [ "$line" = "EOF" ] && break
        SSL_CERT="${SSL_CERT}${line}\n"
    done
    printf "%b" "$SSL_CERT" > "$CERTS_DIR/fullchain.pem"

    echo -e "\n${C_CYAN}Pega la Llave Privada (Private Key) y escribe 'EOF' en una línea nueva:${C_RESET}"
    SSL_KEY=""
    while IFS= read -r line; do
        [ "$line" = "EOF" ] && break
        SSL_KEY="${SSL_KEY}${line}\n"
    done
    printf "%b" "$SSL_KEY" > "$CERTS_DIR/privkey.pem"
    cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
    chmod 600 "$CERTS_DIR/privkey.pem"
    chmod 644 "$CERTS_DIR"/*.pem
    log_ok "Certificados SSL instalados."
else
    log_warn "Generando certificado autofirmado temporal..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERTS_DIR/privkey.pem" \
        -out "$CERTS_DIR/fullchain.pem" \
        -subj "/CN=$DOMAIN" >/dev/null 2>&1
    cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
    chmod 600 "$CERTS_DIR/privkey.pem"
    chmod 644 "$CERTS_DIR"/*.pem
    log_ok "Certificado temporal listo. Podrás actualizarlo luego con 'se2code -> Opción 7'."
fi

# 5. Configurar PHP-FPM Pool Aislado
mkdir -p "$PHP_POOLS_DIR"
POOL_FILE="$PHP_POOLS_DIR/${SITE_SLUG}.conf"
cat << POOL_EOF > "$POOL_FILE"
[${SITE_SLUG}]
user = www-data
group = www-data
listen = ${PHP_PORT}
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = 20
pm.process_idle_timeout = 10s
pm.max_requests = 1000

php_admin_value[memory_limit] = 1024M
php_admin_value[upload_max_filesize] = 256M
php_admin_value[post_max_size] = 256M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
php_admin_value[sendmail_path] = /bin/true
php_admin_value[opcache.enable] = 1
php_admin_value[opcache.jit] = 1255

catch_workers_output = yes
php_admin_value[error_log] = /var/log/php/${SITE_SLUG}.error.log
php_admin_flag[log_errors] = on
access.log = /var/log/php/${SITE_SLUG}.access.log
POOL_EOF
log_ok "Pool PHP-FPM aislado configurado en $POOL_FILE."

# 6. Configurar Virtual Host NGINX con FastCGI Microcache
mkdir -p "$STACK_ROOT/nginx/conf.d"
cat << NGINX_EOF > "$VHOST_FILE"
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate /etc/nginx/certs/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/${DOMAIN}/privkey.pem;

    root /var/www/html/${SITE_SLUG};
    index index.php index.html index.htm;

    access_log /var/log/nginx/${SITE_SLUG}.access.log;
    error_log /var/log/nginx/${SITE_SLUG}.error.log;

    # Evitar cacheo de peticiones no GET/HEAD, query strings o logins/carritos
    set \$skip_cache 0;
    if (\$request_method = POST) { set \$skip_cache 1; }
    if (\$query_string != "") { set \$skip_cache 1; }
    if (\$request_uri ~* "/wp-admin/|/xmlrpc.php|wp-.*.php|/feed/|index.php|sitemap(_index)?.xml") { set \$skip_cache 1; }
    if (\$http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in|woocommerce_items_in_cart") { set \$skip_cache 1; }

    # Regla de purga Nginx Helper
    location ~ /purge(/.*) {
        fastcgi_cache_purge WORDPRESS "\$scheme\$request_method\$host\$1";
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass ${PHP_CONTAINER}:${PHP_PORT};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;

        fastcgi_cache WORDPRESS;
        fastcgi_cache_bypass \$skip_cache;
        fastcgi_no_cache \$skip_cache;
        fastcgi_cache_valid 200 301 302 60m;
        fastcgi_cache_use_stale error timeout updating invalid_header http_500 http_503;
        fastcgi_cache_min_uses 1;
        fastcgi_cache_lock on;
        add_header X-FastCGI-Cache \$upstream_cache_status;
        add_header X-Cache-Status \$upstream_cache_status;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires max;
        log_not_found off;
        access_log off;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
NGINX_EOF
log_ok "Nginx Virtual Host con FastCGI Microcache configurado en $VHOST_FILE."

# 7. Crear Base de Datos y Usuario Aislado en MariaDB
log_section "CREANDO BASE DE DATOS Y USUARIO AISLADO"
DB_NAME="wp_${SITE_SLUG}_db"
DB_USER="wp_${SITE_SLUG}_user"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
MARIADB_ROOT_PASS=$(grep -E "^MYSQL_ROOT_PASSWORD=" "$STACK_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo "root_secret")

docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;" 2>/dev/null || true
log_ok "Base de Datos '${DB_NAME}' y usuario '${DB_USER}' listos para recibir los datos."

# 8. Descomprimir Archivos Directamente en wp-data
log_section "DESCOMPRIMIENDO ARCHIVOS DE WORDPRESS"
mkdir -p "$SITE_WEB_DIR"

log_step "Extrayendo $TAR_FILE en $SITE_WEB_DIR..."
# Detectar si los archivos vienen envueltos en una subcarpeta (ej: public_html/ o wordpress/)
SAMPLE_PATH=$(tar -tf "$TAR_FILE" 2>/dev/null | head -n 10 | grep -E "wp-config\.php|wp-login\.php" || true)

if [ -n "$SAMPLE_PATH" ] && [[ "$SAMPLE_PATH" =~ / ]]; then
    TOP_DIR=$(echo "$SAMPLE_PATH" | cut -d/ -f1)
    log_info "Los archivos están anidados en la carpeta '$TOP_DIR'. Extrayendo con --strip-components=1..."
    tar -xzf "$TAR_FILE" -C "$SITE_WEB_DIR" --strip-components=1 2>/dev/null || tar -xf "$TAR_FILE" -C "$SITE_WEB_DIR" --strip-components=1
else
    log_info "Extrayendo archivos directamente en la raíz..."
    tar -xzf "$TAR_FILE" -C "$SITE_WEB_DIR" 2>/dev/null || tar -xf "$TAR_FILE" -C "$SITE_WEB_DIR"
fi
log_ok "Archivos de WordPress extraídos exitosamente."

# 9. Importar Base de Datos
log_section "IMPORTANDO BASE DE DATOS (.SQL)"
log_step "Importando dump en la base de datos '${DB_NAME}'..."
if [[ "$SQL_FILE" =~ \.gz$ ]]; then
    zcat "$SQL_FILE" | docker exec -i mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl "$DB_NAME"
else
    docker exec -i mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl "$DB_NAME" < "$SQL_FILE"
fi
log_ok "Base de Datos importada con éxito."

# 10. Reconfigurar wp-config.php Inteligente
log_section "CONECTANDO Y RECONFIGURANDO WP-CONFIG.PHP"

WP_CONFIG="$SITE_WEB_DIR/wp-config.php"

# Detectar prefijo de tablas original
TABLE_PREFIX="wp_"
if [ -f "$WP_CONFIG" ]; then
    DETECTED_PREFIX=$(grep -E "^\s*\\\$table_prefix\s*=" "$WP_CONFIG" | head -n 1 | cut -d"'" -f2 2>/dev/null || true)
    [ -n "$DETECTED_PREFIX" ] && TABLE_PREFIX="$DETECTED_PREFIX"
fi
log_info "Prefijo de tablas detectado: '$TABLE_PREFIX'"

# Reemplazar o insertar credenciales seguras de BD
if [ -f "$WP_CONFIG" ]; then
    sed -i "s/define(\s*['\"]DB_NAME['\"].*/define( 'DB_NAME', '${DB_NAME}' );/" "$WP_CONFIG"
    sed -i "s/define(\s*['\"]DB_USER['\"].*/define( 'DB_USER', '${DB_USER}' );/" "$WP_CONFIG"
    sed -i "s/define(\s*['\"]DB_PASSWORD['\"].*/define( 'DB_PASSWORD', '${DB_PASS}' );/" "$WP_CONFIG"
    sed -i "s/define(\s*['\"]DB_HOST['\"].*/define( 'DB_HOST', 'mariadb:3306' );/" "$WP_CONFIG"

    # Eliminar configuraciones de hosts o puertos anteriores
    sed -i "/WP_REDIS_HOST/d" "$WP_CONFIG"
    sed -i "/WP_REDIS_PORT/d" "$WP_CONFIG"
    sed -i "/WP_REDIS_PREFIX/d" "$WP_CONFIG"
    sed -i "/DISABLE_WP_CRON/d" "$WP_CONFIG"
    sed -i "/WP_CACHE/d" "$WP_CONFIG"

    # Insertar optimizaciones se2Code antes de table_prefix
    cat << CFG_SNIPPET > /tmp/se2code_snippet.txt

// Optimizaciones Maestras se2Code Stack (Auto-Inyectadas)
define( 'FORCE_SSL_ADMIN', true );
define( 'DISALLOW_FILE_EDIT', true );
define( 'WP_MEMORY_LIMIT', '1024M' );
define( 'WP_MAX_MEMORY_LIMIT', '1024M' );
define( 'CONCATENATE_SCRIPTS', true );
define( 'DISABLE_WP_CRON', true );

// Detección de Proxy Reverso y Cloudflare HTTPS
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && 'https' === \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) {
    \$_SERVER['HTTPS'] = 'on';
}
if ( isset( \$_SERVER['HTTP_CF_VISITOR'] ) && false !== strpos( \$_SERVER['HTTP_CF_VISITOR'], 'https' ) ) {
    \$_SERVER['HTTPS'] = 'on';
}

// Redis Object Cache
define( 'WP_CACHE', true );
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PREFIX', '${SITE_SLUG}_' );
define( 'WP_REDIS_TIMEOUT', 1 );
define( 'WP_REDIS_READ_TIMEOUT', 1 );
CFG_SNIPPET

    sed -i "/\\\$table_prefix/r /tmp/se2code_snippet.txt" "$WP_CONFIG"
    rm -f /tmp/se2code_snippet.txt
    log_ok "wp-config.php reconectado a MariaDB y configurado con Redis."
fi

# 11. Opción wp search-replace para Staging o Cambio de Dominio
log_section "CAMBIO DE DOMINIO / STAGING (SEARCH & REPLACE)"

echo -e "¿Deseas ejecutar un reemplazo de URL en la base de datos (${C_YELLOW}wp search-replace${C_RESET})?"
echo -e "  (Indispensable si vienes de otro dominio o estás creando un entorno de ${C_BOLD}Staging / Dev${C_RESET})"
read -r -p "¿Ejecutar reemplazo de dominio? [S/n]: " DO_REPLACE
DO_REPLACE=${DO_REPLACE:-S}

if [[ "$DO_REPLACE" =~ ^[Ss]$ ]]; then
    # Intentar detectar el dominio previo desde wp_options
    OLD_SITEURL=$(docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "SELECT option_value FROM \`${DB_NAME}\`.${TABLE_PREFIX}options WHERE option_name = 'siteurl' LIMIT 1;" 2>/dev/null | tail -n 1 || true)
    
    echo -e "\nDominio previo detectado en la BD: ${C_YELLOW}${OLD_SITEURL:-'No detectado'}${C_RESET}"
    read -r -p "Escribe la URL vieja a buscar [ej: ${OLD_SITEURL:-https://viejo-dominio.com}]: " SEARCH_URL
    SEARCH_URL=${SEARCH_URL:-$OLD_SITEURL}
    
    DEST_DEFAULT="https://${DOMAIN}"
    read -r -p "Escribe la URL nueva de reemplazo [por defecto: $DEST_DEFAULT]: " REPLACE_URL
    REPLACE_URL=${REPLACE_URL:-$DEST_DEFAULT}

    if [ -n "$SEARCH_URL" ] && [ -n "$REPLACE_URL" ] && [ "$SEARCH_URL" != "$REPLACE_URL" ]; then
        log_step "Ejecutando: wp search-replace '$SEARCH_URL' '$REPLACE_URL' --all-tables --precise..."
        docker exec --user 33:33 "$PHP_CONTAINER" wp search-replace "$SEARCH_URL" "$REPLACE_URL" --all-tables --precise --skip-columns=guid --path="$CONTAINER_PATH" || true
        log_ok "Reemplazo de URLs completado en todas las tablas."
    else
        log_info "No hubo cambios de URL."
    fi
fi

# 12. Optimización y Desactivación de Plugins de Caché
log_section "PASO FINAL: OPTIMIZACIÓN Y LIMPIEZA DE CACHÉ"
bash "$STACK_ROOT/modules/wordpress/scripts/optimize-site.sh" "$SITE_SLUG"

echo -e "\n${C_BOLD}${C_GREEN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}       🎉 ¡MIGRACIÓN COMPLETADA EXITOSAMENTE CON SE2CODE!             ${C_RESET}"
echo -e "${C_GREEN}======================================================================${C_RESET}\n"
echo -e "  - Sitio Web       : ${C_CYAN}https://${DOMAIN}${C_RESET}"
echo -e "  - Carpeta Web     : ${SITE_WEB_DIR}"
echo -e "  - Base de Datos   : ${C_GREEN}${DB_NAME}${C_RESET}"
echo -e "  - Usuario BD      : ${C_CYAN}${DB_USER}${C_RESET}"
echo -e "  - Contraseña BD   : ${DB_PASS}"
echo -e "  - Motor PHP       : ${PHP_CONTAINER} (Puerto TCP ${PHP_PORT})"
echo -e "  - FastCGI Cache   : ${C_GREEN}Activo${C_RESET}"
echo -e "  - Redis Cache     : ${C_GREEN}Activo (Prefijo: ${SITE_SLUG}_)${C_RESET}\n"

echo -e "${C_BOLD}${C_YELLOW}⚡ RECORDATORIO FUNDAMENTAL:${C_RESET}"
echo -e "  ${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e "  ⚠️  ${C_BOLD}NO instales plugins de caché adicionales${C_RESET} en este WordPress."
echo -e "  Si tu respaldo contenía WP Rocket, LiteSpeed u otros, el optimizador"
echo -e "  los ha desactivado automáticamente para garantizar máxima velocidad."
echo -e "  ${C_CYAN}----------------------------------------------------------------------${C_RESET}\n"
