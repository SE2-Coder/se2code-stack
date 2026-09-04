#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Core: Instalador de Sistema, Docker y Dependencias
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/banner.sh" ] && source "$SCRIPT_DIR/banner.sh"

check_os_compatibility() {
    log_step "Verificando compatibilidad del Sistema Operativo..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VER="$VERSION_ID"
        log_info "Detectado: $NAME ($VERSION)"
        case "$OS_ID" in
            debian)
                if [ "$OS_VER" -lt 12 ]; then
                    log_warn "Se recomienda Debian 12 (Bookworm) o Debian 13 (Trixie). Tu versión es $OS_VER."
                else
                    log_ok "Sistema Operativo 100% compatible (Debian $OS_VER)."
                fi
                ;;
            ubuntu)
                log_ok "Sistema Operativo compatible (Ubuntu $OS_VER)."
                ;;
            *)
                log_warn "Distribución no testeada oficialmente ($OS_ID). Intentando continuar..."
                ;;
        esac
    else
        log_warn "No se pudo leer /etc/os-release. Continuando..."
    fi
}

install_system_dependencies() {
    log_step "Instalando paquetes y dependencias esenciales..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        jq \
        ufw \
        qrencode \
        tar \
        gzip \
        openssl \
        procps \
        net-tools >/dev/null 2>&1
    log_ok "Dependencias del sistema instaladas correctamente."
}

install_docker_engine() {
    log_step "Verificando instalación de Docker y Docker Compose..."
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
        COMPOSE_VER=$(docker compose version | awk '{print $4}')
        log_ok "Docker ($DOCKER_VER) y Docker Compose ($COMPOSE_VER) ya están instalados."
        return 0
    fi

    log_info "Docker no detectado. Instalando Docker Engine oficial..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/debian/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1

    sudo systemctl enable --now docker >/dev/null 2>&1 || true
    
    # Agregar el usuario actual al grupo docker si no es root
    if [ -n "$SUDO_USER" ]; then
        sudo usermod -aG docker "$SUDO_USER" >/dev/null 2>&1 || true
    fi

    log_ok "Docker Engine y Docker Compose v2 instalados y activos."
}
