#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - One-Liner Web Installer (Estilo CyberPanel / Coolify)
# ==============================================================================
# Uso:
#   curl -sSL https://raw.githubusercontent.com/SE2-Coder/se2code-stack/main/install.sh | bash
#   o
#   bash <(curl -sSL https://raw.githubusercontent.com/SE2-Coder/se2code-stack/main/install.sh)
# ==============================================================================
set -e

# Reasignar stdin a /dev/tty para que los menús interactivos y 'read' funcionen
# perfectamente incluso cuando el usuario ejecuta 'curl ... | bash'
if [ ! -t 0 ]; then
    if [ -e /dev/tty ]; then
        exec < /dev/tty
    fi
fi

# Colores para la fase de pre-instalación
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

clear 2>/dev/null || true
echo -e "${C_CYAN}"
echo "   ======================================================================="
echo "                  ⚡ se2Code Stack Server - Auto-Installer                "
echo -e "           ${C_BOLD}${C_CYAN}🌐 Web:${C_RESET} ${C_YELLOW}https://se2code.com${C_RESET}  ${C_BOLD}|${C_RESET}  ${C_BOLD}${C_PURPLE}🛠️ Toolkit:${C_RESET} ${C_GREEN}https://se2code.engineer${C_RESET}    "
echo "   ======================================================================="
echo -e "${C_RESET}"

# 1. Comprobar privilegios de root
if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este instalador debe ejecutarse como root.${C_RESET}"
    echo -e "Por favor, ejecuta: ${C_YELLOW}sudo -i${C_RESET} o ${C_YELLOW}sudo bash install.sh${C_RESET}"
    exit 1
fi

# 2. Instalar dependencias mínimas para la descarga (git, curl, ca-certificates, tar)
echo -e "${C_CYAN}[1/3] Preparando dependencias básicas del sistema (git, curl, tar)...${C_RESET}"
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y git curl ca-certificates tar
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git curl ca-certificates tar
fi

# 3. Configuración del directorio de destino
INSTALL_DIR="/opt/se2code-stack"
REPO_URL="https://github.com/SE2-Coder/se2code-stack.git"
BRANCH="main"

echo -e "\n${C_CYAN}[2/3] Descargando la suite de infraestructura en ${INSTALL_DIR}...${C_RESET}"

if [ -d "${INSTALL_DIR}/.git" ]; then
    echo -e "${C_YELLOW}» Se detectó una instalación previa. Actualizando repositorio...${C_RESET}"
    cd "$INSTALL_DIR"
    git fetch origin "$BRANCH"
    git reset --hard "origin/${BRANCH}"
else
    mkdir -p /opt
    # Si la carpeta existe pero no es git, respaldarla
    if [ -d "$INSTALL_DIR" ]; then
        mv "$INSTALL_DIR" "${INSTALL_DIR}_backup_$(date +%s)"
    fi
    git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

# Asegurar permisos de ejecución en toda la suite
chmod +x "${INSTALL_DIR}/deploy.sh"
chmod +x "${INSTALL_DIR}/bin/se2code"
chmod +x "${INSTALL_DIR}/core/"*.sh
chmod +x "${INSTALL_DIR}/modules/wordpress/scripts/"*.sh
chmod +x "${INSTALL_DIR}/modules/wireguard/setup-vpn.sh"

echo -e "\n${C_GREEN}[3/3] Paquete descargado y configurado con éxito.${C_RESET}"
echo -e "${C_GREEN}» Iniciando asistente de despliegue interactivo...${C_RESET}\n"
sleep 1

# 4. Pasar el control a deploy.sh
cd "$INSTALL_DIR"
exec bash "${INSTALL_DIR}/deploy.sh"
