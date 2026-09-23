FROM nginx:1.27-alpine

# Alinear UID/GID 33 (www-data) en Alpine para paridad total con PHP-FPM (UID 33) y WordPress
RUN deluser xfs 2>/dev/null || true && \
    sed -i 's/:82:82:/:33:33:/' /etc/passwd 2>/dev/null || true && \
    sed -i 's/:82:/:33:/' /etc/group 2>/dev/null || true && \
    mkdir -p /var/cache/nginx /var/log/nginx && \
    chown -R www-data:www-data /var/cache/nginx /var/log/nginx && \
    chmod -R 775 /var/cache/nginx
