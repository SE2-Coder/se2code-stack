#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack - Runner automático de WP-Cron para todos los sitios WordPress
# ==============================================================================
WP_DATA_DIR="/opt/se2code-stack/modules/wordpress/wp-data"

[ -d "$WP_DATA_DIR" ] || exit 0

for site_dir in "$WP_DATA_DIR"/*; do
    if [ -d "$site_dir" ] && [ -f "$site_dir/wp-config.php" ]; then
        site_name=$(basename "$site_dir")
        docker exec --user 33:33 wp-php84 wp cron event run --due-now --path="/var/www/html/$site_name" >/dev/null 2>&1 || true
    fi
done
