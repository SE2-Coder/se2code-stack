# ============================================================================
# VIRTUAL HOST: {{SITE_SLUG}} - {{DOMAIN}} (Landing Page - Sin Base de Datos)
# Generado por se2Code Stack Server
# ============================================================================

server {
    listen 80;
    listen [::]:80;
    server_name {{DOMAIN}} www.{{DOMAIN}};

    location /.well-known/acme-challenge/ {
        root /var/www/html/{{SITE_SLUG}};
        allow all;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    listen [::]:443 ssl;
    server_name {{DOMAIN}} www.{{DOMAIN}};

    root /var/www/html/{{SITE_SLUG}};
    index index.html index.htm index.php;

    ssl_certificate /etc/nginx/certs/{{DOMAIN}}/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/{{DOMAIN}}/privkey.pem;
    ssl_trusted_certificate /etc/nginx/certs/{{DOMAIN}}/chain.pem;

    include /etc/nginx/snippets/ssl.conf;
    include /etc/nginx/snippets/security-headers.conf;

    access_log /var/log/nginx/{{SITE_SLUG}}.access.log main;
    error_log /var/log/nginx/{{SITE_SLUG}}.error.log warn;

    client_max_body_size 64M;

    # Rate limiting
    limit_req zone=general burst=100 nodelay;
    limit_conn conn_limit_per_ip 50;

    # Bloqueo de archivos ocultos y sensibles
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~* \.(bak|backup|old|orig|save|swp|sql|log|ini|conf|config|env|git|sh|json)$ {
        deny all;
    }

    # Permitir manifiesto web si existe
    location = /manifest.json {
        allow all;
    }

    # Caché para activos estáticos (imágenes, CSS, JS, fuentes)
    include /etc/nginx/snippets/static-cache.conf;

    # Enrutamiento para Landing Pages (HTML estático + Clean URLs)
    location / {
        try_files $uri $uri/ $uri.html /index.html /index.php?$args =404;
    }

    # Procesamiento opcional de scripts PHP (formularios de contacto, mailers)
{{PHP_LOCATION_BLOCK}}
}
