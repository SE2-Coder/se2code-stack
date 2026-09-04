#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WordPress: Conmutador Rápido de Versión PHP
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

SITE_SLUG="${1:-}"

if [ -z "$SITE_SLUG" ]; then
    echo -e "\n${C_BOLD}${C_CYAN}--- Conmutador de Versión PHP ---${C_RESET}"
    SITES=($(ls -1 "$STACK_ROOT"/php/php*/pools/*.conf 2>/dev/null | xargs -n 1 basename | sed 's/\.conf$//' | grep -v "placeholder" || true))
    if [ ${#SITES[@]} -eq 0 ]; then
        log_error "No hay sitios activos."
        exit 1
    fi

    i=1
    for s in "${SITES[@]}"; do
        if [ -f "$STACK_ROOT/php/php84/pools/${s}.conf" ]; then
            CURR="PHP 8.4"
        else
            CURR="PHP 8.5"
        fi
        echo "  $i) $s ($CURR)"
        i=$((i + 1))
    done
    read -r -p "Selecciona el sitio a cambiar: " OPT
    IDX=$((OPT - 1))
    SITE_SLUG="${SITES[$IDX]}"
fi

# Detectar versión actual
if [ -f "$STACK_ROOT/php/php84/pools/${SITE_SLUG}.conf" ]; then
    CURRENT_VER="8.4"
    TARGET_VER="8.5"
    FROM_DIR="$STACK_ROOT/php/php84/pools"
    TO_DIR="$STACK_ROOT/php/php85/pools"
    FROM_CONT="wp-php84"
    TO_CONT="wp-php85"
elif [ -f "$STACK_ROOT/php/php85/pools/${SITE_SLUG}.conf" ]; then
    CURRENT_VER="8.5"
    TARGET_VER="8.4"
    FROM_DIR="$STACK_ROOT/php/php85/pools"
    TO_DIR="$STACK_ROOT/php/php84/pools"
    FROM_CONT="wp-php85"
    TO_CONT="wp-php84"
else
    log_error "El sitio '$SITE_SLUG' no se encuentra configurado."
    exit 1
fi

log_step "Cambiando [$SITE_SLUG] de PHP $CURRENT_VER a PHP $TARGET_VER..."

# Mover archivo de pool
mv "$FROM_DIR/${SITE_SLUG}.conf" "$TO_DIR/${SITE_SLUG}.conf"

# Actualizar el contenedor en el virtual host de NGINX
sed -i "s/fastcgi_pass ${FROM_CONT}:/fastcgi_pass ${TO_CONT}:/g" "$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"

# Recargar servicios
docker exec wp-nginx nginx -s reload 2>/dev/null || true
docker restart "$FROM_CONT" >/dev/null 2>&1 || true
docker restart "$TO_CONT" >/dev/null 2>&1 || true

log_ok "Sitio [$SITE_SLUG] migrado exitosamente a PHP $TARGET_VER (Zero Downtime)."
