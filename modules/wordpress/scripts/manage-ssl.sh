#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WordPress: Gestión de Certificados SSL/TLS
# (Cloudflare Origin CA, Let's Encrypt vía acme.sh, Autofirmados)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

DOMAIN="${1:-}"
SITE_SLUG="${2:-}"

# Si no se pasó dominio, listar sitios para seleccionar interactivamente
if [ -z "$DOMAIN" ]; then
    echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
    echo -e "  ${C_BOLD}🔒 GESTIÓN DE CERTIFICADOS SSL/TLS SE2CODE${C_RESET}"
    echo -e "${C_CYAN}======================================================================${C_RESET}"

    CONF_FILES=($(find "$STACK_ROOT/nginx/conf.d" -type f -name "*.conf" ! -name "default*.conf" 2>/dev/null | sort || true))

    if [ ${#CONF_FILES[@]} -eq 0 ]; then
        log_warn "No se encontraron sitios WordPress configurados en el servidor."
        exit 1
    fi

    echo -e "\nSelecciona el sitio para gestionar sus certificados SSL:"
    idx=1
    declare -a DOMAINS_LIST
    declare -a SLUGS_LIST

    for conf in "${CONF_FILES[@]}"; do
        slug=$(basename "$conf" .conf)
        dom=$(grep -E "^\s*server_name\s+" "$conf" | head -n 1 | awk '{print $2}' | tr -d ';' || echo "$slug")
        DOMAINS_LIST+=("$dom")
        SLUGS_LIST+=("$slug")

        # Estado SSL
        cert_file="$STACK_ROOT/nginx/certs/$dom/fullchain.pem"
        if [ -f "$cert_file" ]; then
            ssl_status="${C_GREEN}Activo ✔${C_RESET}"
        else
            ssl_status="${C_YELLOW}No SSL ⚠${C_RESET}"
        fi

        echo -e "  ${C_CYAN}$idx)${C_RESET} ${C_BOLD}$dom${C_RESET} (${C_GRAY}slug: $slug, SSL: $ssl_status${C_RESET})"
        idx=$((idx + 1))
    done

    echo ""
    read -r -p "Escribe el número del sitio [1-${#DOMAINS_LIST[@]}] o escribe el dominio: " SITE_INPUT

    if [[ "$SITE_INPUT" =~ ^[0-9]+$ ]] && [ "$SITE_INPUT" -ge 1 ] && [ "$SITE_INPUT" -le ${#DOMAINS_LIST[@]} ]; then
        idx_zero=$((SITE_INPUT - 1))
        DOMAIN="${DOMAINS_LIST[$idx_zero]}"
        SITE_SLUG="${SLUGS_LIST[$idx_zero]}"
    else
        DOMAIN=$(echo "$SITE_INPUT" | sed -e 's|^https\?://||' -e 's|/.*$||' | tr -d '[:space:]')
    fi
fi

if [ -z "$DOMAIN" ]; then
    log_err "Dominio no válido. Operación cancelada."
    exit 1
fi

# Detectar slug si no vino por parámetro
if [ -z "$SITE_SLUG" ]; then
    # Buscar en nginx/conf.d
    MATCHING_CONF=$(grep -l -E "server_name.*\b${DOMAIN}\b" "$STACK_ROOT/nginx/conf.d/"*.conf 2>/dev/null | head -n 1 || true)
    if [ -n "$MATCHING_CONF" ]; then
        SITE_SLUG=$(basename "$MATCHING_CONF" .conf)
    else
        SITE_SLUG=$(echo "$DOMAIN" | tr -cd '[:alnum:]')
    fi
fi

CERTS_DIR="$STACK_ROOT/nginx/certs/$DOMAIN"
SITE_WEB_DIR="$STACK_ROOT/wp-data/$SITE_SLUG"
mkdir -p "$CERTS_DIR"

echo -e "\n${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_BOLD}CONFIGURACIÓN DE CERTIFICADO SSL/TLS${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "Dominio: ${C_BOLD}${C_YELLOW}${DOMAIN}${C_RESET}\n"
echo -e "Selecciona el tipo de certificado para ${C_YELLOW}${DOMAIN}${C_RESET}:\n"
echo -e "  1) ${C_GREEN}Pegar certificados de Cloudflare (Origin CA)${C_RESET}"
echo -e "     ${C_GRAY}↳ Para sitios detrás de Cloudflare. Válido hasta por 15 años.${C_RESET}\n"
echo -e "  2) ${C_CYAN}Let's Encrypt automático (acme.sh)${C_RESET}"
echo -e "     ${C_GRAY}↳ Certificado público oficial con candado verde directo (sin Cloudflare).${C_RESET}\n"
echo -e "  3) ${C_YELLOW}Certificado autofirmado (Rápido / Pruebas / Cloudflare)${C_RESET}"
echo -e "     ${C_GRAY}↳ Generación instantánea. Para pruebas o si ya usas Cloudflare (modo Full).${C_RESET}\n"

read -r -p "Elige una opción [1-3, por defecto 3]: " SSL_CHOICE
SSL_CHOICE=${SSL_CHOICE:-3}

case "$SSL_CHOICE" in
    1)
        echo -e "\n${C_BOLD}--- Instalación de Certificados de Cloudflare Origin CA ---${C_RESET}"
        echo -e "${C_CYAN}Pega el Certificado de Origen (Origin Certificate) y escribe 'EOF' en una línea sola al terminar:${C_RESET}"
        SSL_CERT=""
        while IFS= read -r line; do
            [ "$line" = "EOF" ] && break
            SSL_CERT="${SSL_CERT}${line}\n"
        done
        printf "%b" "$SSL_CERT" > "$CERTS_DIR/fullchain.pem"

        echo -e "\n${C_CYAN}Pega la Llave Privada (Private Key) y escribe 'EOF' en una línea sola al terminar:${C_RESET}"
        SSL_KEY=""
        while IFS= read -r line; do
            [ "$line" = "EOF" ] && break
            SSL_KEY="${SSL_KEY}${line}\n"
        done
        printf "%b" "$SSL_KEY" > "$CERTS_DIR/privkey.pem"
        cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
        chmod 600 "$CERTS_DIR/privkey.pem"
        chmod 644 "$CERTS_DIR"/*.pem

        docker exec wp-nginx nginx -t >/dev/null 2>&1 && docker exec wp-nginx nginx -s reload 2>/dev/null || true
        log_ok "Certificados SSL de Cloudflare instalados y aplicados correctamente para $DOMAIN."
        ;;
    2)
        echo -e "\n${C_BOLD}--- Emisión Automática vía Let's Encrypt (acme.sh) ---${C_RESET}"
        if [ ! -f /root/.acme.sh/acme.sh ]; then
            log_step "Instalando cliente ACME (acme.sh)..."
            curl -sSL https://get.acme.sh | sh -s email="admin@${DOMAIN}" >/dev/null 2>&1 || true
            ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh 2>/dev/null || true
        fi

        /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

        # Crear webroot de acme challenge
        mkdir -p "$SITE_WEB_DIR/.well-known/acme-challenge"
        chown -R 33:33 "$SITE_WEB_DIR/.well-known" 2>/dev/null || true
        chmod -R 755 "$SITE_WEB_DIR/.well-known" 2>/dev/null || true

        # Asegurar certificado temporal para Nginx si no existe
        if [ ! -f "$CERTS_DIR/fullchain.pem" ] || [ ! -f "$CERTS_DIR/privkey.pem" ]; then
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$CERTS_DIR/privkey.pem" \
                -out "$CERTS_DIR/fullchain.pem" \
                -subj "/C=CO/ST=Valle/L=Cali/O=se2Code/CN=$DOMAIN" >/dev/null 2>&1
            cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
            chmod 600 "$CERTS_DIR/privkey.pem"
            chmod 644 "$CERTS_DIR"/*.pem
        fi

        # Recargar Nginx para que location /.well-known/acme-challenge/ esté activo en puerto 80
        docker exec wp-nginx nginx -t >/dev/null 2>&1 && docker exec wp-nginx nginx -s reload 2>/dev/null || true

        log_step "Emitiendo certificado Let's Encrypt para '$DOMAIN'..."
        if /root/.acme.sh/acme.sh --issue -d "$DOMAIN" -w "$SITE_WEB_DIR" --server letsencrypt; then
            log_step "Instalando certificado en NGINX..."
            /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
                --key-file "$CERTS_DIR/privkey.pem" \
                --fullchain-file "$CERTS_DIR/fullchain.pem" \
                --reloadcmd "docker exec wp-nginx nginx -s reload" >/dev/null 2>&1 || true
            cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
            chmod 600 "$CERTS_DIR/privkey.pem"
            chmod 644 "$CERTS_DIR"/*.pem
            docker exec wp-nginx nginx -s reload 2>/dev/null || true
            log_ok "¡Certificado Let's Encrypt emitido e instalado con éxito para $DOMAIN!"
        else
            log_warn "No se pudo validar el reto HTTP de Let's Encrypt para $DOMAIN."
            log_warn "Se mantuvo el certificado existente/autofirmado para evitar que el sitio quede inaccesible."
            log_warn "Asegúrate de que el registro DNS A de '$DOMAIN' apunte a la IP de este VPS."
        fi
        ;;
    3|*)
        echo -e "\n${C_BOLD}--- Generación de Certificado Autofirmado ---${C_RESET}"
        log_step "Generando certificado autofirmado para '$DOMAIN'..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$CERTS_DIR/privkey.pem" \
            -out "$CERTS_DIR/fullchain.pem" \
            -subj "/C=CO/ST=Valle/L=Cali/O=se2Code/CN=$DOMAIN" >/dev/null 2>&1
        cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
        chmod 600 "$CERTS_DIR/privkey.pem"
        chmod 644 "$CERTS_DIR"/*.pem

        docker exec wp-nginx nginx -t >/dev/null 2>&1 && docker exec wp-nginx nginx -s reload 2>/dev/null || true
        log_ok "Certificado autofirmado generado y activo para $DOMAIN."
        ;;
esac
