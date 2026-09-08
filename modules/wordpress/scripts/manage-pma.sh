#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Módulo de Gestión de phpMyAdmin y Acceso a Base de Datos
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WP_DIR="$STACK_ROOT/modules/wordpress"

# Cargar utilidades del Core
source "$STACK_ROOT/core/banner.sh"
[ -f "$STACK_ROOT/core/ports.sh" ] && source "$STACK_ROOT/core/ports.sh"

# Cargar variables de entorno
if [ -f "$WP_DIR/.env" ]; then
    set -a
    source "$WP_DIR/.env"
    set +a
fi

DB_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
CURRENT_PMA_PORT="${PMA_PORT:-8080}"
CURRENT_BIND_IP="${PMA_BIND_IP:-0.0.0.0}"

# Detectar IP pública e IP de WireGuard
get_server_ip() {
    curl -s4 --max-time 2 ifconfig.me || curl -s4 --max-time 2 icanhazip.com || ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || echo "127.0.0.1"
}

get_wireguard_ip() {
    if ip addr show wg0 >/dev/null 2>&1; then
        ip addr show wg0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "10.13.13.1"
    else
        echo "10.13.13.1"
    fi
}

is_pma_running() {
    if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^wp-phpmyadmin$"; then
        return 0
    else
        return 1
    fi
}

show_credentials() {
    local ACCESS_PORT="${1:-$CURRENT_PMA_PORT}"
    local BIND="${2:-$CURRENT_BIND_IP}"
    local PUB_IP
    PUB_IP=$(get_server_ip)
    local WG_IP
    WG_IP=$(get_wireguard_ip)

    echo -e "\n${C_BOLD}${C_CYAN}╔════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}║              🗄️  DATOS DE ACCESO A PHPMYADMIN                          ║${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}╚════════════════════════════════════════════════════════════════════════╝${C_RESET}"

    if [ "$BIND" = "127.0.0.1" ]; then
        echo -e "  - ${C_BOLD}URL Local:${C_RESET}       ${C_GREEN}http://127.0.0.1:${ACCESS_PORT}${C_RESET} (o vía túnel SSH)"
    elif [ "$BIND" = "$WG_IP" ] || [ "$BIND" = "10.13.13.1" ]; then
        echo -e "  - ${C_BOLD}URL VPN (Segura):${C_RESET} ${C_GREEN}http://${WG_IP}:${ACCESS_PORT}${C_RESET} (conectado a WireGuard)"
    else
        echo -e "  - ${C_BOLD}URL Pública:${C_RESET}     ${C_GREEN}http://${PUB_IP}:${ACCESS_PORT}${C_RESET}"
        if [ "$WG_IP" != "10.13.13.1" ] || ip addr show wg0 >/dev/null 2>&1; then
            echo -e "  - ${C_BOLD}URL VPN:${C_RESET}         ${C_GREEN}http://${WG_IP}:${ACCESS_PORT}${C_RESET} (vía WireGuard)"
        fi
    fi

    echo -e "  - ${C_BOLD}Servidor / Host:${C_RESET} ${C_CYAN}mariadb${C_RESET} (o localhost en el formulario)"
    echo -e "  - ${C_BOLD}Usuario Maestro:${C_RESET} ${C_BOLD}${C_YELLOW}root${C_RESET}"
    echo -e "  - ${C_BOLD}Contraseña Root:${C_RESET} ${C_BOLD}${C_GREEN}${DB_ROOT_PASSWORD}${C_RESET}"
    echo -e "${C_GRAY}  (Con el usuario 'root' puedes ver, crear, exportar y editar TODAS las bases de datos).${C_RESET}"
    echo -e "${C_CYAN}════════════════════════════════════════════════════════════════════════${C_RESET}\n"
}

start_pma() {
    log_section "INICIAR / ACTIVAR PHPMYADMIN"

    if is_pma_running; then
        log_ok "phpMyAdmin ya se encuentra corriendo actualmente."
        show_credentials "$CURRENT_PMA_PORT" "$CURRENT_BIND_IP"
        return 0
    fi

    local PORT_TO_USE="$CURRENT_PMA_PORT"
    local BIND_TO_USE="$CURRENT_BIND_IP"

    # Si se pasan parámetros por CLI
    if [ -n "${1:-}" ]; then
        PORT_TO_USE="$1"
    else
        echo -e "${C_CYAN}¿Qué puerto deseas usar para phpMyAdmin?${C_RESET}"
        echo -e "  - Rango sugerido: ${C_GREEN}8000 a 65535${C_RESET}"
        echo -e "  - Puerto sugerido por defecto: ${C_BOLD}${C_CYAN}${CURRENT_PMA_PORT}${C_RESET}"
        read -r -p "Escribe el puerto [Enter para ${CURRENT_PMA_PORT}]: " CHOSEN_PORT
        PORT_TO_USE="${CHOSEN_PORT:-$CURRENT_PMA_PORT}"

        if ! [[ "$PORT_TO_USE" =~ ^[0-9]+$ ]] || [ "$PORT_TO_USE" -lt 1024 ] || [ "$PORT_TO_USE" -gt 65535 ]; then
            log_error "Puerto inválido. Usando puerto por defecto: 8080."
            PORT_TO_USE=8080
        fi

        echo -e "\n${C_CYAN}¿Cómo deseas exponer phpMyAdmin?${C_RESET}"
        echo -e "  1) ${C_GREEN}[Estándar / Web]${C_RESET} Accesible vía IP pública en puerto ${PORT_TO_USE} (con UFW)"
        echo -e "  2) ${C_PURPLE}[Máxima Seguridad]${C_RESET} Solo accesible a través del túnel VPN WireGuard (10.13.13.1)"
        echo -e "  3) [Localhost Únicamente] Solo accesible mediante túnel SSH local (127.0.0.1)"
        read -r -p "Selecciona una opción [1-3, por defecto 1]: " EXPOSE_OPT
        EXPOSE_OPT="${EXPOSE_OPT:-1}"

        case "$EXPOSE_OPT" in
            2)
                BIND_TO_USE=$(get_wireguard_ip)
                log_info "phpMyAdmin será enlazado exclusivamente a la IP de WireGuard ($BIND_TO_USE)."
                ;;
            3)
                BIND_TO_USE="127.0.0.1"
                log_info "phpMyAdmin será enlazado únicamente a 127.0.0.1."
                ;;
            *)
                BIND_TO_USE="0.0.0.0"
                ;;
        esac
    fi

    # Actualizar o inyectar PMA_PORT y PMA_BIND_IP en .env
    if [ -f "$WP_DIR/.env" ]; then
        if grep -q "^PMA_PORT=" "$WP_DIR/.env"; then
            sed -i "s/^PMA_PORT=.*/PMA_PORT=${PORT_TO_USE}/" "$WP_DIR/.env"
        else
            echo "PMA_PORT=${PORT_TO_USE}" >> "$WP_DIR/.env"
        fi

        if grep -q "^PMA_BIND_IP=" "$WP_DIR/.env"; then
            sed -i "s/^PMA_BIND_IP=.*/PMA_BIND_IP=${BIND_TO_USE}/" "$WP_DIR/.env"
        else
            echo "PMA_BIND_IP=${BIND_TO_USE}" >> "$WP_DIR/.env"
        fi
    fi

    export PMA_PORT="$PORT_TO_USE"
    export PMA_BIND_IP="$BIND_TO_USE"

    # Abrir puerto en UFW si es acceso público
    if [ "$BIND_TO_USE" = "0.0.0.0" ] && command -v ufw >/dev/null 2>&1; then
        ufw allow "${PORT_TO_USE}/tcp" comment "se2Code phpMyAdmin" >/dev/null 2>&1 || true
        log_ok "Regla añadida en UFW para el puerto ${PORT_TO_USE}/tcp."
    fi

    log_step "Levantando contenedor phpMyAdmin en Docker Compose..."
    docker compose -f "$WP_DIR/docker-compose.yml" up -d phpmyadmin

    log_info "Esperando sincronización del contenedor..."
    sleep 3

    if is_pma_running; then
        log_ok "phpMyAdmin iniciado exitosamente."
        show_credentials "$PORT_TO_USE" "$BIND_TO_USE"
    else
        log_error "El contenedor no pudo arrancar. Revisa 'docker logs wp-phpmyadmin'."
    fi
}

stop_pma() {
    log_section "DETENER PHPMYADMIN (LIBERAR RECURSOS)"

    if ! is_pma_running; then
        log_info "phpMyAdmin ya se encuentra detenido."
        return 0
    fi

    log_step "Deteniendo contenedor wp-phpmyadmin..."
    docker stop wp-phpmyadmin >/dev/null 2>&1 || docker compose -f "$WP_DIR/docker-compose.yml" stop phpmyadmin >/dev/null 2>&1 || true

    # Cerrar puerto en UFW si estaba abierto
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow "${CURRENT_PMA_PORT}/tcp" >/dev/null 2>&1 || true
        ufw reload >/dev/null 2>&1 || true
        log_ok "Puerto ${CURRENT_PMA_PORT}/tcp cerrado en Firewall UFW."
    fi

    log_ok "phpMyAdmin detenido. Memoria RAM liberada y acceso deshabilitado."
}

show_status() {
    log_section "ESTADO DE PHPMYADMIN"

    if is_pma_running; then
        local RUNTIME_PORT
        RUNTIME_PORT=$(docker port wp-phpmyadmin 80 2>/dev/null | awk -F: '{print $NF}' | head -n 1 || echo "$CURRENT_PMA_PORT")
        echo -e "  - Estado:            ${C_BOLD}${C_GREEN}ACTIVO (En ejecución) ✔${C_RESET}"
        echo -e "  - Puerto escuchando: ${C_BOLD}${C_CYAN}${RUNTIME_PORT}/tcp${C_RESET}"
        show_credentials "$RUNTIME_PORT" "$CURRENT_BIND_IP"
    else
        echo -e "  - Estado:            ${C_BOLD}${C_YELLOW}DETENIDO (Apagado para ahorro de RAM) ⏹${C_RESET}"
        echo -e "  - Puerto configurado:${C_GRAY} ${CURRENT_PMA_PORT}/tcp${C_RESET}"
        echo -e "\nPuedes iniciarlo en cualquier momento ejecutando: ${C_BOLD}${C_GREEN}se2code pma start${C_RESET}\n"
    fi
}

reset_wp_password() {
    log_section "CAMBIO RÁPIDO DE CONTRASEÑA WORDPRESS (SIN SQL)"
    echo -e "${C_GRAY}Esta herramienta te permite cambiar la contraseña de cualquier usuario${C_RESET}"
    echo -e "${C_GRAY}administrador de WordPress al instante sin tener que abrir la base de datos.${C_RESET}\n"

    local SITES_DIR="$WP_DIR/wp-data"
    if [ ! -d "$SITES_DIR" ]; then
        log_error "No se encontró el directorio de sitios ($SITES_DIR)."
        return 1
    fi

    local SITES=()
    while IFS= read -r -d '' site_path; do
        SITES+=("$(basename "$site_path")")
    done < <(find "$SITES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    if [ ${#SITES[@]} -eq 0 ]; then
        log_warn "No hay sitios WordPress instalados en este servidor."
        return 0
    fi

    echo -e "${C_CYAN}Selecciona el sitio WordPress:${C_RESET}"
    for i in "${!SITES[@]}"; do
        echo -e "  $((i+1))) ${SITES[$i]}"
    done

    read -r -p "Número de sitio [1-${#SITES[@]}]: " SITE_IDX
    if ! [[ "$SITE_IDX" =~ ^[0-9]+$ ]] || [ "$SITE_IDX" -lt 1 ] || [ "$SITE_IDX" -gt ${#SITES[@]} ]; then
        log_error "Selección inválida."
        return 1
    fi

    local CHOSEN_SLUG="${SITES[$((SITE_IDX-1))]}"
    local SITE_PATH="$SITES_DIR/$CHOSEN_SLUG"

    log_step "Buscando usuarios en '$CHOSEN_SLUG'..."
    if command -v wp >/dev/null 2>&1; then
        wp user list --path="$SITE_PATH" --allow-root --fields=ID,user_login,user_email,roles 2>/dev/null || true
    fi

    read -r -p "Escribe el nombre de usuario (user_login) a modificar [ej: admin]: " TARGET_USER
    if [ -z "$TARGET_USER" ]; then
        log_error "El usuario no puede estar vacío."
        return 1
    fi

    read -s -r -p "Escribe la NUEVA contraseña para '$TARGET_USER': " NEW_PASS1
    echo ""
    read -s -r -p "Confirma la NUEVA contraseña: " NEW_PASS2
    echo ""

    if [ -z "$NEW_PASS1" ] || [ "$NEW_PASS1" != "$NEW_PASS2" ]; then
        log_error "Las contraseñas no coinciden o están vacías."
        return 1
    fi

    # Actualizar mediante WP-CLI
    if command -v wp >/dev/null 2>&1; then
        if wp user update "$TARGET_USER" --user_pass="$NEW_PASS1" --path="$SITE_PATH" --allow-root >/dev/null 2>&1; then
            log_ok "¡Contraseña actualizada exitosamente para '$TARGET_USER' en '$CHOSEN_SLUG'!"
            return 0
        fi
    fi

    # Si WP-CLI falló, actualizar directamente en MariaDB
    log_info "Intentando actualización directa en la base de datos MariaDB..."
    local DB_NAME=""
    if [ -f "$SITE_PATH/wp-config.php" ]; then
        DB_NAME=$(grep "DB_NAME" "$SITE_PATH/wp-config.php" | head -n 1 | awk -F"'" '{print $4}' 2>/dev/null || true)
        local TABLE_PREFIX
        TABLE_PREFIX=$(grep "\$table_prefix" "$SITE_PATH/wp-config.php" | head -n 1 | awk -F"'" '{print $2}' 2>/dev/null || echo "wp_")
    fi

    if [ -n "$DB_NAME" ]; then
        docker exec -i mariadb mysql -u root -p"$DB_ROOT_PASSWORD" "$DB_NAME" -e \
            "UPDATE ${TABLE_PREFIX}users SET user_pass = MD5('${NEW_PASS1}') WHERE user_login = '${TARGET_USER}';" 2>/dev/null || true
        log_ok "¡Contraseña actualizada con hash MD5 en la base de datos '$DB_NAME'!"
    else
        log_error "No se pudo detectar el nombre de la base de datos de '$CHOSEN_SLUG'."
    fi
}

# Manejo de parámetros CLI
ACTION="${1:-menu}"
case "$ACTION" in
    start)
        start_pma "${2:-}"
        exit 0
        ;;
    stop)
        stop_pma
        exit 0
        ;;
    status)
        show_status
        exit 0
        ;;
    reset-pass|password)
        reset_wp_password
        exit 0
        ;;
    menu|"")
        ;;
    *)
        echo "Uso: $0 {start|stop|status|reset-pass}"
        exit 1
        ;;
esac

# Menú interactivo
while true; do
    show_banner
    log_section "GESTIÓN DE PHPMYADMIN Y BASES DE DATOS MARIADB"

    if is_pma_running; then
        echo -e "  Estado actual: ${C_BOLD}${C_GREEN}phpMyAdmin ACTIVO ✔${C_RESET} (Puerto: ${CURRENT_PMA_PORT})"
    else
        echo -e "  Estado actual: ${C_BOLD}${C_YELLOW}phpMyAdmin DETENIDO (Ahorrando memoria RAM) ⏹${C_RESET}"
    fi
    echo -e "${C_CYAN}================================================================${C_RESET}"
    echo -e "  1) 🚀 Iniciar / Activar phpMyAdmin (Elegir puerto y modo)"
    echo -e "  2) ⏹️  Detener phpMyAdmin (Cerrar puerto UFW y liberar RAM)"
    echo -e "  3) 🔑 Ver Estado y Credenciales de Acceso (Usuario root + contraseña)"
    echo -e "  4) ⚡ Cambiar Contraseña de Administrador WordPress (Sin entrar a SQL)"
    echo -e "  5) ↩️  Volver al menú principal"
    echo -e "${C_CYAN}================================================================${C_RESET}"

    read -r -p "Selecciona una opción [1-5]: " PMA_CHOICE

    case "$PMA_CHOICE" in
        1)
            start_pma
            read -r -p "Presiona ENTER para continuar..." _
            ;;
        2)
            stop_pma
            read -r -p "Presiona ENTER para continuar..." _
            ;;
        3)
            show_status
            read -r -p "Presiona ENTER para continuar..." _
            ;;
        4)
            reset_wp_password
            read -r -p "Presiona ENTER para continuar..." _
            ;;
        5|q|Q)
            exit 0
            ;;
        *)
            log_warn "Opción inválida."
            sleep 1
            ;;
    esac
done
