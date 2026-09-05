#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Core: Hardware Profiler & Sizing Advisor
# ==============================================================================

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$CORE_DIR/banner.sh" ] && source "$CORE_DIR/banner.sh"

get_hardware_specs() {
    # 1. Detección de CPU Cores
    if command -v nproc >/dev/null 2>&1; then
        CPU_CORES=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
    else
        CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "1")
    fi

    # 2. Detección de Memoria RAM (en MB)
    if [ -f /proc/meminfo ]; then
        RAM_TOTAL_MB=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
        RAM_FREE_MB=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
        SWAP_TOTAL_MB=$(awk '/SwapTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS fallback para desarrollo local
        RAM_TOTAL_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "1073741824")
        RAM_TOTAL_MB=$((RAM_TOTAL_BYTES / 1024 / 1024))
        RAM_FREE_MB=$((RAM_TOTAL_MB / 2))
        SWAP_TOTAL_MB=1024
    else
        RAM_TOTAL_MB=1024
        RAM_FREE_MB=512
        SWAP_TOTAL_MB=0
    fi

    # 3. Detección de Espacio en Disco (en GB)
    DISK_FREE_GB=$(df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo "10")

    # 4. Cálculo de Capacidad de Sitios
    # Base Stack (NGINX + MariaDB + Redis + OS) consume ~450 MB
    BASE_STACK_MB=450
    SITE_COST_MB=200

    if [ "$RAM_TOTAL_MB" -le "$BASE_STACK_MB" ]; then
        MAX_SAFE_SITES=1
    else
        AVAIL_FOR_SITES=$((RAM_TOTAL_MB - BASE_STACK_MB))
        MAX_SAFE_SITES=$((AVAIL_FOR_SITES / SITE_COST_MB))
        if [ "$MAX_SAFE_SITES" -lt 1 ]; then
            MAX_SAFE_SITES=1
        fi
    fi
    return 0
}

show_hardware_diagnostics() {
    get_hardware_specs

    RAM_TOTAL_GB=$(awk -v m="$RAM_TOTAL_MB" 'BEGIN {printf "%.1f", m/1024}')
    RAM_FREE_GB=$(awk -v m="$RAM_FREE_MB" 'BEGIN {printf "%.1f", m/1024}')
    SWAP_TOTAL_GB=$(awk -v m="$SWAP_TOTAL_MB" 'BEGIN {printf "%.1f", m/1024}')

    echo -e "${C_CYAN}================================================================${C_RESET}"
    echo -e "  ${C_BOLD}📊 se2Code Stack: DIAGNÓSTICO DE CAPACIDAD DE HARDWARE${C_RESET}"
    echo -e "${C_CYAN}================================================================${C_RESET}"
    echo -e "  ${C_BOLD}CPU Cores${C_RESET}       : ${C_CYAN}${CPU_CORES} Core(s)${C_RESET}"
    echo -e "  ${C_BOLD}Memoria RAM${C_RESET}     : ${C_GREEN}${RAM_TOTAL_GB} GB Total${C_RESET} (${RAM_FREE_GB} GB disponible)"
    
    if [ "$SWAP_TOTAL_MB" -lt 512 ]; then
        echo -e "  ${C_BOLD}Memoria Swap${C_RESET}    : ${C_YELLOW}${SWAP_TOTAL_GB} GB (${C_RED}Inexistente o baja ⚠️${C_RESET})"
    else
        echo -e "  ${C_BOLD}Memoria Swap${C_RESET}    : ${C_GREEN}${SWAP_TOTAL_GB} GB Activa ✔${C_RESET}"
    fi

    echo -e "  ${C_BOLD}Disco Raíz${C_RESET}      : ${C_CYAN}${DISK_FREE_GB} GB Libres${C_RESET}"
    echo -e "${C_GRAY}----------------------------------------------------------------${C_RESET}"
    echo -e "  ${C_BOLD}Consumo Base del Stack (NGINX+DB+Redis+SO)${C_RESET} : ~${BASE_STACK_MB} MB RAM"
    echo -e "  ${C_BOLD}Capacidad Máxima Recomendada${C_RESET}              : ${C_BOLD}${C_GREEN}${MAX_SAFE_SITES} Sitio(s) WordPress${C_RESET}"
    echo -e "${C_CYAN}================================================================${C_RESET}\n"
    return 0
}

validate_site_capacity() {
    local REQUESTED=$1
    get_hardware_specs

    if [ "$REQUESTED" -gt "$MAX_SAFE_SITES" ]; then
        echo -e "\n${C_BOLD}${C_YELLOW}⚠️  [ALERTA DE SOBRECARGA DE HARDWARE]${C_RESET}"
        echo -e "${C_GRAY}----------------------------------------------------------------${C_RESET}"
        echo -e "  Has solicitado aprovisionar : ${C_BOLD}${C_RED}${REQUESTED} Sitios WordPress${C_RESET}"
        echo -e "  Capacidad segura recomendada: ${C_BOLD}${C_GREEN}${MAX_SAFE_SITES} Sitio(s) WordPress${C_RESET}"
        echo -e "\n  ${C_BOLD}¿Por qué es peligroso?${C_RESET}"
        echo -e "  Cada sitio con PHP 8.5 y Elementor requiere ~150-200 MB de RAM."
        echo -e "  ${REQUESTED} Sitios + MariaDB + NGINX demandarán aproximadamente:"
        ESTIMATED_NEEDED=$(( BASE_STACK_MB + (REQUESTED * SITE_COST_MB) ))
        echo -e "  ${C_RED}~${ESTIMATED_NEEDED} MB de RAM.${C_RESET} Tu servidor solo cuenta con ${C_BOLD}${RAM_TOTAL_MB} MB físico.${C_RESET}"
        echo -e "\n  ${C_BOLD}Consecuencia si continúas:${C_RESET}"
        echo -e "  El sistema operativo activará el 'Out-Of-Memory Killer' (OOM) y apagará"
        echo -e "  arbitrariamente MariaDB o NGINX, dejando tus páginas caídas."
        echo -e "${C_GRAY}----------------------------------------------------------------${C_RESET}"

        echo -e "\n${C_BOLD}[?] ¿Cómo deseas proceder?${C_RESET}"
        echo -e "    1) Ajustar la cantidad a lo recomendado (${MAX_SAFE_SITES} Sitio)"
        echo -e "    2) Activar 'Escudo Swap' (+2 GB de memoria virtual en disco) y continuar"
        echo -e "    3) Cancelar y mejorar el plan de VPS"
        echo -e "    4) Continuar bajo mi propio riesgo"
        read -r -p "Tu elección [1-4]: " CAPACITY_CHOICE

        case "$CAPACITY_CHOICE" in
            1)
                echo "$MAX_SAFE_SITES"
                return 0
                ;;
            2)
                if [ -f "$CORE_DIR/swap.sh" ]; then
                    source "$CORE_DIR/swap.sh"
                    create_swap_shield 2
                fi
                echo "$REQUESTED"
                return 0
                ;;
            3)
                log_error "Instalación cancelada por el usuario para escalar el VPS."
                exit 1
                ;;
            *)
                log_warn "Continuando bajo riesgo del usuario con $REQUESTED sitios."
                echo "$REQUESTED"
                return 0
                ;;
        esac
    fi
    echo "$REQUESTED"
    return 0
}
