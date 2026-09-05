<?php
/**
 * Plugin Name: se2Code Performance & Cloud Accelerator
 * Description: Elimina latencias de red, previene conflictos de caché, autoconfigura Nginx FastCGI + Redis y optimiza Elementor.
 * Author: se2Code
 * Version: 1.2.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// ==============================================================================
// 1. RED: FORZAR IPv4 EN cURL (Previene cuelgues de 20s en VPS con IPv6 inactiva)
// ==============================================================================
add_action( 'http_api_curl', function( $handle ) {
    curl_setopt( $handle, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4 );
    curl_setopt( $handle, CURLOPT_CONNECTTIMEOUT, 5 );
    curl_setopt( $handle, CURLOPT_TIMEOUT, 10 );
} );

// ==============================================================================
// 2. ELEMENTOR & CLOUDFLARE: CABECERAS Y BYPASS DE ROCKET LOADER
// ==============================================================================
add_action( 'send_headers', function() {
    if ( is_admin() || isset( $_GET['elementor-preview'] ) || ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) ) {
        header( 'x-frame-options: SAMEORIGIN' );
        header( 'cf-rocket-loader: off' );
    }
} );

add_filter( 'script_loader_tag', function( $tag, $handle ) {
    if ( is_admin() || ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) ) {
        if ( strpos( $tag, 'data-cfasync' ) === false ) {
            $tag = str_replace( '<script ', '<script data-cfasync="false" ', $tag );
        }
    }
    return $tag;
}, 10, 2 );

// Polyfill seguro de Elementor v2
add_action( 'admin_head', 'se2code_inject_elementor_v2_poly', 1 );
add_action( 'wp_head', 'se2code_inject_elementor_v2_poly', 1 );
add_action( 'elementor/editor/before_enqueue_scripts', 'se2code_inject_elementor_v2_poly', 1 );

function se2code_inject_elementor_v2_poly() {
    if ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) {
        echo '<script data-cfasync="false">
            window.elementorV2 = window.elementorV2 || {};
            window.elementorV2.editorCurrentUser = window.elementorV2.editorCurrentUser || {
                useCurrentUserCapabilities: function() { return { isAdmin: true, canUser: function() { return true; }, capabilities: ["manage_options"] }; },
                useCurrentUser: function() { return { data: { capabilities: ["manage_options"] } }; },
                useSuppressedMessage: function() { return [false, function() {}]; },
                useUpdateCurrentUser: function() { return { mutate: function() {} }; },
                ensureUser: async function() { return { capabilities: ["manage_options"] }; },
                getCurrentUser: function() { return { capabilities: ["manage_options"] }; },
                onSetUser: function() { return function() {}; }
            };
        </script>';
    }
}

// Invalidar caché CDN de Cloudflare en scripts Elementor
add_filter( 'script_loader_src', function( $src, $handle ) {
    if ( strpos( $src, 'elementor' ) !== false && strpos( $src, 'ver=' ) !== false ) {
        $src = add_query_arg( 'se2v', '3', $src );
    }
    return $src;
}, 99, 2 );

// Desactivar telemetria de Elementor
add_filter( 'elementor/tracker/send_tracking_data_params', '__return_empty_array' );

// ==============================================================================
// 3. DETECTOR DE PLUGINS DE CACHÉ EN CONFLICTO (MIGRACIONES / POST-INSTALL)
// ==============================================================================
add_action( 'admin_notices', function() {
    if ( ! current_user_can( 'activate_plugins' ) ) {
        return;
    }

    $conflicting_plugins = [
        'wp-rocket/wp-rocket.php'             => 'WP Rocket',
        'litespeed-cache/litespeed-cache.php' => 'LiteSpeed Cache',
        'w3-total-cache/w3-total-cache.php'   => 'W3 Total Cache',
        'wp-super-cache/wp-cache.php'         => 'WP Super Cache',
        'wp-fastest-cache/wpFastestCache.php' => 'WP Fastest Cache',
        'breeze/breeze.php'                   => 'Breeze Cache',
        'sg-cachepress/sg-cachepress.php'     => 'Speed Optimizer (SiteGround)',
        'cache-enabler/cache-enabler.php'     => 'Cache Enabler',
        'powered-cache/powered-cache.php'     => 'Powered Cache',
        'comet-cache/comet-cache.php'         => 'Comet Cache',
        'hyper-cache/hyper-cache.php'         => 'Hyper Cache',
    ];

    require_once ABSPATH . 'wp-admin/includes/plugin.php';

    $detected = [];
    foreach ( $conflicting_plugins as $file => $name ) {
        if ( is_plugin_active( $file ) ) {
            $detected[] = $name;
        }
    }

    if ( ! empty( $detected ) ) {
        echo '<div class="notice notice-error" style="border-left: 5px solid #d63638; padding: 15px 20px; margin: 20px 0; background: #fff; box-shadow: 0 2px 6px rgba(0,0,0,0.08); border-radius: 4px;">';
        echo '<div style="display: flex; align-items: flex-start; gap: 14px;">';
        echo '<span class="dashicons dashicons-warning" style="font-size: 32px; width: 32px; height: 32px; color: #d63638; flex-shrink: 0; margin-top: 2px;"></span>';
        echo '<div>';
        echo '<h3 style="margin: 0 0 8px 0; font-size: 16px; color: #d63638; font-weight: 700;">se2Code Stack — Conflicto de Plugins de Caché Detectado</h3>';
        echo '<p style="margin: 0 0 10px 0; font-size: 13.5px; line-height: 1.5; color: #1d2327;">';
        echo 'Se detectó activo el plugin: <strong style="color: #d63638;">' . esc_html( implode( ', ', $detected ) ) . '</strong>.<br>';
        echo 'Tu servidor se2Code ya cuenta con <strong>Nginx FastCGI Cache</strong> a nivel de infraestructura y <strong>Redis Object Cache</strong> en memoria RAM.';
        echo '</p>';
        echo '<p style="margin: 0; font-size: 12.5px; line-height: 1.5; color: #50575e; background: #fdf2f2; padding: 10px 14px; border-radius: 4px; border: 1px solid #f8d7da;">';
        echo '⚠️ <strong>ADVERTENCIA:</strong> <em>Los plugins de caché externos son contraproducentes en este servidor: causan conflictos de cabeceras HTTP, sobreescritura de microcaché, problemas con carritos/sesiones y degradan la velocidad de carga. Si realizaste una <strong>migración</strong>, por favor desactiva y desinstala estos plugins.</em>';
        echo '</p>';
        echo '</div>';
        echo '</div>';
        echo '</div>';
    }
} );

// ==============================================================================
// 4. AVISO INFORMATIVO DE ACELERACIÓN EN EL DASHBOARD (Dismissible)
// ==============================================================================
add_action( 'admin_notices', function() {
    $screen = get_current_screen();
    if ( $screen && 'dashboard' === $screen->id && current_user_can( 'manage_options' ) ) {
        $dismissed = get_user_meta( get_current_user_id(), 'se2code_cache_notice_dismissed', true );
        if ( ! $dismissed ) {
            echo '<div class="notice notice-info is-dismissible se2code-cache-notice" style="border-left: 5px solid #00a32a; padding: 12px 18px; margin: 15px 0; background: #f0fdf4; border-color: #00a32a;">';
            echo '<div style="display: flex; align-items: center; gap: 10px;">';
            echo '<span class="dashicons dashicons-performance" style="font-size: 24px; width: 24px; height: 24px; color: #00a32a;"></span>';
            echo '<div>';
            echo '<h4 style="margin: 0 0 4px 0; font-size: 14px; color: #15803d; font-weight: 700;">se2Code Server Stack — Aceleración Nativa Activa</h4>';
            echo '<p style="margin: 0; font-size: 13px; color: #166534;">';
            echo 'Este sitio está optimizado con <strong>Nginx FastCGI Cache</strong> + <strong>Redis Object Cache</strong>. No requiere ni se recomienda instalar plugins de caché adicionales (como WP Rocket, LiteSpeed o W3TC).';
            echo '</p>';
            echo '</div>';
            echo '</div>';
            echo '</div>';
            echo '<script>
                jQuery(document).on("click", ".se2code-cache-notice .notice-dismiss", function() {
                    jQuery.post(ajaxurl, { action: "se2code_dismiss_cache_notice" });
                });
            </script>';
        }
    }
} );

add_action( 'wp_ajax_se2code_dismiss_cache_notice', function() {
    update_user_meta( get_current_user_id(), 'se2code_cache_notice_dismissed', 1 );
    wp_die();
} );

// ==============================================================================
// 5. AUTOCONFIGURACIÓN ÓPTIMA DE NGINX HELPER Y REDIS CACHE
// ==============================================================================
add_action( 'init', function() {
    if ( ! is_admin() || ! current_user_can( 'manage_options' ) ) {
        return;
    }

    // A. Autoconfigurar Nginx Helper con la configuración óptima FastCGI si no tiene opciones
    $nginx_options = get_option( 'rt_wp_nginx_helper_options' );
    if ( ! $nginx_options || empty( $nginx_options['enable_purge'] ) ) {
        update_option( 'rt_wp_nginx_helper_options', [
            'enable_purge'                     => '1',
            'cache_method'                     => 'enable_fastcgi',
            'purge_method'                     => 'get_request',
            'enable_map'                       => 0,
            'enable_log'                       => 0,
            'log_level'                        => 'INFO',
            'log_filesize'                     => '5',
            'enable_stamp'                     => 0,
            'purge_homepage_on_edit'           => '1',
            'purge_homepage_on_del'            => '1',
            'purge_archive_on_edit'            => '1',
            'purge_archive_on_del'             => '1',
            'purge_archive_on_new_comment'     => 0,
            'purge_archive_on_deleted_comment' => '1',
            'purge_page_on_mod'                => '1',
            'purge_page_on_new_comment'        => '1',
            'purge_page_on_deleted_comment'    => '1',
            'purge_feeds'                      => '1',
            'purge_amp_urls'                   => '1',
        ] );
    }

    // B. Activar drop-in de Redis si redis-cache está activo y falta object-cache.php
    $dropin_path = WP_CONTENT_DIR . '/object-cache.php';
    $plugin_dropin = WP_CONTENT_DIR . '/plugins/redis-cache/includes/object-cache.php';
    if ( ! file_exists( $dropin_path ) && file_exists( $plugin_dropin ) ) {
        @copy( $plugin_dropin, $dropin_path );
    }
} );
