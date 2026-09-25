#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - Aprovisionador de Landing Pages Básicas
# (Sin Base de Datos - 100% Ligero, HTML/CSS/JS con opción PHP 8.4)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"

# Cargar utilidades
[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

SITE_SLUG="${1:-}"
DOMAIN="${2:-}"
ENABLE_PHP="${3:-}"
SSL_CHOICE="${4:-}"

# Modo interactivo
if [ -z "$SITE_SLUG" ]; then
    echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
    echo -e "  ${C_BOLD}🚀 CREACIÓN DE LANDING PAGE BÁSICA (SIN BASE DE DATOS)${C_RESET}"
    echo -e "${C_CYAN}======================================================================${C_RESET}\n"
    read -r -p "Identificador / Slug de la landing (ej: milanding): " SITE_SLUG
fi

if [ -z "$DOMAIN" ]; then
    read -r -p "Dominio principal (ej: milanding.com): " DOMAIN
fi

# Sanitizar entradas
SITE_SLUG=$(echo "$SITE_SLUG" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')
DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-')

if [ -z "$SITE_SLUG" ] || [ -z "$DOMAIN" ]; then
    log_error "El slug y el dominio no pueden estar vacíos."
    exit 1
fi

# Verificar si el sitio ya existe
VHOST_FILE="$STACK_ROOT/nginx/conf.d/${SITE_SLUG}.conf"
SITE_WEB_DIR="$STACK_ROOT/wp-data/$SITE_SLUG"

if [ -f "$VHOST_FILE" ] || [ -d "$SITE_WEB_DIR" ]; then
    log_error "Ya existe un sitio o configuración con el slug [$SITE_SLUG]."
    log_info "Si deseas reemplazarlo, elimínalo primero con: se2code -> Opción 5."
    exit 1
fi

# Preguntar por soporte PHP
if [ -z "$ENABLE_PHP" ]; then
    echo -e "\n${C_BOLD}[?] ¿Deseas habilitar procesamiento PHP para esta landing page?${C_RESET}"
    echo -e "    ${C_GRAY}Permite procesar formularios con contact.php, enviar emails o conectar webhooks.${C_RESET}"
    echo -e "  1) ${C_GREEN}Sí, habilitar PHP 8.4 (Recomendado - Formulario de contacto funcional)${C_RESET}"
    echo -e "  2) ${C_CYAN}No, sitio 100% Estático (HTML/CSS/JS puro - Cero procesos PHP)${C_RESET}"
    read -r -p "Opción [1-2, por defecto 1]: " PHP_OPT
    PHP_OPT=${PHP_OPT:-1}
    if [ "$PHP_OPT" = "1" ] || [ "$PHP_OPT" = "yes" ]; then
        ENABLE_PHP="yes"
    else
        ENABLE_PHP="no"
    fi
fi

log_step "Aprovisionando landing page: $SITE_SLUG ($DOMAIN)..."

# 1. Configuración de PHP Pool (solo si está habilitado)
PHP_PORT=""
PHP_CONTAINER="wp-php84"
POOL_DIR="$STACK_ROOT/php/php84/pools"

if [ "$ENABLE_PHP" = "yes" ]; then
    USED_PORTS=$(grep -shoE "listen = 0.0.0.0:[0-9]+" "$STACK_ROOT"/php/php*/pools/*.conf 2>/dev/null | awk -F: '{print $2}' || true)
    NEXT_PORT=9001
    while echo "$USED_PORTS" | grep -q "^${NEXT_PORT}$"; do
        NEXT_PORT=$((NEXT_PORT + 1))
    done
    PHP_PORT=$NEXT_PORT
    log_ok "Puerto PHP-FPM asignado: $PHP_PORT"

    sed -e "s/{{SITE_SLUG}}/$SITE_SLUG/g" \
        -e "s/{{PHP_PORT}}/$PHP_PORT/g" \
        "$STACK_ROOT/templates/php-pool.conf.tpl" > "$POOL_DIR/${SITE_SLUG}.conf"
    log_ok "Pool PHP-FPM generado en $POOL_DIR/${SITE_SLUG}.conf"
fi

# 2. Configuración de Certificados SSL/TLS
CERTS_DIR="$STACK_ROOT/nginx/certs/$DOMAIN"
mkdir -p "$CERTS_DIR"

if [ -z "$SSL_CHOICE" ]; then
    echo -e "\n${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "  ${C_BOLD}CONFIGURACIÓN DE CERTIFICADO SSL/TLS${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "Selecciona el tipo de certificado para ${C_YELLOW}${DOMAIN}${C_RESET}:\n"
    echo -e "  1) ${C_GREEN}Pegar certificados de Cloudflare (Origin CA)${C_RESET}"
    echo -e "     ${C_GRAY}↳ Para sitios detrás de Cloudflare. Válido hasta por 15 años.${C_RESET}\n"
    echo -e "  2) ${C_CYAN}Let's Encrypt automático (acme.sh)${C_RESET}"
    echo -e "     ${C_GRAY}↳ Certificado público oficial con candado verde directo.${C_RESET}\n"
    echo -e "  3) ${C_YELLOW}Certificado autofirmado (Rápido / Pruebas / Cloudflare Full)${C_RESET}"
    echo -e "     ${C_GRAY}↳ Generación instantánea. Ideal para pruebas locales o Cloudflare.${C_RESET}\n"

    read -r -p "Elige una opción [1-3, por defecto 3]: " SSL_CHOICE
    SSL_CHOICE=${SSL_CHOICE:-3}
fi

NEED_ACME=false

case "$SSL_CHOICE" in
    1)
        echo -e "\n${C_CYAN}Pega el Certificado de Origen (Origin Certificate) y escribe 'EOF' en una línea sola al terminar:${C_RESET}"
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
        log_ok "Certificados SSL de Cloudflare guardados."
        ;;
    2)
        log_info "Configurando certificado provisional para inicializar NGINX..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$CERTS_DIR/privkey.pem" \
            -out "$CERTS_DIR/fullchain.pem" \
            -subj "/C=CO/ST=Valle/L=Cali/O=se2Code/CN=$DOMAIN" >/dev/null 2>&1
        cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
        NEED_ACME=true
        log_ok "Certificado provisional listo. Se emitirá Let's Encrypt tras activar NGINX."
        ;;
    3|*)
        log_step "Generando certificado autofirmado..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$CERTS_DIR/privkey.pem" \
            -out "$CERTS_DIR/fullchain.pem" \
            -subj "/C=CO/ST=Valle/L=Cali/O=se2Code/CN=$DOMAIN" >/dev/null 2>&1
        cp "$CERTS_DIR/fullchain.pem" "$CERTS_DIR/chain.pem"
        log_ok "Certificado autofirmado generado y activo."
        ;;
esac

chmod 600 "$CERTS_DIR/privkey.pem"
chmod 644 "$CERTS_DIR"/*.pem

# 3. Desplegar Archivos de la Landing Page
log_step "Desplegando archivos de plantilla en $SITE_WEB_DIR..."
mkdir -p "$SITE_WEB_DIR"
cp -r "$STACK_ROOT/templates/landing-page/"* "$SITE_WEB_DIR/"

# Reemplazar DOMAIN en index.html
if [ -f "$SITE_WEB_DIR/index.html" ]; then
    sed -i "s/{{DOMAIN}}/$DOMAIN/g" "$SITE_WEB_DIR/index.html"
fi

# Si PHP está desactivado, eliminar contact.php para seguridad total
if [ "$ENABLE_PHP" != "yes" ]; then
    rm -f "$SITE_WEB_DIR/contact.php"
fi

# Ajustar permisos para Nginx/PHP (uid 33: gid 33)
chown -R 33:33 "$SITE_WEB_DIR" 2>/dev/null || true
chmod -R 755 "$SITE_WEB_DIR"

# 4. Generar Virtual Host de NGINX
log_step "Generando configuración NGINX..."

if [ "$ENABLE_PHP" = "yes" ]; then
    read -r -d '' PHP_BLOCK << EOP || true
    # Procesamiento de scripts PHP (formularios de contacto)
    location ~ \.php$ {
        fastcgi_pass ${PHP_CONTAINER}:${PHP_PORT};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_read_timeout 60;
    }
EOP
else
    read -r -d '' PHP_BLOCK << EOP || true
    # PHP deshabilitado para esta landing estática pura
    location ~ \.php$ {
        deny all;
    }
EOP
fi

# Crear el vhost reemplazando los placeholders
export SITE_SLUG DOMAIN PHP_BLOCK
awk -v slug="$SITE_SLUG" -v dom="$DOMAIN" -v phpblock="$PHP_BLOCK" '{
    gsub(/\{\{SITE_SLUG\}\}/, slug);
    gsub(/\{\{DOMAIN\}\}/, dom);
    if ($0 ~ /\{\{PHP_LOCATION_BLOCK\}\}/) {
        print phpblock;
    } else {
        print $0;
    }
}' "$STACK_ROOT/templates/landing-vhost.conf.tpl" > "$VHOST_FILE"

log_ok "Virtual Host generado en $VHOST_FILE"

# 5. Reiniciar y Validar NGINX y PHP
if [ "$ENABLE_PHP" = "yes" ]; then
    log_step "Reiniciando contenedor $PHP_CONTAINER para activar el pool..."
    docker restart "$PHP_CONTAINER" >/dev/null 2>&1 || true
fi

log_step "Validando configuración de NGINX..."
if docker exec wp-nginx nginx -t >/dev/null 2>&1; then
    docker exec wp-nginx nginx -s reload >/dev/null 2>&1 || true
    log_ok "NGINX recargado exitosamente."
else
    log_warn "Advertencia: Comprueba la sintaxis de NGINX con 'docker exec wp-nginx nginx -t'."
fi

# 6. Emisión automática de Let's Encrypt si fue solicitado
if [ "$NEED_ACME" = true ]; then
    log_section "EMISIÓN AUTOMÁTICA DE CERTIFICADO LET'S ENCRYPT (ACME.SH)"
    if [ ! -f /root/.acme.sh/acme.sh ]; then
        log_step "Instalando cliente ACME (acme.sh)..."
        curl -sSL https://get.acme.sh | sh -s email="admin@${DOMAIN}" >/dev/null 2>&1 || true
        ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh 2>/dev/null || true
    fi

    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
    mkdir -p "$SITE_WEB_DIR/.well-known/acme-challenge"
    chown -R 33:33 "$SITE_WEB_DIR/.well-known" 2>/dev/null || true
    chmod -R 755 "$SITE_WEB_DIR/.well-known" 2>/dev/null || true

    log_step "Solicitando certificado Let's Encrypt para '$DOMAIN' vía reto HTTP..."
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
        log_warn "Se mantuvo el certificado autofirmado para garantizar operatividad inmediata."
        log_warn "Podrás reintentar emitir Let's Encrypt más tarde desde 'se2code -> Opción 7'."
    fi
fi

# 7. Resumen de Aprovisionamiento
echo -e "\n${C_BOLD}${C_GREEN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}      ¡LANDING PAGE CREADA EXITOSAMENTE CON SE2CODE STACK!           ${C_RESET}"
echo -e "${C_GREEN}======================================================================${C_RESET}\n"
echo -e "  - URL Oficial     : ${C_BOLD}${C_CYAN}https://${DOMAIN}${C_RESET}"
echo -e "  - Slug del Sitio  : ${C_YELLOW}${SITE_SLUG}${C_RESET}"
echo -e "  - Directorio Web  : ${C_WHITE:-\033[38;5;255m}${SITE_WEB_DIR}${C_RESET}"
echo -e "  - Base de Datos   : ${C_GREEN}Ninguna (0 MB RAM / Cero sobrecostos)${C_RESET}"
if [ "$ENABLE_PHP" = "yes" ]; then
    echo -e "  - Soporte PHP     : ${C_GREEN}PHP 8.4 Habilitado (Pool puerto TCP ${PHP_PORT})${C_RESET}"
    echo -e "  - Formulario      : ${C_CYAN}contact.php -> guarda leads en leads.json${C_RESET}"
else
    echo -e "  - Soporte PHP     : ${C_BLUE}Deshabilitado (100% HTML/CSS/JS Estático Puro)${C_RESET}"
fi
echo -e "  - Certificado SSL : ${C_GREEN}Configurado y Activo ✔${C_RESET}"
echo -e "  - Desempeño       : ${C_GREEN}⚡ 100/100 PageSpeed (Nginx Direct I/O + Static Cache 1 Año)${C_RESET}\n"

echo -e "${C_BOLD}${C_YELLOW}💡 CÓMO PERSONALIZAR ESTA LANDING PAGE:${C_RESET}"
echo -e "  1. Puedes subir tus archivos HTML, CSS y JS directamente a:"
echo -e "     ${C_CYAN}${SITE_WEB_DIR}/${C_RESET}"
echo -e "  2. O conectar un repositorio Git / despliegue continuo mediante SFTP o rsync."
echo -e "  3. Revisa la documentación interna en:"
echo -e "     ${C_CYAN}${SITE_WEB_DIR}/README.md${C_RESET}\n"
