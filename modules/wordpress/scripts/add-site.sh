#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WordPress: Aprovisionador de Sitios (Estándar o Multilenguaje)
# Arquitectura 100% Aislada (Zero-Trust): Base de datos y usuario propios por instancia
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

# Cargar utilidades
[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

SITE_SLUG="${1:-}"
DOMAIN="${2:-}"
PHP_VERSION="${3:-}"

# Modo interactivo
if [ -z "$SITE_SLUG" ]; then
    echo -e "${C_BOLD}${C_CYAN}--- Aprovisionamiento de Sitio WordPress ---${C_RESET}"
    read -r -p "Identificador / Slug del sitio (ej: misterloans): " SITE_SLUG
fi

if [ -z "$DOMAIN" ]; then
    read -r -p "Dominio principal (ej: dev.mister.loans): " DOMAIN
fi

if [ -z "$PHP_VERSION" ]; then
    echo -e "Selecciona la versión de PHP:"
    echo -e "  1) PHP 8.5 (Última generación - Recomendada)"
    echo -e "  2) PHP 8.4 (Estable)"
    read -r -p "Opción [1-2, por defecto 1]: " PHP_OPT
    PHP_OPT=${PHP_OPT:-1}
    if [ "$PHP_OPT" = "2" ]; then
        PHP_VERSION="8.4"
    else
        PHP_VERSION="8.5"
    fi
fi

# Sanitizar
SITE_SLUG=$(echo "$SITE_SLUG" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')
DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-')

# Preguntar por la Arquitectura (Estándar vs Multilenguaje / Subdirectorios)
echo -e "\n${C_BOLD}[?] Selecciona el Tipo de Arquitectura para este Sitio:${C_RESET}"
echo -e "    1) 🌐 Estándar (1 solo WordPress en la raíz /)"
echo -e "    2) 🌍 Multilenguaje / Multi-Directorio (Home en raíz + subcarpetas independientes, ej: /es, /en)"
read -r -p "Opción [1-2, por defecto 1]: " ARCH_CHOICE
ARCH_CHOICE=${ARCH_CHOICE:-1}

SUB_LANGS=()
if [ "$ARCH_CHOICE" = "2" ]; then
    echo -e "\n${C_CYAN}Escribe los códigos de idioma o subcarpetas separados por espacio [ej: es en]:${C_RESET}"
    read -r -p "Subcarpetas [por defecto: es en]: " LANGS_INPUT
    LANGS_INPUT=${LANGS_INPUT:-"es en"}
    for l in $LANGS_INPUT; do
        clean_lang=$(echo "$l" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')
        [ -n "$clean_lang" ] && SUB_LANGS+=("$clean_lang")
    done
    log_ok "Arquitectura configurada: Home (/) + ${#SUB_LANGS[@]} instancias (${SUB_LANGS[*]})."
fi

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
read -r -p "Opción [1-2, por defecto 1]: " SSL_CHOICE
SSL_CHOICE=${SSL_CHOICE:-1}

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

# 4. Generar Virtual Host NGINX con bloques de subdirectorios
VHOST_FILE="$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"
sed -e "s/{{SITE_SLUG}}/$SITE_SLUG/g" \
    -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{PHP_CONTAINER}}/$PHP_CONTAINER/g" \
    -e "s/{{PHP_PORT}}/$PHP_PORT/g" \
    "$STACK_ROOT/templates/nginx-vhost.conf.tpl" > "$VHOST_FILE"

# Si es multilenguaje, insertar bloques location de subcarpetas antes de 'location /'
if [ ${#SUB_LANGS[@]} -gt 0 ]; then
    SUB_RULES=""
    for lang in "${SUB_LANGS[@]}"; do
        SUB_RULES="${SUB_RULES}\n    # Enrutamiento Sub-WordPress: /${lang}/\n    location /${lang}/ {\n        try_files \$uri \$uri/ /${lang}/index.php?\$args;\n    }\n"
    done
    sed -i "s|location / {|${SUB_RULES}\n    location / {|" "$VHOST_FILE"
    log_ok "Reglas de enrutamiento NGINX añadidas para: ${SUB_LANGS[*]}"
fi
log_ok "Virtual Host NGINX activo en $VHOST_FILE"

MARIADB_ROOT_PASS=$(grep -E "^MYSQL_ROOT_PASSWORD=" "$STACK_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo "root_secret")

# Función auxiliar para crear y configurar una instancia de WordPress con usuario 100% aislado
setup_wp_instance() {
    local INSTANCE_DIR="$1"
    local INSTANCE_NAME="$2"
    local DB_SUFFIX="$3"
    local REDIS_SUBPREFIX="$4"
    local URL_PATH="$5"

    mkdir -p "$INSTANCE_DIR"
    if [ ! -f "$INSTANCE_DIR/wp-login.php" ]; then
        log_info "Descargando WordPress Core para [$INSTANCE_NAME]..."
        curl -sSL https://wordpress.org/latest.tar.gz | tar -xz -C "$INSTANCE_DIR" --strip-components=1
        log_ok "WordPress descargado en $INSTANCE_DIR."
    fi

    # Base de datos y usuario dedicados e independientes (Zero Trust)
    local DB_NAME="wp_${SITE_SLUG}_${DB_SUFFIX}"
    local DB_USER="wp_${SITE_SLUG}_${DB_SUFFIX}_user"
    local DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

    docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "
    CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
    GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
    FLUSH PRIVILEGES;" 2>/dev/null || true
    log_ok "Base de Datos '${DB_NAME}' y usuario aislado '${DB_USER}' creados."

    # wp-config.php
    if [ ! -f "$INSTANCE_DIR/wp-config.php" ]; then
        local SALT_KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ || true)
        cat << WPCONF > "$INSTANCE_DIR/wp-config.php"
<?php
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASS}' );
define( 'DB_HOST', 'mariadb:3306' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', 'utf8mb4_unicode_ci' );

${SALT_KEYS}

// Detección de Proxy Reverso y Cloudflare HTTPS
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && 'https' === \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) {
    \$_SERVER['HTTPS'] = 'on';
}
if ( isset( \$_SERVER['HTTP_CF_VISITOR'] ) && false !== strpos( \$_SERVER['HTTP_CF_VISITOR'], 'https' ) ) {
    \$_SERVER['HTTPS'] = 'on';
}

\$table_prefix = 'wp_';

// Optimizaciones Maestras se2Code Stack
define( 'FORCE_SSL_ADMIN', true );
define( 'DISALLOW_FILE_EDIT', true );
define( 'WP_MEMORY_LIMIT', '1024M' );
define( 'WP_MAX_MEMORY_LIMIT', '1024M' );
define( 'CONCATENATE_SCRIPTS', true );
define( 'DISABLE_WP_CRON', true );

// Redis Cache Scoped
define( 'WP_CACHE', true );
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PREFIX', '${REDIS_SUBPREFIX}' );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
WPCONF
        chmod 600 "$INSTANCE_DIR/wp-config.php"

    # Acelerador de Rendimiento se2Code (IPv4 cURL + Elementor Booster)
    mkdir -p "$INSTANCE_DIR/wp-content/mu-plugins"
    cp "$STACK_ROOT/templates/se2code-core.php.tpl" "$INSTANCE_DIR/wp-content/mu-plugins/se2code-core.php"
    chmod 644 "$INSTANCE_DIR/wp-content/mu-plugins/se2code-core.php" 
        log_ok "wp-config.php generado con credenciales aisladas para [$INSTANCE_NAME]."
    fi

    # Pre-instalar plugins de infraestructura obligatorios (Redis Cache y Nginx Helper)
    mkdir -p "$INSTANCE_DIR/wp-content/plugins"
    if [ ! -d "$INSTANCE_DIR/wp-content/plugins/redis-cache" ]; then
        log_info "Pre-instalando plugin obligatorio redis-cache..."
        curl -sSL https://downloads.wordpress.org/plugin/redis-cache.latest-stable.zip -o /tmp/redis-cache.zip 2>/dev/null && \
        unzip -q -o /tmp/redis-cache.zip -d "$INSTANCE_DIR/wp-content/plugins/" 2>/dev/null && \
        rm -f /tmp/redis-cache.zip || true
        [ -f "$INSTANCE_DIR/wp-content/plugins/redis-cache/includes/object-cache.php" ] && \
        cp "$INSTANCE_DIR/wp-content/plugins/redis-cache/includes/object-cache.php" "$INSTANCE_DIR/wp-content/object-cache.php" 2>/dev/null || true
    fi

    if [ ! -d "$INSTANCE_DIR/wp-content/plugins/nginx-helper" ]; then
        log_info "Pre-instalando plugin obligatorio nginx-helper..."
        curl -sSL https://downloads.wordpress.org/plugin/nginx-helper.latest-stable.zip -o /tmp/nginx-helper.zip 2>/dev/null && \
        unzip -q -o /tmp/nginx-helper.zip -d "$INSTANCE_DIR/wp-content/plugins/" 2>/dev/null && \
        rm -f /tmp/nginx-helper.zip || true
    fi

    # Registrar datos de salida
    SUMMARY_DATA+=("Instancia: [$INSTANCE_NAME] -> URL: https://${DOMAIN}${URL_PATH} | BD: ${DB_NAME} | User: ${DB_USER} | Pass: ${DB_PASS}")
}

SUMMARY_DATA=()
SITE_WEB_DIR="$STACK_ROOT/wp-data/$SITE_SLUG"

# 5. Instalar WordPress Home (Raíz)
log_step "Configurando WordPress Principal (Home)..."
setup_wp_instance "$SITE_WEB_DIR" "Home / Principal" "db" "${SITE_SLUG}_" ""

# 6. Instalar Subcarpetas de Idiomas si aplica
if [ ${#SUB_LANGS[@]} -gt 0 ]; then
    for lang in "${SUB_LANGS[@]}"; do
        log_step "Configurando instancia independiente para idioma [/$lang/]..."
        setup_wp_instance "$SITE_WEB_DIR/$lang" "Idioma /$lang/" "${lang}_db" "${SITE_SLUG}_${lang}_" "/$lang/"
    done
fi

# 7. Permisos de Archivos 33:33 (www-data)
sudo chown -R 33:33 "$SITE_WEB_DIR" 2>/dev/null || chown -R 33:33 "$SITE_WEB_DIR" 2>/dev/null || true
find "$SITE_WEB_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
find "$SITE_WEB_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true
find "$SITE_WEB_DIR" -type f -name "wp-config.php" -exec chmod 600 {} + 2>/dev/null || true

# 8. Recargar NGINX y Reiniciar PHP
docker exec "$PHP_CONTAINER" chown -R www-data:www-data /var/log/php 2>/dev/null || true
docker exec wp-nginx nginx -s reload 2>/dev/null || true
docker restart "$PHP_CONTAINER" >/dev/null 2>&1 || true

# 9. Resumen Final
echo -e "\n${C_BOLD}${C_GREEN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}         ¡SITIO APROVISIONADO EXITOSAMENTE CON SE2CODE!               ${C_RESET}"
echo -e "${C_GREEN}======================================================================${C_RESET}\n"
echo -e "  - Dominio Maestro : https://${DOMAIN}"
echo -e "  - Directorio Web  : ${SITE_WEB_DIR}"
echo -e "  - Motor PHP       : ${PHP_CONTAINER} (Puerto TCP ${PHP_PORT})"
echo -e "  - Arquitectura    : $([ ${#SUB_LANGS[@]} -gt 0 ] && echo "Multilenguaje / Multi-Directorio (${SUB_LANGS[*]})" || echo "Estándar")\n"

echo -e "${C_BOLD}${C_CYAN}Instancias y Bases de Datos Aisladas (Zero-Trust):${C_RESET}"
for item in "${SUMMARY_DATA[@]}"; do
    echo -e "  » ${item}"
done
echo ""

echo -e "${C_BOLD}${C_YELLOW}⚡ ARQUITECTURA DE CACHÉ SE2CODE (REGLA FUNDAMENTAL):${C_RESET}"
echo -e "  ${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e "  ✔ ${C_GREEN}Nginx FastCGI Cache${C_RESET} preconfigurado a nivel de servidor (RAM/Disco)."
echo -e "  ✔ ${C_GREEN}Redis Object Cache${C_RESET} preconfigurado en memoria RAM (Consultas MySQL)."
echo -e "  ✔ ${C_GREEN}Nginx Helper & Redis Cache${C_RESET} pre-instalados con opciones óptimas."
echo -e ""
echo -e "  ${C_BOLD}${C_RED}⚠️  ¡NO INSTALES NINGÚN PLUGIN DE CACHÉ ADICIONAL!${C_RESET}"
echo -e "  Plugins como ${C_YELLOW}WP Rocket, LiteSpeed Cache, W3 Total Cache, WP Super Cache${C_RESET}"
echo -e "  o ${C_YELLOW}WP Fastest Cache${C_RESET} son innecesarios y ${C_RED}degradan el rendimiento${C_RESET}."
echo -e ""
echo -e "  Si acabas de ${C_BOLD}migrar${C_RESET} este sitio desde otro servidor, ejecuta en cualquier momento:"
echo -e "  👉 ${C_CYAN}se2code${C_RESET} -> Opción 9 (${C_YELLOW}Optimizar Sitio / Post-Migración${C_RESET})"
echo -e "  para desactivar automáticamente los plugins de caché del proveedor anterior."
echo -e "  ${C_CYAN}----------------------------------------------------------------------${C_RESET}\n"
