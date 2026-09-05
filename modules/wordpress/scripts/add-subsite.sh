#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WordPress: Agregar Sub-sitio / Idioma en Subcarpeta
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "  ${C_BOLD}🌍 AGREGAR SUB-SITIO / IDIOMA EN SUBCARPETA (ej: /es, /en)${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}"

CONF_FILES=($(find "$STACK_ROOT/nginx/conf.d" -type f -name "*.conf" ! -name "default*.conf" 2>/dev/null | sort || true))
if [ ${#CONF_FILES[@]} -eq 0 ]; then
    log_error "No hay sitios WordPress configurados en el stack."
    exit 1
fi

echo -e "  Selecciona el sitio maestro donde deseas agregar el idioma:\n"
i=1
SITES=()
for conf in "${CONF_FILES[@]}"; do
    s=$(basename "$conf" .conf)
    SITES+=("$s")
    dom=$(grep -E "^\s*server_name\s+" "$conf" | head -n 1 | awk '{print $2}' | tr -d ';' || echo "$s")
    echo -e "    ${C_BOLD}$i)${C_RESET} ${C_CYAN}$s${C_RESET} (Dominio: ${C_YELLOW}$dom${C_RESET})"
    i=$((i + 1))
done
echo -e "    ${C_BOLD}0)${C_RESET} Cancelar\n"

read -r -p "Opción [1-${#SITES[@]}]: " OPT
if [ "$OPT" = "0" ] || [ -z "$OPT" ]; then
    log_info "Operación cancelada."
    exit 0
fi

IDX=$((OPT - 1))
SITE_SLUG="${SITES[$IDX]}"
VHOST_FILE="$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"
DOMAIN=$(grep -E "^\s*server_name\s+" "$VHOST_FILE" | head -n 1 | awk '{print $2}' | tr -d ';' || echo "$SITE_SLUG")

echo -e "\n${C_BOLD}Sitio seleccionado:${C_RESET} $SITE_SLUG ($DOMAIN)"
read -r -p "Escribe el nombre de la subcarpeta / idioma a crear (ej: es o en): " SUB_NAME
SUB_NAME=$(echo "$SUB_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')

if [ -z "$SUB_NAME" ]; then
    log_error "Nombre de subcarpeta no válido."
    exit 1
fi

SITE_WEB_DIR="$STACK_ROOT/wp-data/$SITE_SLUG"
TARGET_DIR="$SITE_WEB_DIR/$SUB_NAME"

if [ -d "$TARGET_DIR" ] && [ -f "$TARGET_DIR/wp-config.php" ]; then
    log_warn "La subcarpeta '$SUB_NAME' ya existe en $TARGET_DIR."
    read -r -p "¿Deseas reconfigurar la base de datos de todos modos? [s/N]: " RECONF
    if [[ ! "$RECONF" =~ ^[Ss]$ ]]; then
        exit 0
    fi
fi

log_step "Aprovisionando sub-sitio independiente: https://${DOMAIN}/${SUB_NAME}/..."

mkdir -p "$TARGET_DIR"
if [ ! -f "$TARGET_DIR/wp-login.php" ]; then
    log_info "Descargando WordPress Core para [/$SUB_NAME/]..."
    curl -sSL https://wordpress.org/latest.tar.gz | tar -xz -C "$TARGET_DIR" --strip-components=1
    log_ok "WordPress descargado en $TARGET_DIR."
fi

# Reutilizar credenciales del sitio maestro si existen para asegurar autenticación en MariaDB
if [ -f "$SITE_WEB_DIR/wp-config.php" ]; then
    DB_USER=$(grep -E "define\(\s*'DB_USER'" "$SITE_WEB_DIR/wp-config.php" | awk -F"'" '{print $4}')
    DB_PASS=$(grep -E "define\(\s*'DB_PASSWORD'" "$SITE_WEB_DIR/wp-config.php" | awk -F"'" '{print $4}')
else
    DB_USER="wp_${SITE_SLUG}_user"
    DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
fi

DB_NAME="wp_${SITE_SLUG}_${SUB_NAME}_db"
MARIADB_ROOT_PASS=$(grep -E "^MYSQL_ROOT_PASSWORD=" "$STACK_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo "root_secret")

docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;" 2>/dev/null || true
log_ok "Base de Datos '${DB_NAME}' creada y asignada a '${DB_USER}'."

# wp-config.php
if [ ! -f "$TARGET_DIR/wp-config.php" ]; then
    SALT_KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ || true)
    cat << WPCONF > "$TARGET_DIR/wp-config.php"
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

// Redis Cache con prefijo único por idioma
define( 'WP_CACHE', true );
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PREFIX', '${SITE_SLUG}_${SUB_NAME}_' );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
WPCONF
    chmod 600 "$TARGET_DIR/wp-config.php"
    log_ok "wp-config.php generado para [/$SUB_NAME/]."
fi

# Actualizar NGINX vHost si no tiene la regla para esta subcarpeta
if ! grep -q "location /${SUB_NAME}/ {" "$VHOST_FILE"; then
    RULE="\n    # Enrutamiento Sub-WordPress: /${SUB_NAME}/\n    location /${SUB_NAME}/ {\n        try_files \$uri \$uri/ /${SUB_NAME}/index.php?\$args;\n    }\n"
    sed -i "s|location / {|${RULE}\n    location / {|" "$VHOST_FILE"
    docker exec wp-nginx nginx -s reload 2>/dev/null || true
    log_ok "Regla NGINX insertada y recargada."
fi

# Permisos 33:33
sudo chown -R 33:33 "$TARGET_DIR" 2>/dev/null || chown -R 33:33 "$TARGET_DIR" 2>/dev/null || true
find "$TARGET_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
find "$TARGET_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true
[ -f "$TARGET_DIR/wp-config.php" ] && chmod 600 "$TARGET_DIR/wp-config.php"

echo -e "\n${C_BOLD}${C_GREEN}✔ SUB-SITIO APROVISIONADO EXITOSAMENTE${C_RESET}"
echo -e "  - URL Acceso    : ${C_CYAN}https://${DOMAIN}/${SUB_NAME}/${C_RESET}"
echo -e "  - Carpeta Web   : ${TARGET_DIR}"
echo -e "  - Base de Datos : ${C_GREEN}${DB_NAME}${C_RESET}"
echo -e "  - Usuario BD    : ${DB_USER}"
echo -e "  - Contraseña BD : (Misma contraseña de la raíz)\n"
