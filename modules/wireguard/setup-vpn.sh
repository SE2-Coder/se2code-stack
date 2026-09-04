#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WireGuard VPN: Asistente de Despliegue y Gestión
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

[ -f "$STACK_ROOT/core/banner.sh" ] && source "$STACK_ROOT/core/banner.sh"
[ -f "$STACK_ROOT/core/ports.sh" ] && source "$STACK_ROOT/core/ports.sh"

log_section "🛡️  MÓDULO WIREGUARD VPN: INSTALACIÓN Y CONFIGURACIÓN"

# 1. Habilitar Reenvío de Paquetes en Kernel
log_step "Habilitando reenvío de paquetes en el Kernel (IP Forwarding)..."
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-se2code-wireguard.conf >/dev/null
echo "net.ipv4.conf.all.src_valid_mark=1" | sudo tee -a /etc/sysctl.d/99-se2code-wireguard.conf >/dev/null
sudo sysctl --system >/dev/null 2>&1 || true
log_ok "Kernel IP Forwarding habilitado."

# 2. Configurar NAT en UFW
log_step "Configurando enrutamiento NAT nativo en UFW..."
MAIN_IF=$(ip route show default 2>/dev/null | awk '{print $5}' || echo "eth0")
sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw 2>/dev/null || true

# Inyectar reglas NAT en /etc/ufw/before.rules si no existen
if ! grep -q "10.13.13.0/24" /etc/ufw/before.rules 2>/dev/null; then
    sudo sed -i '1i # Reglas NAT Masquerade se2Code VPN\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.13.13.0/24 -o '"$MAIN_IF"' -j MASQUERADE\nCOMMIT\n' /etc/ufw/before.rules
fi

if ! grep -q "ufw-before-forward -i wg0" /etc/ufw/before.rules 2>/dev/null; then
    sudo sed -i '/^:ufw-before-forward/a -A ufw-before-forward -i wg0 -j ACCEPT\n-A ufw-before-forward -o wg0 -j ACCEPT' /etc/ufw/before.rules
fi
sudo ufw reload >/dev/null 2>&1 || true
log_ok "Reglas NAT UFW activas en interfaz $MAIN_IF."

# 3. Detectar IP Pública
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "127.0.0.1")
log_ok "IP Pública del servidor: $PUBLIC_IP"

# 4. Selección Dinámica de Puerto UDP
WG_PORT=$(ask_custom_port "WireGuard VPN" "62420" "udp")

# 5. Generar .env de WireGuard
cat << ENV_EOF > "$SCRIPT_DIR/.env"
WG_SERVERURL=${PUBLIC_IP}
WG_SERVERPORT=${WG_PORT}
WG_PEERS=2
ENV_EOF

# 6. Levantar WireGuard de forma limpia
log_step "Desplegando contenedor WireGuard en modo Host (Puerto $WG_PORT/udp)..."
cd "$SCRIPT_DIR"

# Limpieza previa del kernel para evitar socket bloqueado
docker compose down >/dev/null 2>&1 || true
sudo ip link delete wg0 2>/dev/null || true

mkdir -p "$SCRIPT_DIR/config"
docker compose --env-file "$SCRIPT_DIR/.env" up -d

log_info "Esperando 8 segundos para la generación de claves y perfiles..."
sleep 8

# 7. Corregir permisos para lectura de QR
sudo chown -R "$USER:$USER" "$SCRIPT_DIR/config" 2>/dev/null || true
sudo chmod -R 755 "$SCRIPT_DIR/config" 2>/dev/null || true

# 8. Inyectar puerto real si wg_confs/wg0.conf se generó en 51820
if [ -f "$SCRIPT_DIR/config/wg_confs/wg0.conf" ]; then
    sudo sed -i "s/51820/$WG_PORT/g" "$SCRIPT_DIR/config/wg_confs/wg0.conf" 2>/dev/null || true
    sudo sed -i "s/:51820/:$WG_PORT/g" "$SCRIPT_DIR/config/peer"*/*.conf 2>/dev/null || true
    docker compose restart >/dev/null 2>&1 || true
    sleep 3
fi

log_ok "WireGuard VPN activo y escuchando en puerto UDP $WG_PORT."

# 9. Mostrar Código QR
if [ -f "$SCRIPT_DIR/config/peer1/peer1.conf" ] && command -v qrencode >/dev/null 2>&1; then
    echo -e "\n${C_BOLD}${C_GREEN}📱 CÓDIGO QR PARA DISPOSITIVO MÓVIL (PEER 1):${C_RESET}"
    echo -e "${C_GRAY}Escanea este código con la app oficial de WireGuard en tu teléfono:${C_RESET}\n"
    qrencode -t ansiutf8 < "$SCRIPT_DIR/config/peer1/peer1.conf"
fi
