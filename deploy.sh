#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Master Deployment & Bootstrap Script
# ==============================================================================
set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source Core Libraries
source "${BASE_DIR}/core/banner.sh"
source "${BASE_DIR}/core/system.sh"
source "${BASE_DIR}/core/hardware.sh"
source "${BASE_DIR}/core/swap.sh"
source "${BASE_DIR}/core/ports.sh"

# Check root privilege
if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script debe ejecutarse como root.${C_RESET}"
    echo -e "Por favor, ejecuta: ${C_YELLOW}sudo -i${C_RESET} o ${C_YELLOW}sudo bash deploy.sh${C_RESET}"
    exit 1
fi

# Clear screen & show banner
clear 2>/dev/null || true
show_banner

log_section "INICIANDO INSTALACIÓN DEL STACK DE SERVIDOR"

# 1. Hardware Detection & Capacity Analysis
show_hardware_diagnostics

# 2. Swap Memory Check & Provisioning
if [ "$SWAP_TOTAL_MB" -lt 1024 ]; then
    log_warn "El servidor cuenta con poca o ninguna memoria Swap (${SWAP_TOTAL_MB} MB)."
    read -rp "¿Deseas crear un Escudo Swap de 2 GB para proteger la RAM ante picos de tráfico? [S/n]: " CREATE_SWAP
    CREATE_SWAP=${CREATE_SWAP:-S}
    if [[ "$CREATE_SWAP" =~ ^[Ss]$ ]]; then
        create_swap_shield 2
    fi
else
    log_ok "Memoria Swap adecuada detectada: ${SWAP_TOTAL_MB} MB."
fi

# 3. Base System & Docker Dependencies
check_os_compatibility
install_system_dependencies
install_docker_engine

# 4. Service Selection Menu
echo -e "\n${C_BOLD}${C_CYAN}¿Qué módulos deseas desplegar en este servidor?${C_RESET}"
echo -e "  ${C_BOLD}1)${C_RESET} Stack WordPress Completo (Nginx + PHP 8.4/8.5 + MariaDB + Redis)"
echo -e "  ${C_BOLD}2)${C_RESET} WireGuard VPN Server (Túnel seguro con UFW NAT)"
echo -e "  ${C_BOLD}3)${C_RESET} Suite Completa (WordPress + WireGuard)"
echo -e "  ${C_BOLD}4)${C_RESET} Cancelar instalación"
read -rp "Selecciona una opción [1-4, por defecto 3]: " STACK_CHOICE
STACK_CHOICE=${STACK_CHOICE:-3}

INSTALL_WP=false
INSTALL_WG=false

case "$STACK_CHOICE" in
    1) INSTALL_WP=true ;;
    2) INSTALL_WG=true ;;
    3) INSTALL_WP=true; INSTALL_WG=true ;;
    4)
        log_warn "Instalación cancelada por el usuario."
        exit 0
        ;;
    *)
        log_warn "Opción no válida. Instalando Suite Completa por defecto."
        INSTALL_WP=true
        INSTALL_WG=true
        ;;
esac

# 5. Deploy WordPress Stack
if [ "$INSTALL_WP" = true ]; then
    log_section "CONFIGURANDO STACK WORDPRESS ENTERPRISE"

    WP_DIR="${BASE_DIR}/modules/wordpress"
    cd "$WP_DIR"

    # Generate .env if not present
    if [ ! -f .env ]; then
        log_step "Generando credenciales criptográficas seguras en .env..."
        MYSQL_ROOT_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
        REDIS_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)

        cat << ENV_EOF > .env
COMPOSE_PROJECT_NAME=se2code_wp
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASS}
REDIS_PASSWORD=${REDIS_PASS}
ENV_EOF
        chmod 600 .env
        log_ok "Archivo .env creado con credenciales protegidas."
    fi

    # Create directories for runtime data and configs
    mkdir -p certs nginx/conf.d php/pools-84 php/pools-85 wp-data mariadb/data backups

    # Ensure placeholder pools exist
    touch php/pools-84/placeholder.conf php/pools-85/placeholder.conf

    # Allow HTTP / HTTPS on UFW if installed
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp comment "HTTP Web Traffic" >/dev/null 2>&1 || true
        ufw allow 443/tcp comment "HTTPS Web Traffic" >/dev/null 2>&1 || true
    fi

    log_step "Construyendo contenedores e inicializando servicios..."
    docker compose up -d --build

    # Install Global WP-CLI Wrapper
    log_step "Instalando comando global 'wp' (WP-CLI)..."
    cat << 'CLI_EOF' > /usr/local/bin/wp
#!/usr/bin/env bash
docker exec -i --user 33:33 wp-php84 wp --allow-root "$@" 2>/dev/null || docker exec -i --user 33:33 wp-php85 wp --allow-root "$@"
CLI_EOF
    chmod +x /usr/local/bin/wp
    log_ok "WP-CLI configurado globalmente en /usr/local/bin/wp"

    # Ask for initial sites
    echo -e "\n${C_BOLD}${C_CYAN}¿Deseas desplegar sitios WordPress en este momento?${C_RESET}"
    echo -e "  [0] = Solo dejar el stack base listo (podrás agregar sitios luego con 'se2code')"
    read -rp "Número de sitios a crear ahora [0-${MAX_SAFE_SITES}]: " SITES_COUNT
    SITES_COUNT=${SITES_COUNT:-0}

    if [[ "$SITES_COUNT" =~ ^[0-9]+$ ]] && [ "$SITES_COUNT" -gt 0 ]; then
        validate_site_capacity "$SITES_COUNT" >/dev/null 2>&1 || true
        for ((i=1; i<=SITES_COUNT; i++)); do
            log_section "CONFIGURANDO SITIO ${i} DE ${SITES_COUNT}"
            "${WP_DIR}/scripts/add-site.sh"
        done
    else
        log_info "No se crearon sitios iniciales. El stack está listo para recibir sitios con el comando 'se2code'."
    fi
fi

# 6. Deploy WireGuard Stack
if [ "$INSTALL_WG" = true ]; then
    log_section "CONFIGURANDO WIREGUARD VPN SERVER"
    "${BASE_DIR}/modules/wireguard/setup-vpn.sh"
fi

# 7. Install Global Management CLI
log_step "Instalando herramienta de gestión global 'se2code'..."
ln -sf "${BASE_DIR}/bin/se2code" /usr/local/bin/se2code
chmod +x /usr/local/bin/se2code
chmod +x "${BASE_DIR}/bin/se2code"
log_ok "Comando 'se2code' instalado con éxito en /usr/local/bin/se2code."

# 8. Summary & Final Instructions
echo -e "\n${C_GREEN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}          ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!                     ${C_RESET}"
echo -e "${C_GREEN}======================================================================${C_RESET}\n"

echo -e "Para administrar tu servidor en cualquier momento, ejecuta:"
echo -e "  ${C_BOLD}${C_YELLOW}se2code${C_RESET}\n"

echo -e "Acciones rápidas disponibles:"
echo -e "  » Agregar un nuevo sitio:        ${C_CYAN}se2code${C_RESET} -> Opción 1"
echo -e "  » Cambiar versión PHP (8.4/8.5):  ${C_CYAN}se2code${C_RESET} -> Opción 2"
echo -e "  » Generar backup granular:       ${C_CYAN}se2code${C_RESET} -> Opción 4"
echo -e "  » Ver QR WireGuard VPN:          ${C_CYAN}se2code${C_RESET} -> Opción 7"
echo -e "  » Monitoreo de hardware:         ${C_CYAN}se2code${C_RESET} -> Opción 9"
echo -e "  » Ejecutar WP-CLI directo:       ${C_CYAN}wp <comando>${C_RESET}\n"

log_ok "El servidor está 100% operativo y optimizado para producción."
