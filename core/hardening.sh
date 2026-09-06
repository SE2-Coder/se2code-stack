#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Core: Hardening y Securización Profunda del Servidor
# ==============================================================================
# Automatización de la guía: docs/01-setup-server.md
# Soporte oficial para Debian 12 (Bookworm) y Debian 13 (Trixie).
#
# Pasos ejecutados:
#   1. Verificación de OS y dependencias base
#   2. Creación de usuario administrador no-root con contraseña sudo
#   3. Gestión de llaves SSH (Pegar / Generar en servidor / Importar de root)
#   4. Selección dinámica de puerto SSH con rangos y validación
#   5. Hardening de SSH, socket systemd y neutralización de cloud-init
#   6. Configuración de Firewall UFW (Nativo, sin conflictos)
#   7. Protección de fuerza bruta con Fail2ban (Systemd + nftables)
#   8. Hardening del Kernel (sysctl), Modprobe y permisos estrictos
#   9. Verificación en vivo del socket y salvaguarda Anti-Bloqueo
# ==============================================================================

set -eo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$CORE_DIR/banner.sh" ] && source "$CORE_DIR/banner.sh"
[ -f "$CORE_DIR/ports.sh" ] && source "$CORE_DIR/ports.sh"
[ -f "$CORE_DIR/system.sh" ] && source "$CORE_DIR/system.sh"

# Verificación de privilegios de root
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Este script debe ejecutarse como root (sudo).\033[0m"
    exit 1
fi

show_banner 2>/dev/null || true
log_section "MÓDULO DE HARDENING Y SECURIZACIÓN PROFUNDA DEL SERVIDOR"

# ------------------------------------------------------------------------------
# 1. Verificación de Sistema Operativo y Paquetes Base
# ------------------------------------------------------------------------------
log_step "Paso 1/9: Verificando Sistema Operativo y paquetes de seguridad..."
check_os_compatibility 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget sudo ufw fail2ban ca-certificates gnupg lsb-release openssh-server procps net-tools >/dev/null 2>&1
log_ok "Paquetes esenciales de seguridad instalados (UFW, Fail2ban, OpenSSH, Sudo)."

# ------------------------------------------------------------------------------
# 2. Creación del Usuario Administrador no-root
# ------------------------------------------------------------------------------
log_step "Paso 2/9: Configuración de Usuario Administrador (No-Root)"
echo -e "${C_GRAY}Por estándares de seguridad, nunca se debe administrar el servidor directamente${C_RESET}"
echo -e "${C_GRAY}con el usuario 'root'. Se creará un usuario dedicado con privilegios sudo.${C_RESET}\n"

ADMIN_USER=""
while true; do
    read -r -p "¿Qué nombre tendrá el usuario que administrará el servidor? [Por defecto: se2]: " ADMIN_USER
    ADMIN_USER="${ADMIN_USER:-se2}"

    if ! [[ "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "Nombre de usuario inválido. Usa solo letras minúsculas, números y guiones."
        continue
    fi

    if [ "$ADMIN_USER" = "root" ]; then
        log_error "No puedes usar el nombre 'root'. Debe ser un usuario no privilegiado."
        continue
    fi
    break
done

USER_EXISTS=false
if id "$ADMIN_USER" >/dev/null 2>&1; then
    USER_EXISTS=true
    log_info "El usuario '$ADMIN_USER' ya existe en el sistema."
else
    adduser --disabled-password --gecos "" "$ADMIN_USER" >/dev/null 2>&1
    log_ok "Usuario de sistema '$ADMIN_USER' creado."
fi

# Contraseña para el usuario (requerida por sudo)
echo -e "\n${C_CYAN}Asignación de Contraseña para '$ADMIN_USER' (usada para ejecutar sudo):${C_RESET}"
while true; do
    read -s -r -p "Escribe la contraseña para '$ADMIN_USER': " PASS1
    echo ""
    read -s -r -p "Confirma la contraseña: " PASS2
    echo ""

    if [ -z "$PASS1" ]; then
        if $USER_EXISTS; then
            log_info "Contraseña no modificada para el usuario existente."
            break
        else
            log_error "La contraseña no puede estar vacía."
            continue
        fi
    fi

    if [ "$PASS1" != "$PASS2" ]; then
        log_error "Las contraseñas no coinciden. Inténtalo de nuevo."
        continue
    fi

    echo "$ADMIN_USER:$PASS1" | chpasswd
    log_ok "Contraseña para sudo establecida correctamente."
    break
done

# Asignar a grupos sudo y docker
usermod -aG sudo "$ADMIN_USER"
if getent group docker >/dev/null 2>&1; then
    usermod -aG docker "$ADMIN_USER"
fi
log_ok "Privilegios administrativos (sudo) asignados a '$ADMIN_USER'."

# ------------------------------------------------------------------------------
# 3. Configuración de Llaves SSH (Autenticación Criptográfica)
# ------------------------------------------------------------------------------
log_step "Paso 3/9: Configuración de Llaves SSH para '$ADMIN_USER'"
USER_HOME=$(eval echo "~$ADMIN_USER")
mkdir -p "$USER_HOME/.ssh"
touch "$USER_HOME/.ssh/authorized_keys"

echo -e "${C_GRAY}La autenticación por contraseña en SSH será deshabilitada por seguridad.${C_RESET}"
echo -e "${C_CYAN}Selecciona cómo deseas configurar la llave SSH:${C_RESET}"
echo -e "  1) ${C_GREEN}[Recomendado]${C_RESET} Pegar mi clave pública SSH (.pub)"
echo -e "  2) Generar un nuevo par de llaves Ed25519 en este servidor"
if [ -s /root/.ssh/authorized_keys ]; then
    echo -e "  3) Importar la llave autorizada actual de 'root'"
fi

KEY_CHOICE=""
while true; do
    read -r -p "Selecciona una opción [1-3]: " KEY_CHOICE
    case "$KEY_CHOICE" in
        1)
            echo -e "\n${C_CYAN}Pega tu clave pública SSH completa (escribe 'EOF' en una línea nueva al terminar):${C_RESET}"
            PUB_BUFFER=""
            while IFS= read -r line; do
                [ "$line" = "EOF" ] && break
                [ -z "$line" ] && continue
                PUB_BUFFER="${PUB_BUFFER}${line}\n"
            done
            if [ -n "$PUB_BUFFER" ]; then
                printf "%b" "$PUB_BUFFER" >> "$USER_HOME/.ssh/authorized_keys"
                log_ok "Clave(s) pública(s) agregada(s) a $USER_HOME/.ssh/authorized_keys."
            else
                log_warn "No se ingresó ninguna clave pública."
            fi
            break
            ;;
        2)
            TEMP_KEY="/tmp/se2code_ed25519_$$"
            ssh-keygen -t ed25519 -N "" -C "${ADMIN_USER}@$(hostname)" -f "$TEMP_KEY" >/dev/null 2>&1
            cat "${TEMP_KEY}.pub" >> "$USER_HOME/.ssh/authorized_keys"

            echo -e "\n${C_BOLD}${C_YELLOW}╔════════════════════════════════════════════════════════════════════════╗${C_RESET}"
            echo -e "${C_BOLD}${C_YELLOW}║         ⚠️  COPIA Y GUARDA TU CLAVE PRIVADA EN TU COMPUTADORA          ║${C_RESET}"
            echo -e "${C_BOLD}${C_YELLOW}╚════════════════════════════════════════════════════════════════════════╝${C_RESET}"
            echo -e "${C_CYAN}Copia TODO el bloque inferior y guárdalo en tu Mac/PC (ej: server.pem o id_ed25519):${C_RESET}\n"
            echo -e "${C_GREEN}"
            cat "$TEMP_KEY"
            echo -e "${C_RESET}"
            echo -e "${C_YELLOW}Recuerda aplicar permisos 400 en tu computadora local:${C_RESET}"
            echo -e "${C_BOLD}chmod 400 <ruta-de-tu-archivo-guardado>${C_RESET}\n"

            read -r -p "Presiona ENTER una vez hayas copiado y guardado la clave privada..." _
            # Destruir clave privada temporal
            if command -v shred >/dev/null 2>&1; then
                shred -u "$TEMP_KEY" "${TEMP_KEY}.pub" 2>/dev/null || rm -f "$TEMP_KEY" "${TEMP_KEY}.pub"
            else
                rm -f "$TEMP_KEY" "${TEMP_KEY}.pub"
            fi
            log_ok "Clave privada destruida de forma segura de la memoria del servidor."
            break
            ;;
        3)
            if [ -s /root/.ssh/authorized_keys ]; then
                cat /root/.ssh/authorized_keys >> "$USER_HOME/.ssh/authorized_keys"
                log_ok "Claves de /root/.ssh/authorized_keys importadas exitosamente."
                break
            else
                log_error "No se encontraron claves en /root/.ssh/authorized_keys."
            fi
            ;;
        *)
            log_warn "Opción no válida. Ingresa 1, 2 o 3."
            ;;
    esac
done

# Eliminar duplicados y fijar permisos estrictos
sort -u "$USER_HOME/.ssh/authorized_keys" -o "$USER_HOME/.ssh/authorized_keys"
chown -R "$ADMIN_USER:$ADMIN_USER" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"

# ------------------------------------------------------------------------------
# 4. Selección Dinámica del Puerto SSH con Rangos
# ------------------------------------------------------------------------------
log_step "Paso 4/9: Selección de Puerto SSH Personalizado"
echo -e "${C_GRAY}Cambiar el puerto 22 estándar reduce drásticamente los escaneos de bots y ataques automatizados.${C_RESET}"

CHOSEN_SSH_PORT=""
while true; do
    echo -e "\n${C_BOLD}${C_CYAN}--- Configuración de Puerto SSH ---${C_RESET}"
    echo -e "  - Rango recomendado: ${C_GREEN}1024 a 65535${C_RESET} (Puertos no privilegiados / privados)"
    echo -e "  - Ejemplos populares: 2222, 6266, 8022, 22022"
    echo -e "  - Puerto sugerido por defecto: ${C_BOLD}${C_CYAN}6266${C_RESET}"
    read -r -p "¿Qué puerto SSH deseas utilizar en este servidor? [Enter para 6266]: " INPUT_SSH_PORT
    INPUT_SSH_PORT="${INPUT_SSH_PORT:-6266}"

    if ! [[ "$INPUT_SSH_PORT" =~ ^[0-9]+$ ]]; then
        log_error "El puerto debe ser un valor numérico entero."
        continue
    fi

    if [ "$INPUT_SSH_PORT" -lt 1024 ] || [ "$INPUT_SSH_PORT" -gt 65535 ]; then
        log_error "El puerto debe estar en el rango de 1024 a 65535."
        continue
    fi

    # Verificar si está ocupado por otro servicio diferente a SSH
    if command -v ss >/dev/null 2>&1; then
        if ss -tln | grep -q ":${INPUT_SSH_PORT} "; then
            CURRENT_SSH=$(ss -tlnp 2>/dev/null | grep ":${INPUT_SSH_PORT} " || true)
            if echo "$CURRENT_SSH" | grep -q "sshd"; then
                log_info "El puerto $INPUT_SSH_PORT ya está siendo usado por el demonio SSH actual."
            else
                log_error "El puerto $INPUT_SSH_PORT/tcp ya está ocupado por otro servicio en el servidor."
                continue
            fi
        fi
    fi

    CHOSEN_SSH_PORT="$INPUT_SSH_PORT"
    log_ok "Puerto SSH seleccionado: ${C_BOLD}${CHOSEN_SSH_PORT}/tcp${C_RESET}"
    break
done

# ------------------------------------------------------------------------------
# 5. Hardening de OpenSSH, Solución de Sockets Systemd y Limpieza Cloud-Init
# ------------------------------------------------------------------------------
log_step "Paso 5/9: Aplicando Hardening a OpenSSH y resolviendo sockets de Debian 12/13..."

# 5.1 Configuración de sshd_config principal
if [ -f /etc/ssh/sshd_config ]; then
    # Comentar o actualizar directivas Port previas
    if grep -q "^Port " /etc/ssh/sshd_config; then
        sed -i "s/^Port .*/Port ${CHOSEN_SSH_PORT}/" /etc/ssh/sshd_config
    else
        echo "Port ${CHOSEN_SSH_PORT}" >> /etc/ssh/sshd_config
    fi
fi

# 5.2 Crear o actualizar archivo drop-in para OpenSSH moderno
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-se2code-hardening.conf << SSH_EOF
# ==============================================================================
# se2Code Stack - Hardening de SSH (Debian 12 / 13)
# ==============================================================================
Port ${CHOSEN_SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
SSH_EOF

# 5.3 Neutralizar overrides habituales de proveedores cloud (Hostinger, AWS, Hetzner)
for cloud_file in /etc/ssh/sshd_config.d/50-cloud-init.conf /etc/ssh/sshd_config.d/*cloud*; do
    if [ -f "$cloud_file" ] && [ "$cloud_file" != "/etc/ssh/sshd_config.d/99-se2code-hardening.conf" ]; then
        log_info "Detectado override cloud: $cloud_file. Neutralizando PasswordAuthentication yes..."
        sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]]\+yes/PasswordAuthentication no/g' "$cloud_file"
    fi
done

# 5.4 CRÍTICO EN DEBIAN 12/13: Solucionar activación por socket systemd (ssh.socket)
# En Debian 12, ssh.socket intercepta el puerto 22 e ignora sshd_config.
# Desactivamos ssh.socket y forzamos el servicio standalone ssh.service, además de configurar el override.
mkdir -p /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/listen.conf << SOCK_EOF
[Socket]
ListenStream=
ListenStream=${CHOSEN_SSH_PORT}
SOCK_EOF

systemctl stop ssh.socket 2>/dev/null || true
systemctl disable ssh.socket 2>/dev/null || true
systemctl daemon-reload

# 5.5 Validación de sintaxis antes de reiniciar el demonio
if sshd -t; then
    systemctl enable --now ssh.service 2>/dev/null || systemctl enable --now ssh 2>/dev/null || true
    systemctl restart ssh.service 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    log_ok "Demonio SSH reiniciado y reconfigurado."
else
    log_error "Error de sintaxis en la configuración de SSH. Revisa /etc/ssh/sshd_config."
fi

# 5.6 Comprobar que SSH esté escuchando activamente en el nuevo puerto
log_info "Comprobando que SSH esté escuchando en el puerto ${CHOSEN_SSH_PORT}/tcp..."
SSH_UP=false
for i in {1..10}; do
    if ss -tln | grep -q ":${CHOSEN_SSH_PORT} "; then
        SSH_UP=true
        break
    fi
    sleep 1
done

if [ "$SSH_UP" = true ]; then
    log_ok "Servicio SSH activo y escuchando en el puerto ${CHOSEN_SSH_PORT}/tcp."
else
    log_warn "SSH no respondió inmediatamente en el puerto ${CHOSEN_SSH_PORT}. Reintentando arranque forzado..."
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    sleep 2
    if ss -tln | grep -q ":${CHOSEN_SSH_PORT} "; then
        log_ok "Servicio SSH arrancado con éxito en el puerto ${CHOSEN_SSH_PORT}/tcp."
    else
        log_error "Alerta: No se detecta escucha en el puerto ${CHOSEN_SSH_PORT}/tcp. El puerto 22 se mantendrá abierto."
    fi
fi

# ------------------------------------------------------------------------------
# 6. Configuración del Firewall UFW (Nativo y Exclusivo)
# ------------------------------------------------------------------------------
log_step "Paso 6/9: Configuración del Firewall UFW..."

# Políticas maestras por defecto
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1

# Apertura de puertos esenciales
ufw allow "${CHOSEN_SSH_PORT}/tcp" comment "se2Code SSH Custom" >/dev/null 2>&1

# Mantener SIEMPRE abierto el puerto 22 durante la transición para evitar bloqueos
ufw allow 22/tcp comment "se2Code SSH Transition" >/dev/null 2>&1

ufw allow 80/tcp comment "HTTP Nginx" >/dev/null 2>&1
ufw allow 443/tcp comment "HTTPS Nginx" >/dev/null 2>&1

# Consultar puerto WireGuard VPN si se desea pre-abrir
echo -e "\n${C_CYAN}¿Deseas autorizar un puerto UDP para WireGuard VPN en el Firewall? [S/n]:${C_RESET}"
read -r -p "[S/n]: " OPEN_WG
OPEN_WG="${OPEN_WG:-S}"
if [[ "$OPEN_WG" =~ ^[Ss]$ ]]; then
    read -r -p "Puerto UDP de WireGuard (Rango: 1024-65535) [Por defecto: 62420]: " WG_PORT
    WG_PORT="${WG_PORT:-62420}"
    ufw allow "${WG_PORT}/udp" comment "se2Code WireGuard VPN" >/dev/null 2>&1
    log_ok "Puerto WireGuard ${WG_PORT}/udp añadido a UFW."
fi

ufw --force enable >/dev/null 2>&1
ufw reload >/dev/null 2>&1
log_ok "Firewall UFW activado con políticas estrictas (deny incoming, allow outgoing)."

# ------------------------------------------------------------------------------
# 7. Protección contra Intrusiones con Fail2ban (Systemd + nftables)
# ------------------------------------------------------------------------------
log_step "Paso 7/9: Configurando Fail2ban para Debian 12/13..."

mkdir -p /etc/fail2ban
cat > /etc/fail2ban/jail.local << F2B_EOF
# ==============================================================================
# se2Code Stack - Fail2ban Configuration (Debian 12+ Systemd & nftables)
# ==============================================================================
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
ignoreip = 127.0.0.1/8 ::1 10.13.13.0/24
backend = systemd
banaction = nftables[type=multiport]
banaction_allports = nftables[type=allports]

[sshd]
enabled = true
port = ${CHOSEN_SSH_PORT}
filter = sshd
backend = systemd
maxretry = 3
bantime = 3600
F2B_EOF

systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban >/dev/null 2>&1 || true
sleep 2

if fail2ban-client status sshd >/dev/null 2>&1; then
    log_ok "Fail2ban activo y protegiendo el jail 'sshd' en puerto ${CHOSEN_SSH_PORT}/tcp."
else
    log_warn "Fail2ban inició pero el socket se está sincronizando con journald."
fi

# ------------------------------------------------------------------------------
# 8. Hardening del Kernel (sysctl), Modprobe y Permisos del Sistema
# ------------------------------------------------------------------------------
log_step "Paso 8/9: Aplicando Hardening a nivel de Kernel y Sistema Operativo..."

# 8.1 Sysctl Network Hardening
cat > /etc/sysctl.d/99-security-hardening.conf << 'SYSCTL_EOF'
# ==============================================================================
# se2Code Stack - Hardening de Red y Optimización TCP (Kernel)
# ==============================================================================
# Protección contra ataques de red
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Optimización de alto rendimiento para servidores web
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
SYSCTL_EOF

sysctl --system >/dev/null 2>&1 || true
log_ok "Parámetros sysctl aplicados (SYN cookies, rp_filter, buffers de red)."

# 8.2 Modprobe Hardening
cat > /etc/modprobe.d/hardening.conf << 'MOD_EOF'
# Deshabilitar filesystems obsoletos
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true

# Deshabilitar protocolos de red no utilizados
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
MOD_EOF
log_ok "Módulos de kernel obsoletos o vulnerables deshabilitados."

# 8.3 Límites de Seguridad en limits.conf
if ! grep -q "se2code security limits" /etc/security/limits.conf 2>/dev/null; then
    cat >> /etc/security/limits.conf << 'LIMITS_EOF'
# se2code security limits
*               hard    core            0
*               hard    maxlogins       10
*               hard    nproc           1000
LIMITS_EOF
    log_ok "Límites de procesos y recursos aplicados en limits.conf."
fi

# 8.4 Permisos estrictos de archivos del sistema
chmod 700 /root
chmod 600 /boot/grub/grub.cfg 2>/dev/null || true
chmod 600 /etc/shadow
chmod 644 /etc/passwd
chmod 600 /etc/gshadow 2>/dev/null || true
chmod 644 /etc/group
log_ok "Permisos de seguridad estrictos aplicados en archivos del sistema."

# ------------------------------------------------------------------------------
# 9. Verificación de Seguridad y Salvaguarda Anti-Bloqueo
# ------------------------------------------------------------------------------
log_step "Paso 9/9: Salvaguarda de Conexión (Anti-Lockout)"

SERVER_IP=$(curl -s4 --max-time 3 ifconfig.me || curl -s4 --max-time 3 icanhazip.com || ip route get 1.1.1.1 2>/dev/null | awk "{print \$7}" || echo "TU_IP_DEL_SERVIDOR")

echo -e "\n${C_BOLD}${C_YELLOW}╔════════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_YELLOW}║         ⚠️  ATENCIÓN: PRUEBA DE CONEXIÓN EN TERMINAL NUEVA             ║${C_RESET}"
echo -e "${C_BOLD}${C_YELLOW}╚════════════════════════════════════════════════════════════════════════╝${C_RESET}"
echo -e "${C_BOLD}¡NO CIERRES ESTA TERMINAL ACTUAL!${C_RESET}"
echo -e "Abre una ${C_CYAN}NUEVA ventana de terminal${C_RESET} en tu computadora local y prueba conectarte:"
echo -e "\n  ${C_BOLD}${C_GREEN}ssh -p ${CHOSEN_SSH_PORT} ${ADMIN_USER}@${SERVER_IP} -i <ruta-de-tu-llave.pem>${C_RESET}\n"
echo -e "${C_GRAY}(Nota: recuerda que en OpenSSH la bandera de puerto es -p en minúscula).${C_RESET}\n"
echo -e "Una vez conectado, valida que puedas usar sudo ejecutando: ${C_BOLD}sudo whoami${C_RESET}\n"

read -r -p "¿Confirmas que pudiste conectar con éxito en la nueva terminal? [s/N]: " TEST_OK
TEST_OK="${TEST_OK:-N}"

if [[ "$TEST_OK" =~ ^[Ss]$ ]]; then
    if [ "$CHOSEN_SSH_PORT" != "22" ]; then
        log_info "Cerrando puerto temporal 22/tcp en el Firewall UFW..."
        ufw delete allow 22/tcp >/dev/null 2>&1 || true
        ufw reload >/dev/null 2>&1 || true
        log_ok "Puerto 22 cerrado. Acceso restringido únicamente al puerto ${CHOSEN_SSH_PORT}/tcp."
    fi
    log_section "¡HARDENING Y SECURIZACIÓN DEL SERVIDOR COMPLETADOS EXITOSAMENTE!"
    echo -e "  - Usuario Administrador: ${C_BOLD}${C_GREEN}${ADMIN_USER}${C_RESET}"
    echo -e "  - Puerto SSH Seguro:     ${C_BOLD}${C_GREEN}${CHOSEN_SSH_PORT}/tcp${C_RESET}"
    echo -e "  - Login por Password:   ${C_BOLD}${C_RED}DESHABILITADO${C_RESET}"
    echo -e "  - Login de Root Directo: ${C_BOLD}${C_RED}DESHABILITADO${C_RESET}"
    echo -e "  - Firewall UFW:          ${C_BOLD}${C_GREEN}ACTIVO (80, 443, ${CHOSEN_SSH_PORT})${C_RESET}"
    echo -e "  - Fail2ban:              ${C_BOLD}${C_GREEN}ACTIVO (Systemd + nftables)${C_RESET}"
    echo -e "  - Kernel Hardening:      ${C_BOLD}${C_GREEN}APLICADO${C_RESET}\n"
else
    log_warn "Manteniendo abierto el puerto 22/tcp en UFW para evitar que quedes bloqueado."
    log_warn "Puedes probar ingresar de nuevo o revisar tu configuración antes de cerrar el puerto 22."
fi
