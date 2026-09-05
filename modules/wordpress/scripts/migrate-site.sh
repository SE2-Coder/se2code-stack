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
echo -e "
${C_BOLD}--- Selección de Motor PHP ---${C_RESET}"
echo -e "  1) ${C_GREEN}PHP 8.4 (Estable - Recomendado para producción y compatibilidad con Elementor)${C_RESET}"
echo -e "  2) ${C_YELLOW}PHP 8.5 (Preview de última generación)${C_RESET}"
read -r -p "Selecciona versión [1-2, por defecto 1]: " PHP_CHOICE
PHP_CHOICE=${PHP_CHOICE:-1}

if [ "$PHP_CHOICE" = "2" ]; then
    PHP_CONTAINER="wp-php85"
    POOL_DIR="$STACK_ROOT/php/php85/pools"
else
    PHP_CONTAINER="wp-php84"
    POOL_DIR="$STACK_ROOT/php/php84/pools"
fi

# 4. Asignar puerto TCP dinámico (previene colisiones de puertos)
USED_PORTS=$(grep -shoE "listen = 0.0.0.0:[0-9]+" "$STACK_ROOT"/php/php*/pools/*.conf 2>/dev/null | awk -F: '{print $2}' || true)
NEXT_PORT=9001
while echo "$USED_PORTS" | grep -q "^${NEXT_PORT}$"; do
    NEXT_PORT=$((NEXT_PORT + 1))
done
PHP_PORT=$NEXT_PORT
log_ok "Motor asignado: $PHP_CONTAINER (Puerto TCP dinámico $PHP_PORT)"

# 5. Generar Pool PHP-FPM con la plantilla oficial
mkdir -p "$POOL_DIR"
sed -e "s/{{SITE_SLUG}}/$SITE_SLUG/g"     -e "s/{{PHP_PORT}}/$PHP_PORT/g"     "$STACK_ROOT/templates/php-pool.conf.tpl" > "$POOL_DIR/${SITE_SLUG}.conf"
log_ok "Pool PHP-FPM generado en $POOL_DIR/${SITE_SLUG}.conf"

# 6. Certificados SSL (Cloudflare Origin o Autofirmado Temporal)
CERTS_DIR="$STACK_ROOT/nginx/certs/$DOMAIN"
mkdir -p "$CERTS_DIR"

echo -e "
${C_BOLD}--- Certificados SSL (Cloudflare Origin Certificate) ---${C_RESET}"
read -r -p "¿Deseas pegar ahora los certificados de Cloudflare? [S/n]: " HAS_SSL
HAS_SSL=${HAS_SSL:-S}

if [[ "$HAS_SSL" =~ ^[Ss]$ ]]; then
    echo -e "
${C_CYAN}Pega el Certificado de Origen (Origin Certificate) y escribe 'EOF' en una línea nueva:${C_RESET}"
    SSL_CERT=""
    while IFS= read -r line; do
        [ "$line" = "EOF" ] && break
        SSL_CERT="${SSL_CERT}${line}
"
    done
    printf "%b" "$SSL_CERT" > "$CERTS_DIR/fullchain.pem"

    echo -e "
${C_CYAN}Pega la Llave Privada (Private Key) y escribe 'EOF' en una línea nueva:${C_RESET}"
    SSL_KEY=""
    while IFS= read -r line; do
        [ "$line" = "EOF" ] && break
        SSL_KEY="${SSL_KEY}${line}
"
    done
    printf "%b" "$SSL_KEY" > "$CERTS_DIR/privkey.pem"
    cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
    log_ok "Certificados SSL de Cloudflare instalados."
else
    log_warn "Generando certificados autofirmados temporales..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048         -keyout "$CERTS_DIR/privkey.pem"         -out "$CERTS_DIR/fullchain.pem"         -subj "/C=CO/ST=Valle/L=Cali/O=se2Code/CN=$DOMAIN" >/dev/null 2>&1
    cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
    log_warn "Certificados autofirmados temporales listos. Podrás actualizarlos luego con 'se2code -> Opción 7'."
fi

chmod 600 "$CERTS_DIR/privkey.pem"
chmod 644 "$CERTS_DIR"/*.pem

# 7. Configurar Virtual Host NGINX con la plantilla oficial
VHOST_FILE="$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"
mkdir -p "$STACK_ROOT/nginx/conf.d"
sed -e "s/{{SITE_SLUG}}/$SITE_SLUG/g"     -e "s/{{DOMAIN}}/$DOMAIN/g"     -e "s/{{PHP_CONTAINER}}/$PHP_CONTAINER/g"     -e "s/{{PHP_PORT}}/$PHP_PORT/g"     "$STACK_ROOT/templates/nginx-vhost.conf.tpl" > "$VHOST_FILE"
log_ok "Virtual Host NGINX configurado en $VHOST_FILE"

# 8. Crear Base de Datos y Usuario Aislado en MariaDB
log_section "CREANDO BASE DE DATOS Y USUARIO AISLADO"
DB_NAME="wp_${SITE_SLUG}_db"
DB_USER="wp_${SITE_SLUG}_user"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
MARIADB_ROOT_PASS=$(grep -E "^MYSQL_ROOT_PASSWORD=" "$STACK_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo "root_secret")

docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS '${DB_USER}'@'%';
CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;" 2>/dev/null || true
log_ok "Base de Datos '${DB_NAME}' y usuario '${DB_USER}' listos para recibir los datos."

# 9. Descomprimir Archivos Directamente en wp-data
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

# 10. Importar Base de Datos (.sql)
log_section "IMPORTANDO BASE DE DATOS (.SQL)"
log_step "Importando dump en la base de datos '${DB_NAME}'..."
if [[ "$SQL_FILE" =~ \.gz$ ]]; then
    zcat "$SQL_FILE" | docker exec -i mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl "$DB_NAME"
else
    docker exec -i mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl "$DB_NAME" < "$SQL_FILE"
fi
log_ok "Base de Datos importada con éxito."

# 11. Conectar y Reconfigurar wp-config.php Inteligente
log_section "CONECTANDO Y RECONFIGURANDO WP-CONFIG.PHP"

WP_CONFIG="$SITE_WEB_DIR/wp-config.php"

# Detectar prefijo de tablas real (desde MariaDB o wp-config)
TABLE_PREFIX="wp_"
DB_DETECTED_PREFIX=$(docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '${DB_NAME}' AND table_name LIKE '%options' LIMIT 1;" 2>/dev/null | tail -n 1 | sed 's/options$//' || true)
if [ -n "$DB_DETECTED_PREFIX" ]; then
    TABLE_PREFIX="$DB_DETECTED_PREFIX"
elif [ -f "$WP_CONFIG" ]; then
    FILE_PREFIX=$(grep -E "^\s*\\$table_prefix\s*=" "$WP_CONFIG" | head -n 1 | cut -d"'" -f2 2>/dev/null || true)
    [ -n "$FILE_PREFIX" ] && TABLE_PREFIX="$FILE_PREFIX"
fi
log_info "Prefijo de tablas detectado: '$TABLE_PREFIX'"
if [ -f "$WP_CONFIG" ]; then
    sed -E -i "s/^\s*\$table_prefix\s*=.*/\\$table_prefix = '${TABLE_PREFIX}';/" "$WP_CONFIG"
fi

# Reemplazar o insertar credenciales seguras de BD
if [ -f "$WP_CONFIG" ]; then
    sed -E -i "s/define\s*\(\s*['\"]DB_NAME['\"].*/define( 'DB_NAME', '${DB_NAME}' );/" "$WP_CONFIG"
    sed -E -i "s/define\s*\(\s*['\"]DB_USER['\"].*/define( 'DB_USER', '${DB_USER}' );/" "$WP_CONFIG"
    sed -E -i "s/define\s*\(\s*['\"]DB_PASSWORD['\"].*/define( 'DB_PASSWORD', '${DB_PASS}' );/" "$WP_CONFIG"
    sed -E -i "s/define\s*\(\s*['\"]DB_HOST['\"].*/define( 'DB_HOST', 'mariadb:3306' );/" "$WP_CONFIG"

    # Eliminar configuraciones de hosts o puertos anteriores
    sed -i "/WP_REDIS_HOST/d" "$WP_CONFIG"
    sed -i "/WP_REDIS_PORT/d" "$WP_CONFIG"
    sed -i "/WP_REDIS_PREFIX/d" "$WP_CONFIG"
    sed -i "/DISABLE_WP_CRON/d" "$WP_CONFIG"
    sed -i "/WP_CACHE/d" "$WP_CONFIG"
    sed -i "/WP_HOME/d" "$WP_CONFIG"
    sed -i "/WP_SITEURL/d" "$WP_CONFIG"

    # Insertar optimizaciones se2Code antes de table_prefix
    cat << CFG_SNIPPET > /tmp/se2code_snippet.txt

// Optimizaciones Maestras se2Code Stack (Auto-Inyectadas)
define( 'WP_HOME', 'https://${DOMAIN}' );
define( 'WP_SITEURL', 'https://${DOMAIN}' );
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

# 12. Permisos del Sistema de Archivos y Activación de Servicios
log_section "AJUSTANDO PERMISOS Y ACTIVANDO SERVICIOS"
log_step "Asignando propiedad de archivos a www-data (33:33)..."
chown -R 33:33 "$SITE_WEB_DIR" 2>/dev/null || true
find "$SITE_WEB_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
find "$SITE_WEB_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true
[ -f "$WP_CONFIG" ] && chmod 600 "$WP_CONFIG" 2>/dev/null || true

log_step "Recargando NGINX y reiniciando $PHP_CONTAINER..."
docker exec "$PHP_CONTAINER" chown -R www-data:www-data /var/log/php 2>/dev/null || true
docker restart "$PHP_CONTAINER" >/dev/null 2>&1 || true
docker exec wp-nginx nginx -t >/dev/null 2>&1 && docker exec wp-nginx nginx -s reload 2>/dev/null || docker restart wp-nginx >/dev/null 2>&1 || true
log_ok "NGINX recargado y motor PHP activado con el nuevo pool."

# 13. Cambio de Dominio / Staging (wp search-replace)
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

# 14. Paso Final: Optimización y Limpieza de Caché
log_section "PASO FINAL: OPTIMIZACIÓN Y LIMPIEZA DE CACHÉ"
bash "$SCRIPT_DIR/optimize-site.sh" "$SITE_SLUG"

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
