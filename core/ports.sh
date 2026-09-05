#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Core: Validador Dinámico de Puertos y Firewall
# ==============================================================================

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$CORE_DIR/banner.sh" ] && source "$CORE_DIR/banner.sh"

is_port_in_use() {
    local PORT=$1
    local PROTO=${2:-udp} # tcp o udp

    if command -v ss >/dev/null 2>&1; then
        if [ "$PROTO" = "udp" ]; then
            ss -uln | grep -q ":${PORT} "
        else
            ss -tln | grep -q ":${PORT} "
        fi
    elif command -v lsof >/dev/null 2>&1; then
        lsof -i "${PROTO}:${PORT}" >/dev/null 2>&1
    else
        return 1
    fi
}

ask_custom_port() {
    local SERVICE_NAME="$1"
    local DEFAULT_PORT="$2"
    local PROTO="${3:-udp}"

    while true; do
        echo -e "\n${C_BOLD}${C_CYAN}--- Configuración de Red: ${SERVICE_NAME} ---${C_RESET}" >&2
        echo -e "  - Rango seguro recomendado: ${C_GREEN}49152 a 65535${C_RESET} (Puertos dinámicos/privados)" >&2
        echo -e "  - Puerto sugerido por defecto: ${C_BOLD}${C_CYAN}${DEFAULT_PORT}${C_RESET}" >&2
        read -r -p "Escribe el puerto deseado [Enter para ${DEFAULT_PORT}]: " INPUT_PORT

        CHOSEN_PORT="${INPUT_PORT:-$DEFAULT_PORT}"

        # Validar que sea un número entero
        if ! [[ "$CHOSEN_PORT" =~ ^[0-9]+$ ]]; then
            log_error "El puerto debe ser un valor numérico entero." >&2
            continue
        fi

        # Validar rango
        if [ "$CHOSEN_PORT" -lt 1024 ] || [ "$CHOSEN_PORT" -gt 65535 ]; then
            log_error "El puerto debe estar en el rango de 1024 a 65535." >&2
            continue
        fi

        # Validar si ya está en uso
        if is_port_in_use "$CHOSEN_PORT" "$PROTO"; then
            log_error "El puerto ${CHOSEN_PORT}/${PROTO} ya está ocupado por otro servicio en este servidor." >&2
            continue
        fi

        log_ok "Puerto ${CHOSEN_PORT}/${PROTO} disponible y verificado." >&2

        # Abrir en UFW automáticamente si existe
        if command -v ufw >/dev/null 2>&1; then
            sudo ufw allow "${CHOSEN_PORT}/${PROTO}" comment "se2Code ${SERVICE_NAME}" >/dev/null 2>&1 || true
            log_ok "Regla UFW añadida para ${CHOSEN_PORT}/${PROTO}." >&2
        fi

        echo "$CHOSEN_PORT"
        return 0
    done
}
