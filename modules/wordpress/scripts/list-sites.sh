#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WordPress: Listado Detallado de Sitios
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "  ${C_BOLD}📋 SITIOS WORDPRESS INSTALADOS EN ESTE SERVIDOR${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}"

CONF_FILES=($(find "$STACK_ROOT/nginx/conf.d" -type f -name "*.conf" ! -name "default*.conf" 2>/dev/null | sort || true))

if [ ${#CONF_FILES[@]} -eq 0 ]; then
    echo -e "  ${C_YELLOW}Actualmente no hay ningún sitio WordPress configurado.${C_RESET}"
    echo -e "  Usa la opción 1 para crear tu primer sitio.\n"
    exit 0
fi

# Encabezado de la tabla
printf "  ${C_BOLD}%-3s %-20s %-25s %-10s %-12s %-10s${C_RESET}\n" "#" "SLUG" "DOMINIO" "PHP" "ESPACIO" "SSL"
echo -e "  ${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"

idx=1
for conf in "${CONF_FILES[@]}"; do
    slug=$(basename "$conf" .conf)
    
    # Extraer dominio
    domain=$(grep -E "^\s*server_name\s+" "$conf" | head -n 1 | awk '{print $2}' | tr -d ';' || echo "$slug")
    
    # Detectar versión de PHP
    if [ -f "$STACK_ROOT/php/php84/pools/${slug}.conf" ]; then
        php_ver="${C_GREEN}PHP 8.4${C_RESET}"
    elif [ -f "$STACK_ROOT/php/php85/pools/${slug}.conf" ]; then
        php_ver="${C_BLUE}PHP 8.5${C_RESET}"
    else
        php_ver="${C_RED}N/A${C_RESET}"
    fi

    # Espacio en disco
    site_dir="$STACK_ROOT/wp-data/$slug"
    if [ -d "$site_dir" ]; then
        size=$(du -sh "$site_dir" 2>/dev/null | awk '{print $1}' || echo "0M")
    else
        size="0M"
    fi

    # Estado SSL
    cert_file="$STACK_ROOT/nginx/certs/$domain/fullchain.pem"
    if [ -f "$cert_file" ]; then
        ssl_status="${C_GREEN}Activo ✔${C_RESET}"
    else
        ssl_status="${C_YELLOW}No SSL ⚠${C_RESET}"
    fi

    printf "  %-3s %-20s %-25s %-19s %-12s %-19s\n" "$idx" "$slug" "$domain" "$php_ver" "$size" "$ssl_status"
    idx=$((idx + 1))
done

echo -e "  ${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"
echo -e "  Total de sitios en producción: ${C_BOLD}${C_GREEN}${#CONF_FILES[@]}${C_RESET}\n"
