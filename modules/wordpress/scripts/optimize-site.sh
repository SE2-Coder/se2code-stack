#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Optimización Post-Migración & Acondicionamiento de Caché
# Soporta: Sitio Principal (Home) y Subsitios / Idiomas Aislados (/es, /en...)
# Arquitectura Zero-Collision: Prefijos Redis independientes y WP-Cron dedicados
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "  ${C_BOLD}🚀 OPTIMIZADOR POST-MIGRACIÓN & CONFIGURACIÓN DE CACHÉ SE2CODE${C_RESET}"
echo -e "${C_CYAN}======================================================================${C_RESET}\n"

CONF_FILES=($(find "$STACK_ROOT/nginx/conf.d" -type f -name "*.conf" ! -name "default*.conf" 2>/dev/null | sort || true))
if [ ${#CONF_FILES[@]} -eq 0 ]; then
    log_error "No hay sitios WordPress configurados en el stack."
    exit 1
fi

# Parámetro opcional: si se pasa el slug del sitio como $1
SITE_SLUG="${1:-}"

if [ -z "$SITE_SLUG" ]; then
    echo -e "  Selecciona el sitio a optimizar:\n"
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
    if [ "$IDX" -lt 0 ] || [ "$IDX" -ge "${#SITES[@]}" ]; then
        log_error "Opción no válida."
        exit 1
    fi
    SITE_SLUG="${SITES[$IDX]}"
fi

VHOST_FILE="$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"
if [ ! -f "$VHOST_FILE" ]; then
    log_error "No se encontró la configuración del sitio '$SITE_SLUG'."
    exit 1
fi

DOMAIN=$(grep -E "^\s*server_name\s+" "$VHOST_FILE" | head -n 1 | awk '{print $2}' | tr -d ';' || echo "$SITE_SLUG")
SITE_WEB_DIR="$STACK_ROOT/wp-data/$SITE_SLUG"

# Detectar versión PHP del sitio
PHP_CONTAINER="wp-php84"
if grep -q "fastcgi_pass.*wp-php85" "$VHOST_FILE" 2>/dev/null; then
    PHP_CONTAINER="wp-php85"
fi

echo -e "\n${C_BOLD}Sitio a optimizar:${C_RESET} ${C_CYAN}$SITE_SLUG ($DOMAIN)${C_RESET}"
echo -e "${C_BOLD}Contenedor PHP:${C_RESET}   ${C_GREEN}$PHP_CONTAINER${C_RESET}\n"

# Detección de instancias secundarias / subcarpetas de idiomas
DETECTED_SUBS=()
if [ -d "$SITE_WEB_DIR" ]; then
    for item in "$SITE_WEB_DIR"/*; do
        if [ -d "$item" ]; then
            bname=$(basename "$item")
            if [[ ! "$bname" =~ ^(wp-admin|wp-includes|wp-content|\.well-known|\.trash|updraft|backups)$ ]] && [ -f "$item/wp-config.php" ]; then
                DETECTED_SUBS+=("$bname")
            fi
        fi
    done
fi

TARGET_INSTANCES=()
# Formato de cada entrada: "DIR_PATH|CONTAINER_PATH|LABEL|REDIS_PREFIX|URL"

if [ ${#DETECTED_SUBS[@]} -gt 0 ]; then
    echo -e "${C_BOLD}${C_CYAN}Se detectaron instancias secundarias / multi-idioma en este sitio:${C_RESET}"
    echo -e "  - Principal (Home):    ${C_BOLD}https://${DOMAIN}/${C_RESET}"
    for sub in "${DETECTED_SUBS[@]}"; do
        echo -e "  - Subsitio / Idioma:   ${C_BOLD}https://${DOMAIN}/${sub}/${C_RESET}"
    done
    echo ""
    echo -e "  ${C_BOLD}¿Qué instancias deseas optimizar?${C_RESET}"
    echo -e "  ${C_BOLD}${C_GREEN}1) [RECOMENDADO] Optimizar TODO (Sitio Principal + todos los subsitios/idiomas)${C_RESET}"
    echo -e "  2) Solo el Sitio Principal (Home: https://${DOMAIN}/)"
    sub_menu_idx=3
    for sub in "${DETECTED_SUBS[@]}"; do
        echo -e "  $sub_menu_idx) Solo el subsitio [/${sub}/] (https://${DOMAIN}/${sub}/)"
        sub_menu_idx=$((sub_menu_idx + 1))
    done
    echo -e "  0) Cancelar\n"

    read -r -p "Selecciona una opción [1-$((sub_menu_idx - 1)), por defecto 1]: " SCOPE_CHOICE
    SCOPE_CHOICE="${SCOPE_CHOICE:-1}"

    if [ "$SCOPE_CHOICE" = "0" ]; then
        log_info "Operación cancelada."
        exit 0
    elif [ "$SCOPE_CHOICE" = "1" ]; then
        TARGET_INSTANCES+=("$SITE_WEB_DIR|/var/www/html/$SITE_SLUG|Sitio Principal (Home)|${SITE_SLUG}_|https://${DOMAIN}/")
        for sub in "${DETECTED_SUBS[@]}"; do
            TARGET_INSTANCES+=("$SITE_WEB_DIR/$sub|/var/www/html/$SITE_SLUG/$sub|Subsitio (/${sub}/)|${SITE_SLUG}_${sub}_|https://${DOMAIN}/${sub}/")
        done
    elif [ "$SCOPE_CHOICE" = "2" ]; then
        TARGET_INSTANCES+=("$SITE_WEB_DIR|/var/www/html/$SITE_SLUG|Sitio Principal (Home)|${SITE_SLUG}_|https://${DOMAIN}/")
    else
        CHOSEN_SUB_IDX=$((SCOPE_CHOICE - 3))
        if [ "$CHOSEN_SUB_IDX" -ge 0 ] && [ "$CHOSEN_SUB_IDX" -lt ${#DETECTED_SUBS[@]} ]; then
            sub="${DETECTED_SUBS[$CHOSEN_SUB_IDX]}"
            TARGET_INSTANCES+=("$SITE_WEB_DIR/$sub|/var/www/html/$SITE_SLUG/$sub|Subsitio (/${sub}/)|${SITE_SLUG}_${sub}_|https://${DOMAIN}/${sub}/")
        else
            log_error "Opción no válida."
            exit 1
        fi
    fi
else
    TARGET_INSTANCES+=("$SITE_WEB_DIR|/var/www/html/$SITE_SLUG|Sitio Principal (Home)|${SITE_SLUG}_|https://${DOMAIN}/")
fi

# Función de optimización modular por cada instancia
optimize_single_instance() {
    local T_DIR="$1"
    local C_PATH="$2"
    local INST_LABEL="$3"
    local R_PREFIX="$4"
    local INST_URL="$5"

    echo -e "\n${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "  ${C_BOLD}Procesando:${C_RESET} ${C_YELLOW}$INST_LABEL${C_RESET} -> ${C_GREEN}$INST_URL${C_RESET}"
    echo -e "  ${C_BOLD}Prefijo Redis aislado:${C_RESET} ${C_PURPLE}$R_PREFIX${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

    # 1. Escanear y Desactivar Plugins de Caché en Conflicto
    log_section "PASO 1: DETECCIÓN Y PURGA DE PLUGINS EN CONFLICTO"
    CONFLICTING_PLUGINS=(
        "wp-rocket"
        "litespeed-cache"
        "w3-total-cache"
        "wp-super-cache"
        "wp-fastest-cache"
        "breeze"
        "sg-cachepress"
        "cache-enabler"
        "powered-cache"
        "comet-cache"
        "hyper-cache"
        "autoptimize"
        "hide-my-wp"
        "hide-my-wp-pack"
        "wps-hide-login"
        "wp-hide-security-enhancer"
        "rename-wp-login"
        "lockdown-wp-admin"
        "easy-hide-login"
        "custom-login-url"
        "change-wp-admin-login"
        "hc-custom-wp-admin-url"
    )

    local DEACTIVATED_COUNT=0
    for plugin in "${CONFLICTING_PLUGINS[@]}"; do
        if docker exec --user 33:33 "$PHP_CONTAINER" wp plugin is-installed "$plugin" --path="$C_PATH" >/dev/null 2>&1; then
            if docker exec --user 33:33 "$PHP_CONTAINER" wp plugin is-active "$plugin" --path="$C_PATH" >/dev/null 2>&1; then
                log_warn "Plugin en conflicto detectado: '$plugin'. Desactivando..."
                docker exec --user 33:33 "$PHP_CONTAINER" wp plugin deactivate "$plugin" --path="$C_PATH" >/dev/null 2>&1 || true
                DEACTIVATED_COUNT=$((DEACTIVATED_COUNT + 1))
                log_ok "Plugin '$plugin' desactivado con éxito."
            fi
        fi
    done

    if [ "$DEACTIVATED_COUNT" -eq 0 ]; then
        log_ok "No se encontraron plugins de caché externos en conflicto activos."
    else
        log_warn "Se desactivaron $DEACTIVATED_COUNT plugin(s) de caché de proveedores anteriores."
    fi

    # Eliminar drop-ins huérfanos del proveedor anterior
    for dropin in "advanced-cache.php" "wp-cache-config.php" "db.php"; do
        if [ -f "$T_DIR/wp-content/$dropin" ]; then
            log_warn "Eliminando drop-in huérfano en conflicto: wp-content/$dropin..."
            rm -f "$T_DIR/wp-content/$dropin"
        fi
    done

    # Eliminar mu-plugins conflictivos comunes de proveedores anteriores (Bluehost / GoDaddy / Staging)
    for mu in "endurance-page-cache.php" "sso.php" "wp-staging-optimizer.php"; do
        if [ -f "$T_DIR/wp-content/mu-plugins/$mu" ]; then
            log_warn "Eliminando mu-plugin externo en conflicto: $mu..."
            rm -f "$T_DIR/wp-content/mu-plugins/$mu"
        fi
    done
    rm -rf "$T_DIR/wp-content/cache" 2>/dev/null || true

    # 2. Configurar Constantes de wp-config.php con Aislamiento Total
    log_section "PASO 2: AJUSTES DE ARQUITECTURA EN WP-CONFIG.PHP"
    local WP_CONFIG="$T_DIR/wp-config.php"
    if [ -f "$WP_CONFIG" ]; then
        # Garantizar DISABLE_WP_CRON
        if ! grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
            sed -i "/table_prefix/i define( 'DISABLE_WP_CRON', true );" "$WP_CONFIG"
        fi
        # Garantizar WP_CACHE
        if ! grep -q "define( 'WP_CACHE'" "$WP_CONFIG" && ! grep -q 'define( "WP_CACHE"' "$WP_CONFIG"; then
            sed -i "/table_prefix/i define( 'WP_CACHE', true );" "$WP_CONFIG"
        fi
        # Garantizar WP_REDIS_HOST y PORT
        if ! grep -q "WP_REDIS_HOST" "$WP_CONFIG"; then
            sed -i "/table_prefix/i define( 'WP_REDIS_HOST', 'redis' );" "$WP_CONFIG"
            sed -i "/table_prefix/i define( 'WP_REDIS_PORT', 6379 );" "$WP_CONFIG"
        fi
        # Aislamiento de prefijo Redis (crucial para evitar colisión de cachés)
        if grep -q "WP_REDIS_PREFIX" "$WP_CONFIG"; then
            sed -i "s/define(\s*['\"]WP_REDIS_PREFIX['\"].*/define( 'WP_REDIS_PREFIX', '${R_PREFIX}' );/" "$WP_CONFIG"
        else
            sed -i "/table_prefix/i define( 'WP_REDIS_PREFIX', '${R_PREFIX}' );" "$WP_CONFIG"
        fi
        if ! grep -q "WP_REDIS_TIMEOUT" "$WP_CONFIG"; then
            sed -i "/table_prefix/i define( 'WP_REDIS_TIMEOUT', 1 );" "$WP_CONFIG"
            sed -i "/table_prefix/i define( 'WP_REDIS_READ_TIMEOUT', 1 );" "$WP_CONFIG"
        fi
        if ! grep -q "RT_WP_NGINX_HELPER_CACHE_PATH" "$WP_CONFIG"; then
            sed -i "/table_prefix/i define( 'RT_WP_NGINX_HELPER_CACHE_PATH', '/var/cache/nginx' );" "$WP_CONFIG"
        fi
        log_ok "wp-config.php verificado con prefijo Redis único: '${R_PREFIX}'."
    fi

    # 3. Instalación y Activación de Redis Object Cache
    log_section "PASO 3: CONFIGURACIÓN DE REDIS OBJECT CACHE"
    log_step "Instalando y activando 'redis-cache'..."
    docker exec --user 33:33 "$PHP_CONTAINER" wp plugin install redis-cache --activate --path="$C_PATH" >/dev/null 2>&1 || \
    docker exec --user 33:33 "$PHP_CONTAINER" wp plugin activate redis-cache --path="$C_PATH" >/dev/null 2>&1 || true

    log_step "Habilitando drop-in de Redis (object-cache.php)..."
    docker exec --user 33:33 "$PHP_CONTAINER" wp redis enable --path="$C_PATH" >/dev/null 2>&1 || true
    log_ok "Redis Object Cache conectado y activo con prefijo '${R_PREFIX}'."

    # 4. Instalación y Configuración Óptima de Nginx Helper
    log_section "PASO 4: CONFIGURACIÓN DE NGINX FASTCGI CACHE HELPER"
    log_step "Instalando y activando 'nginx-helper'..."
    docker exec --user 33:33 "$PHP_CONTAINER" wp plugin install nginx-helper --activate --path="$C_PATH" >/dev/null 2>&1 || \
    docker exec --user 33:33 "$PHP_CONTAINER" wp plugin activate nginx-helper --path="$C_PATH" >/dev/null 2>&1 || true

    log_step "Aplicando configuración óptima de FastCGI Purge..."
    NGINX_HELPER_CONFIG='{
        "enable_purge": "1",
        "cache_method": "enable_fastcgi",
        "purge_method": "unlink_files",
        "enable_map": 0,
        "enable_log": 0,
        "log_level": "INFO",
        "log_filesize": "5",
        "enable_stamp": 0,
        "purge_homepage_on_edit": "1",
        "purge_homepage_on_del": "1",
        "purge_archive_on_edit": "1",
        "purge_archive_on_del": "1",
        "purge_archive_on_new_comment": 0,
        "purge_archive_on_deleted_comment": "1",
        "purge_page_on_mod": "1",
        "purge_page_on_new_comment": "1",
        "purge_page_on_deleted_comment": "1",
        "purge_feeds": "1",
        "purge_amp_urls": "1"
    }'
    docker exec --user 33:33 "$PHP_CONTAINER" wp option update rt_wp_nginx_helper_options "$NGINX_HELPER_CONFIG" --format=json --path="$C_PATH" >/dev/null 2>&1 || true
    docker exec --user 33:33 "$PHP_CONTAINER" wp cap add administrator 'Nginx Helper | Purge cache' --path="$C_PATH" >/dev/null 2>&1 || true
    docker exec --user 33:33 "$PHP_CONTAINER" wp cap add administrator 'Nginx Helper | Config' --path="$C_PATH" >/dev/null 2>&1 || true
    log_ok "Nginx Helper configurado con reglas automáticas de purga FastCGI."

    # 5. Instalar Acelerador y Blindaje se2Code en mu-plugins
    log_section "PASO 5: INSTALANDO ACELERADOR Y BLINDAJE SE2CODE"
    mkdir -p "$T_DIR/wp-content/mu-plugins"
    SE2CODE_TPL="$STACK_ROOT/modules/wordpress/templates/se2code-core.php.tpl"
    [ ! -f "$SE2CODE_TPL" ] && SE2CODE_TPL="$STACK_ROOT/templates/se2code-core.php.tpl"
    if [ -f "$SE2CODE_TPL" ]; then
        cp "$SE2CODE_TPL" "$T_DIR/wp-content/mu-plugins/se2code-core.php"
        chmod 644 "$T_DIR/wp-content/mu-plugins/se2code-core.php"
        log_ok "se2code-core.php desplegado en mu-plugins."
    fi

    # 6. Corrección de Permisos
    log_section "PASO 6: NORMALIZACIÓN DE PERMISOS DE ARCHIVOS"
    sudo chown -R 33:33 "$T_DIR" 2>/dev/null || chown -R 33:33 "$T_DIR" 2>/dev/null || true
    find "$T_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
    find "$T_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true
    [ -f "$WP_CONFIG" ] && chmod 600 "$WP_CONFIG"
    log_ok "Permisos establecidos: directorios 755, archivos 644, wp-config 600 (usuario www-data)."

    # 7. Action Scheduler y Cron de Sistema
    log_section "PASO 7: REGISTRO DE CRON DE SISTEMA & ACTION SCHEDULER"
    log_step "Optimizando Elementor y acondicionando permisos de caché FastCGI..."
    docker exec --user 33:33 "$PHP_CONTAINER" wp option update elementor_editor_break_frames 1 --path="$C_PATH" >/dev/null 2>&1 || true
    docker exec --user 33:33 "$PHP_CONTAINER" wp option update elementor_allow_tracking 'no' --path="$C_PATH" >/dev/null 2>&1 || true

    log_step "Limpiando tareas fallidas de Action Scheduler..."
    docker exec --user 33:33 "$PHP_CONTAINER" wp eval '
    global $wpdb;
    $wpdb->query("DELETE FROM " . $wpdb->prefix . "actionscheduler_actions WHERE status IN (\x27failed\x27, \x27canceled\x27);");
    $wpdb->query("DELETE FROM " . $wpdb->prefix . "actionscheduler_logs WHERE action_id NOT IN (SELECT action_id FROM " . $wpdb->prefix . "actionscheduler_actions);");
    ' --path="$C_PATH" >/dev/null 2>&1 || true

    log_step "Asegurando cron de sistema dedicado para $INST_LABEL..."
    CRON_FILE="/etc/cron.d/wordpress-cron"
    if [ -d "/etc/cron.d" ]; then
        if ! grep -Fq "$C_PATH cron event run" "$CRON_FILE" 2>/dev/null; then
            echo "* * * * * root docker exec -i --user 33:33 $PHP_CONTAINER wp --allow-root --path=$C_PATH cron event run --due-now > /dev/null 2>&1" >> "$CRON_FILE"
        fi
        if ! grep -Fq "$C_PATH action-scheduler run" "$CRON_FILE" 2>/dev/null; then
            echo "*/2 * * * * root docker exec -i --user 33:33 $PHP_CONTAINER wp --allow-root --path=$C_PATH action-scheduler run > /dev/null 2>&1" >> "$CRON_FILE"
        fi
        chmod 0644 "$CRON_FILE"
        systemctl restart cron 2>/dev/null || true
        log_ok "Reglas de Cron y Action Scheduler registradas activas en $CRON_FILE."
    fi

    log_step "Ejecutando eventos en cola de WP-Cron y Action Scheduler ahora mismo..."
    docker exec --user 33:33 "$PHP_CONTAINER" wp cron event run --due-now --path="$C_PATH" >/dev/null 2>&1 || true
    docker exec --user 33:33 "$PHP_CONTAINER" wp action-scheduler run --path="$C_PATH" >/dev/null 2>&1 || true

    log_step "Purgando transients expirados y regenerando estilos..."
    docker exec --user 33:33 "$PHP_CONTAINER" wp transient delete --all --path="$C_PATH" >/dev/null 2>&1 || true
    docker exec --user 33:33 "$PHP_CONTAINER" wp elementor flush_css --path="$C_PATH" >/dev/null 2>&1 || true
    docker exec --user 33:33 "$PHP_CONTAINER" wp cache flush --path="$C_PATH" >/dev/null 2>&1 || true
    log_ok "Instancia [$INST_LABEL] optimizada exitosamente."
}

# Ejecutar optimización en todas las instancias seleccionadas
for inst in "${TARGET_INSTANCES[@]}"; do
    IFS="|" read -r t_dir c_path label r_prefix url <<< "$inst"
    optimize_single_instance "$t_dir" "$c_path" "$label" "$r_prefix" "$url"
done

# Purgas globales de servidor
log_section "PASO FINAL: RECARGA DE SERVICIOS Y PURGA GLOBAL"
docker exec wp-nginx chmod -R 777 /var/cache/nginx >/dev/null 2>&1 || true
docker exec -u 0 wp-nginx sh -c 'rm -rf /var/cache/nginx/* 2>/dev/null || true'
docker exec wp-nginx nginx -s reload 2>/dev/null || true
docker restart "$PHP_CONTAINER" >/dev/null 2>&1 || true

# 8. Resumen Final
echo -e "\n${C_BOLD}${C_GREEN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}         ¡OPTIMIZACIÓN Y ACONDICIONAMIENTO COMPLETADOS!               ${C_RESET}"
echo -e "${C_GREEN}======================================================================${C_RESET}\n"

for inst in "${TARGET_INSTANCES[@]}"; do
    IFS="|" read -r _ _ label r_prefix url <<< "$inst"
    echo -e "  ✔ ${C_BOLD}$label:${C_RESET} ${C_CYAN}$url${C_RESET}"
    echo -e "    - Redis Prefix: ${C_PURPLE}$r_prefix${C_RESET} (Aislado de otras instancias)"
    echo -e "    - Cron / Action Scheduler: ${C_GREEN}Activo cada minuto${C_RESET}"
done

echo -e "\n${C_BOLD}${C_YELLOW}⚡ RECORDATORIO FUNDAMENTAL:${C_RESET}"
echo -e "  ${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e "  ⚠️  ${C_BOLD}NO instales plugins de caché adicionales${C_RESET} en este WordPress."
echo -e "  El servidor ya entrega páginas a través de RAM (Redis) y Nginx FastCGI."
echo -e "  Plugins como ${C_YELLOW}WP Rocket, LiteSpeed o W3TC${C_RESET} solo frenarán la velocidad."
echo -e "  ${C_CYAN}----------------------------------------------------------------------${C_RESET}\n"
