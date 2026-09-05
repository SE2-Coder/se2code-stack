#!/usr/bin/env bash
# ==============================================================================
# se2Code Stack Server - WordPress: Motor de Backups Granulares (Soporta Multilenguaje)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WP_STACK_ROOT="$(cd "$STACK_ROOT/../.." && pwd)"
BACKUPS_DIR="$WP_STACK_ROOT/backups"

[ -f "$WP_STACK_ROOT/core/banner.sh" ] && source "$WP_STACK_ROOT/core/banner.sh"

SITE_SLUG="${1:-}"
BACKUP_TYPE="${2:-}"

# 1. Seleccionar sitio si no se pasó
if [ -z "$SITE_SLUG" ]; then
    echo -e "\n${C_BOLD}${C_CYAN}--- Módulo de Backups: Selecciona el Sitio ---${C_RESET}"
    
    # Listar sitios activos
    SITES=($(ls -1 "$STACK_ROOT"/php/php*/pools/*.conf 2>/dev/null | xargs -n 1 basename | sed 's/\.conf$//' | grep -v "placeholder" || true))
    if [ ${#SITES[@]} -eq 0 ]; then
        log_error "No se detectaron sitios activos en el stack."
        exit 1
    fi

    i=1
    for s in "${SITES[@]}"; do
        echo "  $i) $s"
        i=$((i + 1))
    done
    echo "  $i) TODOS LOS SITIOS"

    read -r -p "Selecciona una opción [1-$i]: " SITE_OPT
    if [ "$SITE_OPT" -eq "$i" ]; then
        SITE_SLUG="ALL"
    else
        IDX=$((SITE_OPT - 1))
        SITE_SLUG="${SITES[$IDX]}"
    fi
fi

# 2. Seleccionar tipo de backup
if [ -z "$BACKUP_TYPE" ]; then
    echo -e "\n${C_BOLD}[?] ¿Qué tipo de respaldo deseas generar?${C_RESET}"
    echo -e "    1) 📦 Backup COMPLETO (Todas las Bases de datos + Archivos web)"
    echo -e "    2) 🗄️  Solo Bases de Datos (.sql.gz de todas las instancias del sitio)"
    echo -e "    3) 📁 Solo Archivos Web (.tar.gz sin cachés)"
    read -r -p "Opción [1-3]: " TYPE_OPT
    case "$TYPE_OPT" in
        2) BACKUP_TYPE="db" ;;
        3) BACKUP_TYPE="files" ;;
        *) BACKUP_TYPE="full" ;;
    esac
fi

do_single_backup() {
    local SLUG="$1"
    local TYPE="$2"
    local DATE_TAG=$(date +"%Y-%m-%d_%H-%M")
    local TARGET_DIR="$BACKUPS_DIR/$SLUG"
    mkdir -p "$TARGET_DIR"

    log_step "Generando respaldo de [$SLUG] (Tipo: $TYPE)..."

    # Bases de datos (Detecta automáticamente si tiene sub-bases de datos por idioma)
    if [ "$TYPE" = "full" ] || [ "$TYPE" = "db" ]; then
        MARIADB_ROOT_PASS=$(grep -E "^MYSQL_ROOT_PASSWORD=" "$STACK_ROOT/.env" 2>/dev/null | cut -d= -f2 || echo "root_secret")
        
        # Buscar todas las bases de datos del sitio (ej: wp_misitio_db, wp_misitio_es_db, etc.)
        MATCHED_DBS=$(docker exec mariadb mariadb -u root -p"$MARIADB_ROOT_PASS" --skip-ssl -e "SHOW DATABASES LIKE 'wp\_${SLUG}\_%';" 2>/dev/null | grep -E "^wp_${SLUG}_" || true)
        
        if [ -z "$MATCHED_DBS" ]; then
            MATCHED_DBS="wp_${SLUG}_db"
        fi

        for current_db in $MATCHED_DBS; do
            DB_FILE="$TARGET_DIR/${current_db}_${DATE_TAG}.sql.gz"
            log_info "Exportando y comprimiendo base de datos ($current_db)..."
            docker exec mariadb mariadb-dump -u root -p"$MARIADB_ROOT_PASS" --skip-ssl --single-transaction --quick "$current_db" 2>/dev/null | gzip > "$DB_FILE"
            DB_SIZE=$(du -h "$DB_FILE" | cut -f1)
            log_ok "Base de datos respaldada: $(basename "$DB_FILE") ($DB_SIZE)"
        done
    fi

    # Archivos Web
    if [ "$TYPE" = "full" ] || [ "$TYPE" = "files" ]; then
        SRC_DIR="$STACK_ROOT/wp-data/$SLUG"
        FILES_ARCHIVE="$TARGET_DIR/${SLUG}_files_${DATE_TAG}.tar.gz"

        if [ -d "$SRC_DIR" ]; then
            log_info "Comprimiendo archivos web (excluyendo cachés y temporales)..."
            tar -czf "$FILES_ARCHIVE" \
                --exclude="wp-content/cache" \
                --exclude="wp-content/uploads/cache" \
                --exclude="*.log" \
                --exclude="*.tmp" \
                -C "$STACK_ROOT/wp-data" "$SLUG"
            FILES_SIZE=$(du -h "$FILES_ARCHIVE" | cut -f1)
            log_ok "Archivos web respaldados: $(basename "$FILES_ARCHIVE") ($FILES_SIZE)"
        else
            log_warn "No se encontró el directorio $SRC_DIR para respaldar archivos."
        fi
    fi

    log_ok "Respaldo de [$SLUG] guardado en: $TARGET_DIR"
}

if [ "$SITE_SLUG" = "ALL" ]; then
    SITES=($(ls -1 "$STACK_ROOT"/php/php*/pools/*.conf 2>/dev/null | xargs -n 1 basename | sed 's/\.conf$//' | grep -v "placeholder" || true))
    for s in "${SITES[@]}"; do
        do_single_backup "$s" "$BACKUP_TYPE"
    done
else
    do_single_backup "$SITE_SLUG" "$BACKUP_TYPE"
fi

log_ok "Operación de respaldo finalizada con éxito."
