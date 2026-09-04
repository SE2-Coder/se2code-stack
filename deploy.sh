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
check_root

# Clear screen & show banner
clear
show_banner

echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}${WHITE}             INICIANDO INSTALACIÓN DEL STACK DE SERVIDOR              ${NC}"
echo -e "${CYAN}======================================================================${NC}\n"

# 1. Hardware Detection & Capacity Analysis
print_step "Analizando especificaciones de hardware..."
profile_hardware

echo -e "\n${BOLD}${WHITE}Sugerencia de capacidad:${NC}"
echo -e "  » ${GREEN}${MAX_SAFE_SITES} sitios WordPress optimizados${NC} simultáneos con tráfico moderado."
echo -e "  » Capacidad estimada en tráfico alto: ${YELLOW}${MAX_HEAVY_SITES} sitios${NC}.\n"

# 2. Swap Memory Check & Provisioning
if [ "$SWAP_MB" -lt 1024 ]; then
    print_warn "El servidor cuenta con menos de 1 GB de Swap (${SWAP_MB} MB)."
    read -rp "¿Deseas crear un archivo Swap de 2 GB para proteger la RAM ante picos de tráfico? [S/n]: " CREATE_SWAP
    CREATE_SWAP=${CREATE_SWAP:-S}
    if [[ "$CREATE_SWAP" =~ ^[Ss]$ ]]; then
        setup_swap 2048
    fi
else
    print_success "Swap suficiente detectado: ${SWAP_MB} MB."
fi

# 3. Base System & Docker Dependencies
print_step "Verificando dependencias del sistema y Docker Engine..."
check_os
install_prerequisites
configure_ufw_base

# 4. Service Selection Menu
echo -e "\n${BOLD}${CYAN}¿Qué módulos deseas desplegar en este servidor?${NC}"
echo -e "  ${BOLD}1)${NC} Stack WordPress Completo (Nginx + PHP 8.4/8.5 + MariaDB + Redis)"
echo -e "  ${BOLD}2)${NC} WireGuard VPN Server (Túnel seguro con UFW NAT)"
echo -e "  ${BOLD}3)${NC} Suite Completa (WordPress + WireGuard)"
echo -e "  ${BOLD}4)${NC} Cancelar instalación"
read -rp "Selecciona una opción [1-4, por defecto 3]: " STACK_CHOICE
STACK_CHOICE=${STACK_CHOICE:-3}

INSTALL_WP=false
INSTALL_WG=false

case "$STACK_CHOICE" in
    1) INSTALL_WP=true ;;
    2) INSTALL_WG=true ;;
    3) INSTALL_WP=true; INSTALL_WG=true ;;
    4)
        print_warn "Instalación cancelada por el usuario."
        exit 0
        ;;
    *)
        print_warn "Opción no válida. Instalando Suite Completa por defecto."
        INSTALL_WP=true
        INSTALL_WG=true
        ;;
esac

# 5. Deploy WordPress Stack
if [ "$INSTALL_WP" = true ]; then
    echo -e "\n${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}${WHITE}              CONFIGURANDO STACK WORDPRESS ENTERPRISE                 ${NC}"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}\n"

    WP_DIR="${BASE_DIR}/modules/wordpress"
    cd "$WP_DIR"

    # Generate .env if not present
    if [ ! -f .env ]; then
        print_step "Generando credenciales criptográficas seguras en .env..."
        MYSQL_ROOT_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
        REDIS_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)

        cat << ENV_EOF > .env
COMPOSE_PROJECT_NAME=se2code_wp
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASS}
REDIS_PASSWORD=${REDIS_PASS}
ENV_EOF
        chmod 600 .env
        print_success "Archivo .env creado con credenciales protegidas."
    fi

    # Create directories for runtime data and configs
    mkdir -p certs nginx/conf.d php/pools-84 php/pools-85 wp-data mariadb/data backups

    # Ensure placeholder pools exist
    touch php/pools-84/placeholder.conf php/pools-85/placeholder.conf

    # Allow HTTP / HTTPS on UFW
    ufw allow 80/tcp comment "HTTP Web Traffic" >/dev/null 2>&1 || true
    ufw allow 443/tcp comment "HTTPS Web Traffic" >/dev/null 2>&1 || true

    print_step "Construyendo contenedores e inicializando servicios..."
    docker compose up -d --build

    # Install Global WP-CLI Wrapper
    print_step "Instalando comando global 'wp' (WP-CLI)..."
    cat << 'CLI_EOF' > /usr/local/bin/wp
#!/usr/bin/env bash
docker exec -i --user 33:33 se2code_php84 wp --allow-root "$@"
CLI_EOF
    chmod +x /usr/local/bin/wp
    print_success "WP-CLI configurado globalmente en /usr/local/bin/wp"

    # Ask for initial sites
    echo -e "\n${BOLD}${CYAN}¿Deseas desplegar sitios WordPress en este momento?${NC}"
    echo -e "  [0] = Solo dejar el stack base listo (podrás agregar sitios luego con 'se2code')"
    read -rp "Número de sitios a crear ahora [0-${MAX_SAFE_SITES}]: " SITES_COUNT
    SITES_COUNT=${SITES_COUNT:-0}

    if [[ "$SITES_COUNT" =~ ^[0-9]+$ ]] && [ "$SITES_COUNT" -gt 0 ]; then
        validate_capacity "$SITES_COUNT"
        for ((i=1; i<=SITES_COUNT; i++)); do
            echo -e "\n${CYAN}======================================================================${NC}"
            echo -e "${BOLD}${WHITE}      CONFIGURANDO SITIO ${i} DE ${SITES_COUNT}                        ${NC}"
            echo -e "${CYAN}======================================================================${NC}"
            "${WP_DIR}/scripts/add-site.sh"
        done
    else
        print_info "No se crearon sitios iniciales. El stack está listo para recibir sitios con el comando 'se2code'."
    fi
fi

# 6. Deploy WireGuard Stack
if [ "$INSTALL_WG" = true ]; then
    echo -e "\n${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}${WHITE}                 CONFIGURANDO WIREGUARD VPN SERVER                    ${NC}"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}\n"
    "${BASE_DIR}/modules/wireguard/setup-vpn.sh"
fi

# 7. Install Global Management CLI
print_step "Instalando herramienta de gestión global 'se2code'..."
ln -sf "${BASE_DIR}/bin/se2code" /usr/local/bin/se2code
chmod +x /usr/local/bin/se2code
chmod +x "${BASE_DIR}/bin/se2code"
print_success "Comando 'se2code' instalado con éxito en /usr/local/bin/se2code."

# 8. Summary & Final Instructions
echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${BOLD}${GREEN}          ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!                     ${NC}"
echo -e "${GREEN}======================================================================${NC}\n"

echo -e "Para administrar tu servidor en cualquier momento, ejecuta:"
echo -e "  ${BOLD}${YELLOW}se2code${NC}\n"

echo -e "Acciones rápidas disponibles:"
echo -e "  » Agregar un nuevo sitio:       ${CYAN}se2code${NC} -> Opción 1"
echo -e "  » Cambiar versión PHP (8.4/8.5): ${CYAN}se2code${NC} -> Opción 2"
echo -e "  » Generar backup granular:      ${CYAN}se2code${NC} -> Opción 4"
echo -e "  » Ver QR WireGuard VPN:         ${CYAN}se2code${NC} -> Opción 7"
echo -e "  » Monitoreo de hardware:        ${CYAN}se2code${NC} -> Opción 9"
echo -e "  » Ejecutar WP-CLI directo:      ${CYAN}wp <comando>${NC}\n"

print_success "El servidor está 100% operativo y optimizado para producción."
