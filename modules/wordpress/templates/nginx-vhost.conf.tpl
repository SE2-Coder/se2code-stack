# ============================================================================
# VIRTUAL HOST: {{SITE_SLUG}} - {{DOMAIN}} ({{PHP_CONTAINER}}:{{PHP_PORT}})
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
    index index.php index.html;

    ssl_certificate /etc/nginx/certs/{{DOMAIN}}/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/{{DOMAIN}}/privkey.pem;
    ssl_trusted_certificate /etc/nginx/certs/{{DOMAIN}}/chain.pem;

    include /etc/nginx/snippets/ssl.conf;
    include /etc/nginx/snippets/security-headers.conf;
    include /etc/nginx/snippets/uploads-protection.conf;

    access_log /var/log/nginx/{{SITE_SLUG}}.access.log main;
    error_log /var/log/nginx/{{SITE_SLUG}}.error.log warn;

    client_max_body_size 256M;

    # Rate limiting relajado para permitir builders pesados como Elementor
    limit_req zone=general burst=150 nodelay;
    limit_conn conn_limit_per_ip 100;

    # Bloqueo de archivos ocultos
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Bloqueo de archivos temporales de edición
    location ~ ~$ {
        deny all;
    }

    # Bloqueo de archivos sensibles de WordPress
    location ~* /(?:xmlrpc\.php|wp-links-opml\.php|wp-config\.php|wp-config-sample\.php) {
        deny all;
    }

    location = /wp-config.php {
        deny all;
    }

    # Protección de wp-login.php contra ataques de fuerza bruta
    location = /wp-login.php {
        limit_req zone=login burst=3 nodelay;
        include snippets/fastcgi-cache.conf;
        fastcgi_pass {{PHP_CONTAINER}}:{{PHP_PORT}};
        fastcgi_index index.php;
        include fastcgi_params;
    }

    # Caché para activos estáticos (imágenes, CSS, JS, fuentes)
    include /etc/nginx/snippets/static-cache.conf;

    # Enrutamiento principal de WordPress (Permalinks)
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # Procesamiento de PHP con FastCGI Cache
    location ~ \.php$ {
        include snippets/fastcgi-cache.conf;
        fastcgi_pass {{PHP_CONTAINER}}:{{PHP_PORT}};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }
}
