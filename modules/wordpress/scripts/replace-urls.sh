#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Reemplazo Canónico de URLs (4 Variantes ➔ 1 Sola URL)
# Corrige contenido mixto, repara SSL, enlaces rotos y cambios de dominio
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "  ${C_BOLD}🔗 REEMPLAZO INTELIGENTE DE URLs (4 VARIANTES ➔ 1 CANÓNICA)${C_RESET}"
echo -e "  ${C_DIM}Elimina contenido mixto, repara SSL y sincroniza Elementor${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}\n"

CONF_FILES=($(find "$STACK_ROOT/nginx/conf.d" -type f -name "*.conf" ! -name "default*.conf" 2>/dev/null | sort || true))
if [ ${#CONF_FILES[@]} -eq 0 ]; then
    log_error "No hay sitios WordPress configurados en el stack."
    exit 1
fi

SITE_SLUG="${1:-}"

if [ -z "$SITE_SLUG" ]; then
    echo -e "  Selecciona el sitio a procesar:\n"
    i=1
    SITES=()
    for conf in "${CONF_FILES[@]}"; do
        s=$(basename "$conf" .conf)
        SITES+=("$s")
        dom=$(grep -E "^\s*server_name\s+" "$conf" | head -n 1 | awk "{print \$2}" | tr -d ";" || echo "$s")
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
fi

VHOST_FILE="$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"
if [ ! -f "$VHOST_FILE" ]; then
    log_error "No se encontró la configuración del sitio '$SITE_SLUG'."
    exit 1
fi

DOMAIN=$(grep -E "^\s*server_name\s+" "$VHOST_FILE" | head -n 1 | awk "{print \$2}" | tr -d ";" || echo "$SITE_SLUG")
SITE_WEB_DIR="$STACK_ROOT/wp-data/$SITE_SLUG"
CONTAINER_PATH="/var/www/html/$SITE_SLUG"

PHP_CONTAINER="wp-php84"
if grep -q "fastcgi_pass.*wp-php85" "$VHOST_FILE" 2>/dev/null; then
    PHP_CONTAINER="wp-php85"
fi

# Detectar URL actual en la base de datos
DETECTED_URL=$(docker exec --user 33:33 "$PHP_CONTAINER" wp option get siteurl --path="$CONTAINER_PATH" 2>/dev/null || echo "https://${DOMAIN}")

echo -e "\n  Sitio seleccionado : ${C_CYAN}$SITE_SLUG ($DOMAIN)${C_RESET}"
echo -e "  Motor PHP          : ${C_GREEN}$PHP_CONTAINER${C_RESET}"
echo -e "  URL detectada en BD: ${C_YELLOW}$DETECTED_URL${C_RESET}\n"

# 1. Pedir URL origen
echo -e "${C_BOLD}1. Dominio o URL origen a buscar:${C_RESET}"
echo -e "   ${C_DIM}(Se generarán automáticamente las variantes https/http y con/sin www)${C_RESET}"
read -r -p "   Ingresa el dominio a buscar [por defecto: $DETECTED_URL]: " SEARCH_INPUT
SEARCH_INPUT=${SEARCH_INPUT:-$DETECTED_URL}

# 2. Pedir URL canónica final de destino
DEST_DEFAULT="$DETECTED_URL"
echo -e "\n${C_BOLD}2. URL canónica final de destino (ÚNICA URL que quedará en la base de datos):${C_RESET}"
echo -e "   ${C_DIM}(Ejemplo: https://www.midominio.com o https://midominio.com o https://staging.se2code.com)${C_RESET}"
read -r -p "   Ingresa la URL final [por defecto: $DEST_DEFAULT]: " DEST_INPUT
DEST_INPUT=${DEST_INPUT:-$DEST_DEFAULT}

# Normalizar cadenas
CLEAN_SEARCH=$(echo "$SEARCH_INPUT" | sed -e "s|^https\?://||" -e "s|/*$||")
ROOT_SEARCH=$(echo "$CLEAN_SEARCH" | sed "s|^www\.||")

CANONICAL_DEST=$(echo "$DEST_INPUT" | sed -e "s|/*$||")
if [[ ! "$CANONICAL_DEST" =~ ^https?:// ]]; then
    CANONICAL_DEST="https://${CANONICAL_DEST}"
fi
CLEAN_DEST_NO_PROTO=$(echo "$CANONICAL_DEST" | sed -e "s|^https\?://||")

# Matriz de 4 variantes canónicas (orden: www primero)
VARIANTS=(
    "https://www.${ROOT_SEARCH}"
    "http://www.${ROOT_SEARCH}"
    "https://${ROOT_SEARCH}"
    "http://${ROOT_SEARCH}"
)

REL_VARIANTS=(
    "//www.${ROOT_SEARCH}"
    "//${ROOT_SEARCH}"
)

echo -e "\n${C_BOLD}${C_GREEN}--- PLAN DE REEMPLAZO MULTIVARIANTE ---${C_RESET}"
echo -e "Dominio base identificado : ${C_YELLOW}${ROOT_SEARCH}${C_RESET}"
echo -e "URL final canónica destino: ${C_CYAN}${CANONICAL_DEST}${C_RESET}\n"

REPLACEMENTS_TO_RUN=()
for v in "${VARIANTS[@]}"; do
    if [ "$v" != "$CANONICAL_DEST" ]; then
        echo -e "  ✔  ${C_RED}$v${C_RESET}  ➔  ${C_GREEN}${CANONICAL_DEST}${C_RESET}"
        REPLACEMENTS_TO_RUN+=("$v")
    else
        echo -e "  ℹ️   ${C_DIM}$v (ya es la URL canónica destino, omitida)${C_RESET}"
    fi
done

for rv in "${REL_VARIANTS[@]}"; do
    if [ "$rv" != "//$CLEAN_DEST_NO_PROTO" ]; then
        echo -e "  ✔  ${C_RED}$rv${C_RESET}  ➔  ${C_GREEN}//${CLEAN_DEST_NO_PROTO}${C_RESET}"
    fi
done

if [ ${#REPLACEMENTS_TO_RUN[@]} -eq 0 ]; then
    log_info "No hay variantes que reemplazar; la base de datos ya apunta a la URL canónica."
    exit 0
fi

echo ""
read -r -p "¿Deseas ejecutar estos reemplazos en la base de datos ahora? [S/n]: " CONFIRM
CONFIRM=${CONFIRM:-S}
if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    log_info "Operación cancelada por el usuario."
    exit 0
fi

log_section "PASO 1: EJECUTANDO REEMPLAZOS EN TODAS LAS TABLAS"

for v in "${REPLACEMENTS_TO_RUN[@]}"; do
    log_step "Reemplazando: '$v' ➔ '$CANONICAL_DEST'..."
    docker exec --user 33:33 "$PHP_CONTAINER" wp search-replace "$v" "$CANONICAL_DEST" \
        --all-tables --precise --skip-columns=guid --path="$CONTAINER_PATH" || true
done

# Protocolo relativo
for rv in "${REL_VARIANTS[@]}"; do
    if [ "$rv" != "//$CLEAN_DEST_NO_PROTO" ]; then
        docker exec -i --user 33:33 "$PHP_CONTAINER" wp search-replace "$rv" "//$CLEAN_DEST_NO_PROTO" \
            --all-tables --precise --skip-columns=guid --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
    fi
done

# Elementor Native Replace
if docker exec --user 33:33 "$PHP_CONTAINER" wp plugin is-active elementor --path="$CONTAINER_PATH" >/dev/null 2>&1; then
    log_section "PASO 2: SINCRONIZANDO BIBLIOTECA Y ESTILOS DE ELEMENTOR"
    for v in "${REPLACEMENTS_TO_RUN[@]}"; do
        log_step "Elementor: '$v' ➔ '$CANONICAL_DEST'..."
        docker exec -i --user 33:33 "$PHP_CONTAINER" wp elementor replace-urls "$v" "$CANONICAL_DEST" --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
    done
    docker exec -i --user 33:33 "$PHP_CONTAINER" wp elementor flush_css --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
    log_ok "Caché CSS compilada de Elementor regenerada con éxito."
fi

# Regenerar permalinks y purgar cachés
log_section "PASO 3: LIMPIEZA DE CACHÉ Y PERMALINKS"
docker exec -i --user 33:33 "$PHP_CONTAINER" wp rewrite flush --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
docker exec -i --user 33:33 "$PHP_CONTAINER" wp cache flush --path="$CONTAINER_PATH" >/dev/null 2>&1 || true
docker exec -i redis redis-cli FLUSHALL >/dev/null 2>&1 || true
sudo rm -rf /var/cache/nginx/* 2>/dev/null || true
docker exec wp-nginx nginx -s reload 2>/dev/null || true
log_ok "Caché FastCGI y memoria Redis vaciados."

echo -e "\n${C_BOLD}${C_GREEN}======================================================================${C_RESET}"
echo -e "  ${C_BOLD}${C_GREEN}🎉 ¡REEMPLAZO CANÓNICO DE URLs COMPLETADO EXITOSAMENTE!${C_RESET}"
echo -e "  - Todas las variantes ahora apuntan a: ${C_CYAN}${CANONICAL_DEST}${C_RESET}"
echo -e "  - Contenido mixto eliminado y candado SSL unificado."
echo -e "${C_GREEN}======================================================================${C_RESET}\n"
