#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Core: Instalador de Sistema, Docker y Dependencias
# ==============================================================================

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$CORE_DIR/banner.sh" ] && source "$CORE_DIR/banner.sh"

check_os_compatibility() {
    log_step "Verificando compatibilidad del Sistema Operativo..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VER="$VERSION_ID"
        log_info "Detectado: $NAME ($VERSION)"
        case "$OS_ID" in
            debian)
                if [ "$OS_VER" = "12" ] || [ "$OS_VER" = "13" ]; then
                    log_ok "Sistema Operativo compatible y certificado oficialmente (Debian $OS_VER)."
                else
                    log_warn "Debian $OS_VER detectado. Este stack ha sido testeado y certificado oficialmente ÚNICAMENTE en Debian 12 y Debian 13."
                    log_warn "Continuando bajo su propia discreción..."
                fi
                ;;
            *)
                log_warn "Distribución no testeada oficialmente ($OS_ID / $NAME)."
                log_warn "Este stack ha sido diseñado, probado y soportado oficialmente ÚNICAMENTE para Debian 12 y Debian 13."
                log_warn "El uso en otras distribuciones es experimental. Intentando continuar..."
                ;;
        esac
    else
        log_warn "No se pudo leer /etc/os-release. Continuando..."
    fi
}

install_system_dependencies() {
    log_step "Instalando paquetes y dependencias esenciales..."
    export DEBIAN_FRONTEND=noninteractive
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y \
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
            net-tools
    fi
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
    curl -fsSL https://get.docker.com | sh

    systemctl enable --now docker >/dev/null 2>&1 || true

    # Agregar el usuario actual al grupo docker si no es root
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker "$SUDO_USER" >/dev/null 2>&1 || true
    fi

    log_ok "Docker Engine y Docker Compose instalados y activos."
}
