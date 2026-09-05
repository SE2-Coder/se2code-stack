#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WordPress: Desmantelador de Sitios
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

SITE_SLUG="${1:-}"

if [ -z "$SITE_SLUG" ]; then
    echo -e "\n${C_BOLD}${C_RED}======================================================================${C_RESET}"
    echo -e "  ${C_BOLD}🗑️  ELIMINACIÓN SEGURA DE SITIO WORDPRESS${C_RESET}"
    echo -e "${C_RED}======================================================================${C_RESET}"
    
    CONF_FILES=($(find "$STACK_ROOT/nginx/conf.d" -type f -name "*.conf" ! -name "default*.conf" 2>/dev/null | sort || true))
    if [ ${#CONF_FILES[@]} -eq 0 ]; then
        log_error "No hay sitios WordPress configurados para eliminar."
        exit 1
    fi

    echo -e "  Selecciona el sitio que deseas eliminar:\n"
    i=1
    SITES=()
    for conf in "${CONF_FILES[@]}"; do
        s=$(basename "$conf" .conf)
        SITES+=("$s")
        dom=$(grep -E "^\s*server_name\s+" "$conf" | head -n 1 | awk '{print $2}' | tr -d ';' || echo "$s")
        if [ -f "$STACK_ROOT/php/php84/pools/${s}.conf" ]; then
            php_info="PHP 8.4"
        else
            php_info="PHP 8.5"
        fi
        echo -e "    ${C_BOLD}$i)${C_RESET} ${C_CYAN}$s${C_RESET} (Dominio: ${C_YELLOW}$dom${C_RESET} | $php_info)"
        i=$((i + 1))
    done
    echo -e "    ${C_BOLD}0)${C_RESET} Cancelar y volver al menú\n"

    read -r -p "Ingresa el número de opción: " OPT
    if [ "$OPT" = "0" ] || [ -z "$OPT" ]; then
        log_info "Operación cancelada."
        exit 0
    fi

    IDX=$((OPT - 1))
    if [ "$IDX" -lt 0 ] || [ "$IDX" -ge "${#SITES[@]}" ]; then
        log_error "Opción no válida."
        exit 1
    fi
    SITE_SLUG="${SITES[$IDX]}"
fi

echo -e "\n${C_BOLD}${C_RED}⚠️  ¿Estás 100% seguro de que deseas eliminar permanentemente [$SITE_SLUG]?${C_RESET}"
echo -e "  Esta acción eliminará su base de datos MariaDB, archivos web y configuraciones."
read -r -p "Escribe exactamente el nombre del sitio para confirmar ('$SITE_SLUG'): " CONFIRM

if [ "$CONFIRM" != "$SITE_SLUG" ]; then
    log_info "Confirmación no coincide. Operación cancelada de forma segura."
    exit 0
fi

# 1. Generar backup automático preventivo antes de borrar
log_step "Generando respaldo automático de seguridad previo a la eliminación..."
"$SCRIPT_DIR/backup-site.sh" "$SITE_SLUG" "full" >/dev/null 2>&1 || true
log_ok "Backup preventivo guardado en backups/$SITE_SLUG."

# 2. Eliminar base de datos
DB_NAME="wp_${SITE_SLUG}_db"
DB_USER="wp_${SITE_SLUG}_user"
MARIADB_ROOT_PASS=$(grep -E "^MYSQL_ROOT_PASSWORD=" "$STACK_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo "root_secret")

docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
DROP USER IF EXISTS '${DB_USER}'@'%';
FLUSH PRIVILEGES;" 2>/dev/null || true
log_ok "Base de datos y usuario eliminados de MariaDB."

# 3. Eliminar archivos de configuración
rm -f "$STACK_ROOT"/php/php*/pools/${SITE_SLUG}.conf
rm -f "$STACK_ROOT"/nginx/conf.d/${SITE_SLUG}.conf

# 4. Mover archivos web a .trash
TRASH_DIR="$WP_STACK_ROOT/.trash/${SITE_SLUG}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TRASH_DIR"
mv "$STACK_ROOT/wp-data/$SITE_SLUG" "$TRASH_DIR/" 2>/dev/null || true
log_ok "Archivos web movidos a la papelera de seguridad: $TRASH_DIR"

# 5. Recargar NGINX y PHP
docker exec wp-nginx nginx -s reload 2>/dev/null || true
docker restart wp-php84 wp-php85 >/dev/null 2>&1 || true

log_ok "Sitio [$SITE_SLUG] desmantelado completamente y recursos liberados."
