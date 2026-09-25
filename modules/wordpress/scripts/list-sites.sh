#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Listado Detallado de Sitios, Landing Pages y Aplicaciones
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

ALL_CONFS=($(find "$STACK_ROOT/nginx/conf.d" -maxdepth 1 -type f -name "*.conf" ! -name "default*.conf" 2>/dev/null | sort || true))

WP_FILES=()
LANDING_FILES=()
APP_FILES=()

for conf in "${ALL_CONFS[@]}"; do
    slug=$(basename "$conf" .conf)
    if grep -q "proxy_pass" "$conf"; then
        APP_FILES+=("$conf")
    elif grep -qi "\(Landing Page" "$conf" || [ -f "$STACK_ROOT/wp-data/$slug/index.html" -a ! -f "$STACK_ROOT/wp-data/$slug/wp-config.php" ]; then
        LANDING_FILES+=("$conf")
    else
        WP_FILES+=("$conf")
    fi
done

# ==============================================================================
# 1. TABLA DE SITIOS WORDPRESS
# ==============================================================================
echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "  ${C_BOLD}📋 SITIOS WORDPRESS INSTALADOS (CON BASE DE DATOS Y REDIS)${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}"

if [ ${#WP_FILES[@]} -eq 0 ]; then
    echo -e "  ${C_YELLOW}No hay sitios WordPress configurados actualmente.${C_RESET}"
else
    printf "  ${C_BOLD}%-3s %-18s %-26s %-10s %-10s %-10s${C_RESET}\n" "#" "SLUG" "DOMINIO" "PHP" "ESPACIO" "SSL"
    echo -e "  ${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"

    idx=1
    for conf in "${WP_FILES[@]}"; do
        slug=$(basename "$conf" .conf)
        domain=$(grep -E "^\s*server_name\s+" "$conf" | head -n 1 | awk '{print $2}' | tr -d ';' || echo "$slug")
        
        if [ -f "$STACK_ROOT/php/php84/pools/${slug}.conf" ]; then
            php_col="${C_GREEN}PHP 8.4${C_RESET}"
        elif [ -f "$STACK_ROOT/php/php85/pools/${slug}.conf" ]; then
            php_col="${C_BLUE}PHP 8.5${C_RESET}"
        else
            php_col="${C_RED}N/A${C_RESET}"
        fi

        site_dir="$STACK_ROOT/wp-data/$slug"
        size="0M"
        [ -d "$site_dir" ] && size=$(du -sh "$site_dir" 2>/dev/null | awk '{print $1}' || echo "0M")

        cert_file="$STACK_ROOT/nginx/certs/$domain/fullchain.pem"
        [ -f "$cert_file" ] && ssl_col="${C_GREEN}Activo ✔${C_RESET}" || ssl_col="${C_YELLOW}No SSL ⚠${C_RESET}"

        echo -e "  $(printf '%-3s' "$idx") $(printf '%-18s' "$slug") $(printf '%-26s' "$domain") $(printf '%-10s' "$php_col") $(printf '%-10s' "$size") $ssl_col"
        idx=$((idx + 1))
    done
    echo -e "  ${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"
    echo -e "  Total WordPress: ${C_BOLD}${C_GREEN}${#WP_FILES[@]}${C_RESET}"
fi

# ==============================================================================
# 2. TABLA DE LANDING PAGES BÁSICAS (SIN BASE DE DATOS)
# ==============================================================================
echo -e "\n${C_BOLD}${C_GREEN}======================================================================${C_RESET}"
echo -e "  ${C_BOLD}⚡ LANDING PAGES BÁSICAS (ESTÁTICAS / SIN BASE DE DATOS)${C_RESET}"
echo -e "${C_GREEN}======================================================================${C_RESET}"

if [ ${#LANDING_FILES[@]} -eq 0 ]; then
    echo -e "  ${C_GRAY}No hay ninguna landing page básica configurada.${C_RESET}"
    echo -e "  Usa la opción 3 para crear una landing page ultrarrápida sin base de datos."
else
    printf "  ${C_BOLD}%-3s %-18s %-26s %-14s %-10s %-10s${C_RESET}\n" "#" "SLUG" "DOMINIO" "TIPO" "ESPACIO" "SSL"
    echo -e "  ${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"

    lidx=1
    for lconf in "${LANDING_FILES[@]}"; do
        lslug=$(basename "$lconf" .conf)
        ldomain=$(grep -E "^\s*server_name\s+" "$lconf" | head -n 1 | awk '{print $2}' | tr -d ';' || echo "$lslug")

        if grep -q "fastcgi_pass" "$lconf"; then
            ltype="${C_GREEN}HTML + PHP${C_RESET}"
        else
            ltype="${C_CYAN}HTML Puro${C_RESET}"
        fi

        lsite_dir="$STACK_ROOT/wp-data/$lslug"
        lsize="0M"
        [ -d "$lsite_dir" ] && lsize=$(du -sh "$lsite_dir" 2>/dev/null | awk '{print $1}' || echo "0M")

        lcert="$STACK_ROOT/nginx/certs/$ldomain/fullchain.pem"
        [ -f "$lcert" ] && lssl="${C_GREEN}Activo ✔${C_RESET}" || lssl="${C_YELLOW}No SSL ⚠${C_RESET}"

        echo -e "  $(printf '%-3s' "$lidx") $(printf '%-18s' "$lslug") $(printf '%-26s' "$ldomain") $(printf '%-14s' "$ltype") $(printf '%-10s' "$lsize") $lssl"
        lidx=$((lidx + 1))
    done
    echo -e "  ${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"
    echo -e "  Total Landing Pages: ${C_BOLD}${C_GREEN}${#LANDING_FILES[@]}${C_RESET}"
fi

# ==============================================================================
# 3. TABLA DE APLICACIONES & PROXIES NGINX (ASTRO / DIRECTUS / NODE / ETC)
# ==============================================================================
if [ ${#APP_FILES[@]} -gt 0 ]; then
    echo -e "\n${C_BOLD}${C_PURPLE}======================================================================${C_RESET}"
    echo -e "  ${C_BOLD}🚀 APLICACIONES & PROXIES NGINX (ASTRO / DIRECTUS / APPS)${C_RESET}"
    echo -e "${C_PURPLE}======================================================================${C_RESET}"
    printf "  ${C_BOLD}%-3s %-20s %-28s %-12s %-10s${C_RESET}\n" "#" "APP / SLUG" "DOMINIO" "TIPO" "SSL"
    echo -e "  ${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"
    app_idx=1
    for aconf in "${APP_FILES[@]}"; do
        aslug=$(basename "$aconf" .conf)
        adomain=$(grep -E "^\s*server_name\s+" "$aconf" | head -n 1 | awk '{print $2}' | tr -d ";" || echo "$aslug")
        acert="$STACK_ROOT/nginx/certs/$adomain/fullchain.pem"
        if [ -f "$acert" ] || grep -q "ssl_certificate" "$aconf"; then
            assl="${C_GREEN}Activo ✔${C_RESET}"
        else
            assl="${C_YELLOW}No SSL ⚠${C_RESET}"
        fi
        printf "  %-3s %-20s %-28s %-12s %b\n" "$app_idx" "$aslug" "$adomain" "Proxy Pass" "$assl"
        app_idx=$((app_idx + 1))
    done
fi
echo ""
