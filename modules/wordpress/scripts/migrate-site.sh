#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Asistente Automatizado de Migración WordPress
# Importación limpia de archivos (.tar.gz / .tar / .zip) + BD (.sql / .sql.gz)
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
    rm -f "$STACK_ROOT"/php/php*/pools/"${SITE_SLUG}".conf 2>/dev/null || true
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
echo -e "  2) ${C_YELLOW}PHP 8.5 (Preview experimental - No recomendada en producción)${C_RESET}"
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
sed -e "s/{{SITE_SLUG}}/$SITE_SLUG/g" \
    -e "s/{{PHP_PORT}}/$PHP_PORT/g" \
    "$STACK_ROOT/templates/php-pool.conf.tpl" > "$POOL_DIR/${SITE_SLUG}.conf"
log_ok "Pool PHP-FPM generado en $POOL_DIR/${SITE_SLUG}.conf"

# 6. Certificados SSL (Cloudflare Origin, Let's Encrypt o Autofirmado)
CERTS_DIR="$STACK_ROOT/nginx/certs/$DOMAIN"
mkdir -p "$CERTS_DIR"

echo -e "\n${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_BOLD}CONFIGURACIÓN DE CERTIFICADO SSL/TLS${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "Selecciona el tipo de certificado para ${C_YELLOW}${DOMAIN}${C_RESET}:\n"
echo -e "  1) ${C_GREEN}Pegar certificados de Cloudflare (Origin CA)${C_RESET}"
echo -e "     ${C_GRAY}↳ Para sitios detrás de Cloudflare. Válido hasta por 15 años.${C_RESET}\n"
echo -e "  2) ${C_CYAN}Let's Encrypt automático (acme.sh)${C_RESET}"
echo -e "     ${C_GRAY}↳ Certificado público oficial con candado verde directo (sin Cloudflare).${C_RESET}\n"
echo -e "  3) ${C_YELLOW}Certificado autofirmado (Rápido / Pruebas / Cloudflare)${C_RESET}"
echo -e "     ${C_GRAY}↳ Generación instantánea. Para pruebas o si ya usas Cloudflare (modo Full).${C_RESET}\n"

read -r -p "Elige una opción [1-3, por defecto 3]: " SSL_CHOICE
SSL_CHOICE=${SSL_CHOICE:-3}

NEED_ACME=false

case "$SSL_CHOICE" in
    1)
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
        log_ok "Certificados SSL de Cloudflare guardados."
        ;;
    2)
        log_info "Configurando certificado provisional para inicializar NGINX..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$CERTS_DIR/privkey.pem" \
            -out "$CERTS_DIR/fullchain.pem" \
            -subj "/C=CO/ST=Valle/L=Cali/O=se2Code/CN=$DOMAIN" >/dev/null 2>&1
        cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
        NEED_ACME=true
        log_ok "Certificado provisional listo. Se emitirá Let's Encrypt al activar los servicios."
        ;;
    3|*)
        log_step "Generando certificados autofirmados..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$CERTS_DIR/privkey.pem" \
            -out "$CERTS_DIR/fullchain.pem" \
            -subj "/C=CO/ST=Valle/L=Cali/O=se2Code/CN=$DOMAIN" >/dev/null 2>&1
        cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
        log_ok "Certificados autofirmados generados y activos."
        ;;
esac

chmod 600 "$CERTS_DIR/privkey.pem"
chmod 644 "$CERTS_DIR"/*.pem

# 7. Configurar Virtual Host NGINX con la plantilla oficial
VHOST_FILE="$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"
mkdir -p "$STACK_ROOT/nginx/conf.d"
sed -e "s/{{SITE_SLUG}}/$SITE_SLUG/g" \
    -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{PHP_CONTAINER}}/$PHP_CONTAINER/g" \
    -e "s/{{PHP_PORT}}/$PHP_PORT/g" \
    "$STACK_ROOT/templates/nginx-vhost.conf.tpl" > "$VHOST_FILE"
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

# 9. Descomprimir Archivos y Normalizar Raíz Web
log_section "DESCOMPRIMIENDO ARCHIVOS DE WORDPRESS"
mkdir -p "$SITE_WEB_DIR"

log_step "Extrayendo $TAR_FILE en $SITE_WEB_DIR..."
if [[ "$TAR_FILE" =~ \.zip$ ]]; then
    unzip -q -o "$TAR_FILE" -d "$SITE_WEB_DIR"
elif [[ "$TAR_FILE" =~ \.tar\.gz$|\.tgz$ ]]; then
    tar -xzf "$TAR_FILE" -C "$SITE_WEB_DIR"
elif [[ "$TAR_FILE" =~ \.tar$ ]]; then
    tar -xf "$TAR_FILE" -C "$SITE_WEB_DIR"
else
    tar -xf "$TAR_FILE" -C "$SITE_WEB_DIR" 2>/dev/null || unzip -q -o "$TAR_FILE" -d "$SITE_WEB_DIR"
fi

# Detectar si WordPress quedó atrapado en un subdirectorio (ej: public_html/, wordpress/, etc.)
WP_ROOT_FILE=$(find "$SITE_WEB_DIR" -maxdepth 4 -type f -name "wp-login.php" 2>/dev/null | head -n 1 || true)
if [ -n "$WP_ROOT_FILE" ]; then
    WP_REAL_DIR=$(dirname "$WP_ROOT_FILE")
    if [ "$WP_REAL_DIR" != "$SITE_WEB_DIR" ]; then
        log_info "WordPress detectado dentro de subcarpeta: '$WP_REAL_DIR'"
        log_step "Moviendo archivos a la raíz web ($SITE_WEB_DIR)..."
        (
            shopt -s dotglob nullglob
            mv "$WP_REAL_DIR"/* "$SITE_WEB_DIR"/ 2>/dev/null || true
        )
        rmdir -p "$WP_REAL_DIR" 2>/dev/null || true
    fi
fi
log_ok "Archivos de WordPress ubicados correctamente en la raíz web."

# 10. Importar Base de Datos (.sql) Sanitizada
log_section "IMPORTANDO BASE DE DATOS (.SQL)"
log_step "Importando dump en la base de datos '${DB_NAME}'..."
if [[ "$SQL_FILE" =~ \.gz$ ]]; then
    zcat "$SQL_FILE" | sed -E '/^(CREATE DATABASE|USE[[:space:]]+)/Id' | docker exec -i mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl "$DB_NAME"
else
    sed -E '/^(CREATE DATABASE|USE[[:space:]]+)/Id' "$SQL_FILE" | docker exec -i mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl "$DB_NAME"
fi
log_ok "Base de Datos importada con éxito."

# 11. Conectar y Generar wp-config.php Estandarizado
log_section "CONECTANDO Y GENERANDO WP-CONFIG.PHP MAESTRO"

WP_CONFIG="$SITE_WEB_DIR/wp-config.php"

# Detectar prefijo de tablas real (desde MariaDB o wp-config original)
TABLE_PREFIX="wp_"
DB_DETECTED_PREFIX=$(docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -N -s -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '${DB_NAME}' AND table_name LIKE '%posts' AND table_name NOT LIKE '%postmeta' LIMIT 1;" 2>/dev/null | sed 's/posts$//' | tr -d '[:space:]' || true)

if [ -z "$DB_DETECTED_PREFIX" ]; then
    DB_DETECTED_PREFIX=$(docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -N -s -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '${DB_NAME}' AND table_name LIKE '%options' LIMIT 1;" 2>/dev/null | sed 's/options$//' | tr -d '[:space:]' || true)
fi

if [ -n "$DB_DETECTED_PREFIX" ]; then
    TABLE_PREFIX="$DB_DETECTED_PREFIX"
elif [ -f "$WP_CONFIG" ]; then
    FILE_PREFIX=$(grep -E "^\s*\\$table_prefix\s*=" "$WP_CONFIG" 2>/dev/null | head -n 1 | cut -d"'" -f2 | tr -d '[:space:]' || true)
    [ -n "$FILE_PREFIX" ] && TABLE_PREFIX="$FILE_PREFIX"
fi
log_info "Prefijo de tablas detectado: '$TABLE_PREFIX'"

# Respaldar wp-config.php original si existe
if [ -f "$WP_CONFIG" ]; then
    cp "$WP_CONFIG" "$WP_CONFIG.backup" 2>/dev/null || true
fi

# Generar Salts frescos y seguros
SALT_KEYS=$(curl -sSL https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || true)
if [ -z "$SALT_KEYS" ]; then
    SALT_KEYS="// Salts generados automáticamente por se2Code
define('AUTH_KEY',         '$(openssl rand -base64 32)');
define('SECURE_AUTH_KEY',  '$(openssl rand -base64 32)');
define('LOGGED_IN_KEY',    '$(openssl rand -base64 32)');
define('NONCE_KEY',        '$(openssl rand -base64 32)');
define('AUTH_SALT',        '$(openssl rand -base64 32)');
define('SECURE_AUTH_SALT', '$(openssl rand -base64 32)');
define('LOGGED_IN_SALT',   '$(openssl rand -base64 32)');
define('NONCE_SALT',       '$(openssl rand -base64 32)');"
fi

# Generar wp-config.php maestro impecable
cat << WPCONF > "$WP_CONFIG"
<?php
/**
 * Configuración maestra de WordPress generada por se2Code Stack
 */

define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASS}' );
define( 'DB_HOST', 'mariadb:3306' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

${SALT_KEYS}

// Detección de Proxy Reverso y Cloudflare HTTPS
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && 'https' === \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) {
    \$_SERVER['HTTPS'] = 'on';
}
if ( isset( \$_SERVER['HTTP_CF_VISITOR'] ) && false !== strpos( \$_SERVER['HTTP_CF_VISITOR'], 'https' ) ) {
    \$_SERVER['HTTPS'] = 'on';
}

\$table_prefix = '${TABLE_PREFIX}';

// Optimizaciones Maestras se2Code Stack (Previene redirecciones al viejo dominio)
define( 'WP_HOME', 'https://${DOMAIN}' );
define( 'WP_SITEURL', 'https://${DOMAIN}' );
define( 'FORCE_SSL_ADMIN', true );
define( 'DISALLOW_FILE_EDIT', true );
define( 'WP_MEMORY_LIMIT', '1024M' );
define( 'WP_MAX_MEMORY_LIMIT', '1024M' );
define( 'CONCATENATE_SCRIPTS', true );
define( 'DISABLE_WP_CRON', true );

// Redis Object Cache Scoped
define( 'WP_CACHE', true );
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PREFIX', '${SITE_SLUG}_' );
define( 'WP_REDIS_TIMEOUT', 1 );
define( 'WP_REDIS_READ_TIMEOUT', 1 );

// Nginx FastCGI Cache Helper
define( 'RT_WP_NGINX_HELPER_CACHE_PATH', '/var/cache/nginx' );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
WPCONF

log_ok "wp-config.php generado limpiamente y conectado a MariaDB (prefijo '${TABLE_PREFIX}')."

# 12. Purgar Drop-ins Incompatibles, Pre-instalar Plugins de Infraestructura y Desplegar se2Code Core
log_section "CONFIGURANDO PLUGINS DE INFRAESTRUCTURA Y BLINDAJE SE2CODE"
rm -f "$SITE_WEB_DIR/wp-content/advanced-cache.php"
rm -f "$SITE_WEB_DIR/wp-content/wp-cache-config.php"
rm -f "$SITE_WEB_DIR/wp-content/db.php"
rm -rf "$SITE_WEB_DIR/wp-content/cache" 2>/dev/null || true

mkdir -p "$SITE_WEB_DIR/wp-content/plugins"
if [ ! -d "$SITE_WEB_DIR/wp-content/plugins/redis-cache" ]; then
    log_info "Pre-instalando plugin obligatorio redis-cache..."
    curl -sSL https://downloads.wordpress.org/plugin/redis-cache.latest-stable.zip -o /tmp/redis-cache.zip 2>/dev/null && \
    unzip -q -o /tmp/redis-cache.zip -d "$SITE_WEB_DIR/wp-content/plugins/" 2>/dev/null && \
    rm -f /tmp/redis-cache.zip || true
fi

# Configurar drop-in de Redis
if [ -f "$SITE_WEB_DIR/wp-content/plugins/redis-cache/includes/object-cache.php" ]; then
    cp "$SITE_WEB_DIR/wp-content/plugins/redis-cache/includes/object-cache.php" "$SITE_WEB_DIR/wp-content/object-cache.php" 2>/dev/null || true
fi

if [ ! -d "$SITE_WEB_DIR/wp-content/plugins/nginx-helper" ]; then
    log_info "Pre-instalando plugin obligatorio nginx-helper..."
    curl -sSL https://downloads.wordpress.org/plugin/nginx-helper.latest-stable.zip -o /tmp/nginx-helper.zip 2>/dev/null && \
    unzip -q -o /tmp/nginx-helper.zip -d "$SITE_WEB_DIR/wp-content/plugins/" 2>/dev/null && \
    rm -f /tmp/nginx-helper.zip || true
fi

mkdir -p "$SITE_WEB_DIR/wp-content/mu-plugins"
SE2CODE_TPL="$STACK_ROOT/modules/wordpress/templates/se2code-core.php.tpl"
[ ! -f "$SE2CODE_TPL" ] && SE2CODE_TPL="$STACK_ROOT/templates/se2code-core.php.tpl"
cp "$SE2CODE_TPL" "$SITE_WEB_DIR/wp-content/mu-plugins/se2code-core.php" 2>/dev/null || true
chmod 644 "$SITE_WEB_DIR/wp-content/mu-plugins/se2code-core.php" 2>/dev/null || true
rm -f "$SITE_WEB_DIR/wp-content/mu-plugins/wp-staging-optimizer.php" 2>/dev/null || true
log_ok "Plugins de infraestructura y se2code-core.php listos en el sitio."

# 13. Permisos del Sistema de Archivos y Activación de Servicios
log_section "AJUSTANDO PERMISOS Y ACTIVANDO SERVICIOS"
log_step "Asignando propiedad de archivos a www-data (33:33)..."
chown -R 33:33 "$SITE_WEB_DIR" 2>/dev/null || true
find "$SITE_WEB_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
find "$SITE_WEB_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true
chmod 600 "$WP_CONFIG" 2>/dev/null || true

log_step "Recargando NGINX y reiniciando $PHP_CONTAINER..."
docker exec "$PHP_CONTAINER" chown -R www-data:www-data /var/log/php 2>/dev/null || true
docker restart "$PHP_CONTAINER" >/dev/null 2>&1 || true
docker exec wp-nginx nginx -t >/dev/null 2>&1 && docker exec wp-nginx nginx -s reload 2>/dev/null || docker restart wp-nginx >/dev/null 2>&1 || true
log_ok "NGINX recargado y motor PHP activado con el nuevo pool."

if [ "${NEED_ACME:-false}" = true ]; then
    log_section "EMISIÓN AUTOMÁTICA DE CERTIFICADO LET'S ENCRYPT (ACME.SH)"
    if [ ! -f /root/.acme.sh/acme.sh ]; then
        log_step "Instalando cliente ACME (acme.sh)..."
        curl -sSL https://get.acme.sh | sh -s email="admin@${DOMAIN}" >/dev/null 2>&1 || true
        ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh 2>/dev/null || true
    fi

    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
    mkdir -p "$SITE_WEB_DIR/.well-known/acme-challenge"
    chown -R 33:33 "$SITE_WEB_DIR/.well-known" 2>/dev/null || true
    chmod -R 755 "$SITE_WEB_DIR/.well-known" 2>/dev/null || true

    log_step "Solicitando certificado Let's Encrypt para '$DOMAIN' vía reto HTTP..."
    if /root/.acme.sh/acme.sh --issue -d "$DOMAIN" -w "$SITE_WEB_DIR" --server letsencrypt; then
        log_step "Instalando certificado en NGINX..."
        /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
            --key-file "$CERTS_DIR/privkey.pem" \
            --fullchain-file "$CERTS_DIR/fullchain.pem" \
            --reloadcmd "docker exec wp-nginx nginx -s reload" >/dev/null 2>&1 || true
        cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
        chmod 600 "$CERTS_DIR/privkey.pem"
        chmod 644 "$CERTS_DIR"/*.pem
        docker exec wp-nginx nginx -s reload 2>/dev/null || true
        log_ok "¡Certificado Let's Encrypt emitido e instalado con éxito para $DOMAIN!"
    else
        log_warn "No se pudo validar el reto HTTP de Let's Encrypt para $DOMAIN."
        log_warn "Se mantuvo el certificado autofirmado para garantizar operatividad inmediata."
        log_warn "Podrás reintentar emitir Let's Encrypt más tarde desde 'se2code -> Opción 7'."
    fi
fi

# Desactivación preventiva de plugins de ofuscación de login o URLs que rompen migraciones
for sec_plug in "hide-my-wp" "wps-hide-login" "wp-hide-security-enhancer" "rename-wp-login" "lockdown-wp-admin"; do
    if docker exec --user 33:33 "$PHP_CONTAINER" wp plugin is-installed "$sec_plug" --path="$CONTAINER_PATH" >/dev/null 2>&1; then
        if docker exec --user 33:33 "$PHP_CONTAINER" wp plugin is-active "$sec_plug" --path="$CONTAINER_PATH" >/dev/null 2>&1; then
            log_warn "Plugin de ofuscación de login detectado: '$sec_plug'. Desactivando preventivamente para evitar bloqueos del panel y assets rotos..."
            docker exec --user 33:33 "$PHP_CONTAINER" wp plugin deactivate "$sec_plug" --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
        fi
    fi
done

# 14. Cambio de Dominio / Staging (Reemplazo Canónico Multivariante)
log_section "CAMBIO DE DOMINIO / STAGING (REEMPLAZO CANÓNICO MULTIVARIANTE)"

echo -e "¿Deseas ejecutar un reemplazo canónico de URLs en la base de datos (${C_YELLOW}wp search-replace${C_RESET})?"
echo -e "  ${C_DIM}(Sustituye automáticamente las 4 variantes: https/http y con/sin www hacia una sola URL destino)${C_RESET}"
read -r -p "¿Ejecutar reemplazo canónico de dominio? [S/n]: " DO_REPLACE
DO_REPLACE=${DO_REPLACE:-S}

if [[ "$DO_REPLACE" =~ ^[Ss]$ ]]; then
    # Detectar el dominio previo: Primero vía WP-CLI, y como fallback directo en MariaDB
    OLD_SITEURL=$(docker exec --user 33:33 "$PHP_CONTAINER" wp option get siteurl --path="$CONTAINER_PATH" 2>/dev/null | tr -d '[:space:]' || true)
    if [ -z "$OLD_SITEURL" ]; then
        OLD_SITEURL=$(docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -N -s -e "SELECT option_value FROM \`${DB_NAME}\`.${TABLE_PREFIX}options WHERE option_name IN ('siteurl', 'home') AND option_value != '' LIMIT 1;" 2>/dev/null | tr -d '[:space:]' || true)
    fi
    
    echo -e "\nDominio previo detectado en la BD: ${C_YELLOW}${OLD_SITEURL:-'No detectado'}${C_RESET}"
    read -r -p "Escribe el dominio viejo a buscar [ej: ${OLD_SITEURL:-https://viejo-dominio.com}]: " SEARCH_URL
    SEARCH_URL=${SEARCH_URL:-$OLD_SITEURL}
    
    DEST_DEFAULT="https://${DOMAIN}"
    echo -e "\nURL canónica final de destino (${C_BOLD}la ÚNICA URL que reemplazará a todas las variantes${C_RESET}):"
    read -r -p "Escribe la URL nueva [por defecto: $DEST_DEFAULT]: " REPLACE_URL
    REPLACE_URL=${REPLACE_URL:-$DEST_DEFAULT}

    if [ -n "$SEARCH_URL" ] && [ -n "$REPLACE_URL" ]; then
        # Normalizar cadenas
        CLEAN_SEARCH=$(echo "$SEARCH_URL" | sed -e 's|^https\?://||' -e 's|/*$||')
        ROOT_SEARCH=$(echo "$CLEAN_SEARCH" | sed 's|^www\.||')

        CANONICAL_DEST=$(echo "$REPLACE_URL" | sed -e 's|/*$||')
        if [[ ! "$CANONICAL_DEST" =~ ^https?:// ]]; then
            CANONICAL_DEST="https://${CANONICAL_DEST}"
        fi
        CLEAN_DEST_NO_PROTO=$(echo "$CANONICAL_DEST" | sed -e 's|^https\?://||')

        # Matriz de 4 variantes en orden de mayor longitud (www primero para evitar prefijos huérfanos)
        SEARCH_VARIANTS=(
            "https://www.${ROOT_SEARCH}"
            "http://www.${ROOT_SEARCH}"
            "https://${ROOT_SEARCH}"
            "http://${ROOT_SEARCH}"
        )
        REL_VARIANTS=(
            "//www.${ROOT_SEARCH}"
            "//${ROOT_SEARCH}"
        )

        log_step "Ejecutando matriz de reemplazo canónico hacia '$CANONICAL_DEST'..."
        for v in "${SEARCH_VARIANTS[@]}"; do
            if [ "$v" != "$CANONICAL_DEST" ]; then
                log_info "Reemplazando en BD: '$v' ➔ '$CANONICAL_DEST'..."
                docker exec --user 33:33 "$PHP_CONTAINER" wp search-replace "$v" "$CANONICAL_DEST" \
                    --all-tables --precise --skip-columns=guid --path="$CONTAINER_PATH" || true
            fi
        done

        # Reemplazar URLs de protocolo relativo
        for rv in "${REL_VARIANTS[@]}"; do
            if [ "$rv" != "//$CLEAN_DEST_NO_PROTO" ]; then
                docker exec -i --user 33:33 "$PHP_CONTAINER" wp search-replace "$rv" "//$CLEAN_DEST_NO_PROTO" \
                    --all-tables --precise --skip-columns=guid --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
            fi
        done

        # Sincronizar Elementor si está activo
        if docker exec --user 33:33 "$PHP_CONTAINER" wp plugin is-active elementor --path="$CONTAINER_PATH" >/dev/null 2>&1; then
            log_step "Sincronizando biblioteca de Elementor..."
            for v in "${SEARCH_VARIANTS[@]}"; do
                if [ "$v" != "$CANONICAL_DEST" ]; then
                    docker exec -i --user 33:33 "$PHP_CONTAINER" wp elementor replace-urls "$v" "$CANONICAL_DEST" --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
                fi
            done
            docker exec -i --user 33:33 "$PHP_CONTAINER" wp elementor flush_css --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
        fi

        docker exec -i --user 33:33 "$PHP_CONTAINER" wp rewrite flush --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
        docker exec -i --user 33:33 "$PHP_CONTAINER" wp cache flush --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
        docker exec -i redis redis-cli FLUSHALL >/dev/null 2>&1 || true
        log_ok "Matriz de reemplazo completada y estilos regenerados con éxito hacia '$CANONICAL_DEST'."
    else
        log_info "No hubo cambios de URL."
    fi
fi

# 15. Paso Final: Optimización y Limpieza de Caché
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
