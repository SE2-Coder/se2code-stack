#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Core: Banner y Estilos
# ==============================================================================

# Colores ANSI profesionales (Degradados Cian / Neón / Alertas)
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[38;5;51m"
C_BLUE="\033[38;5;39m"
C_GREEN="\033[38;5;48m"
C_YELLOW="\033[38;5;220m"
C_RED="\033[38;5;196m"
C_PURPLE="\033[38;5;141m"
C_GRAY="\033[38;5;245m"

show_banner() {
    clear 2>/dev/null || true
    echo -e "${C_CYAN}"
    cat << 'BANNER_EOF'
  ███████╗███████╗██████╗  ██████╗ ██████╗ ██████╗ ███████╗
  ██╔════╝██╔════╝╚════██╗██╔════╝██╔═══██╗██╔══██╗██╔════╝
  ███████╗█████╗   █████╔╝██║     ██║   ██║██║  ██║█████╗  
  ╚════██║██╔══╝  ██╔═══╝ ██║     ██║   ██║██║  ██║██╔══╝  
  ███████║███████╗███████╗╚██████╗╚██████╔╝██████╔╝███████╗
  ╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝
BANNER_EOF
    echo -e "${C_BOLD}${C_BLUE}           S E R V E R   D E V O P S   S T A C K${C_RESET}"
    echo -e "${C_GRAY}        Plataforma Modular de Alta Disponibilidad y Rendimiento${C_RESET}"
    echo -e "${C_CYAN}================================================================${C_RESET}"
}

log_info()    { echo -e "  ${C_BLUE}ℹ${C_RESET}  $1"; }
log_ok()      { echo -e "  ${C_GREEN}✔${C_RESET}  ${C_BOLD}$1${C_RESET}"; }
log_warn()    { echo -e "  ${C_YELLOW}⚠${C_RESET}  ${C_YELLOW}$1${C_RESET}"; }
log_error()   { echo -e "  ${C_RED}✖${C_RESET}  ${C_BOLD}${C_RED}$1${C_RESET}"; }
log_step()    { echo -e "\n${C_BOLD}${C_CYAN}──▶ $1${C_RESET}"; }
log_section() {
    echo -e "\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "  ${C_BOLD}${C_PURPLE}$1${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
}
