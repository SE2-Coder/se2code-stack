#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Core: Escudo de Swap Automático
# ==============================================================================

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$CORE_DIR/banner.sh" ] && source "$CORE_DIR/banner.sh"

create_swap_shield() {
    local SWAP_SIZE_GB="${1:-2}"
    log_step "Configurando Escudo de Swap (+${SWAP_SIZE_GB} GB de Memoria Virtual)..."

    # Verificar si ya existe Swap activa
    CURRENT_SWAP_MB=$(free -m 2>/dev/null | awk '/Swap:/ {print $2}' || echo "0")
    if [ "$CURRENT_SWAP_MB" -gt 1024 ]; then
        log_ok "Memoria Swap suficiente detectada (${CURRENT_SWAP_MB} MB). No es necesario crear más."
        return 0
    fi

    # Verificar permisos de root
    if [ "$EUID" -ne 0 ]; then
        log_warn "Se requieren privilegios sudo para configurar la memoria Swap."
        SUDO_CMD="sudo"
    else
        SUDO_CMD=""
    fi

    # 1. Crear el archivo Swap
    if [ -f /swapfile ]; then
        $SUDO_CMD swapoff /swapfile 2>/dev/null || true
        $SUDO_CMD rm -f /swapfile
    fi

    log_info "Reservando espacio en disco para /swapfile (${SWAP_SIZE_GB}G)..."
    if command -v fallocate >/dev/null 2>&1; then
        $SUDO_CMD fallocate -l "${SWAP_SIZE_GB}G" /swapfile 2>/dev/null || \
        $SUDO_CMD dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
    else
        $SUDO_CMD dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
    fi

    # 2. Asignar permisos estrictos
    $SUDO_CMD chmod 600 /swapfile

    # 3. Formatear y activar
    $SUDO_CMD mkswap /swapfile
    $SUDO_CMD swapon /swapfile

    # 4. Persistencia en /etc/fstab
    if ! grep -q "/swapfile" /etc/fstab 2>/dev/null; then
        echo "/swapfile none swap sw 0 0" | $SUDO_CMD tee -a /etc/fstab >/dev/null
        log_ok "Swap añadida a /etc/fstab para inicio automático en cada reboot."
    fi

    # 5. Optimización del Kernel (swappiness=10 para usar RAM primero)
    echo "vm.swappiness=10" | $SUDO_CMD tee /etc/sysctl.d/99-se2code-swap.conf >/dev/null
    echo "vm.vfs_cache_pressure=50" | $SUDO_CMD tee -a /etc/sysctl.d/99-se2code-swap.conf >/dev/null
    $SUDO_CMD sysctl --system >/dev/null 2>&1 || true

    log_ok "Escudo de Swap de ${SWAP_SIZE_GB} GB activado y optimizado (swappiness=10)."
}
