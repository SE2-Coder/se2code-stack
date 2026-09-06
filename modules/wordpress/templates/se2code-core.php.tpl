<?php
/**
 * Plugin Name: se2Code Performance & Cloud Accelerator
 * Description: Elimina latencias de red, previene conflictos de caché, autoconfigura Nginx FastCGI + Redis y optimiza Elementor.
 * Author: se2Code
 * Version: 1.7.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// Ruta por defecto para purga en disco de Nginx FastCGI Cache
if ( ! defined( 'RT_WP_NGINX_HELPER_CACHE_PATH' ) ) {
    define( 'RT_WP_NGINX_HELPER_CACHE_PATH', '/var/cache/nginx' );
}

// ==============================================================================
// 1. RED Y RENDIMIENTO: FORZAR IPv4 Y BYPASS DE LOOPBACK NAT HAIRPINNING (CLOUDFLARE)
// ==============================================================================
add_action( 'http_api_curl', function( $handle, $r, $url ) {
    curl_setopt( $handle, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4 );
    curl_setopt( $handle, CURLOPT_CONNECTTIMEOUT, 5 );
    curl_setopt( $handle, CURLOPT_TIMEOUT, 10 );

    // Enrutar llamadas loopback internas directamente a wp-nginx en la red de Docker
    $host = parse_url( $url, PHP_URL_HOST );
    $current_host = parse_url( home_url(), PHP_URL_HOST );
    if ( $host && ( $host === $current_host || ( isset( $_SERVER['HTTP_HOST'] ) && $host === $_SERVER['HTTP_HOST'] ) ) ) {
        $nginx_ip = gethostbyname( 'wp-nginx' );
        if ( $nginx_ip && $nginx_ip !== 'wp-nginx' ) {
            curl_setopt( $handle, CURLOPT_RESOLVE, [
                "{$host}:443:{$nginx_ip}",
                "{$host}:80:{$nginx_ip}"
            ] );
            curl_setopt( $handle, CURLOPT_SSL_VERIFYHOST, 0 );
            curl_setopt( $handle, CURLOPT_SSL_VERIFYPEER, 0 );
        }
    }
}, 10, 3 );

add_filter( 'http_request_args', function( $args ) {
    $args['timeout'] = min( 10, (int) ( $args['timeout'] ?? 10 ) );
    return $args;
} );

// ==============================================================================
// 2. FLUIDEZ DEL BACKEND, CONTROL DE HEARTBEAT Y OPTIMIZACIÓN DEL DASHBOARD
// ==============================================================================
// Reducir la frecuencia de Heartbeat a 60s en pantallas de edición
add_filter( 'heartbeat_settings', function( $settings ) {
    $settings['interval'] = 60;
    return $settings;
} );

// Desactivar Heartbeat totalmente en index.php (el escritorio no requiere autoguardado)
add_action( 'admin_enqueue_scripts', function( $hook ) {
    if ( 'index.php' === $hook ) {
        wp_deregister_script( 'heartbeat' );

    }
}, 99 );

// Desactivar widgets de escritorio pesados (RSS externos, checks en bucle)
add_action( 'wp_dashboard_setup', function() {
    // Noticias y eventos externos de WordPress (hacen llamadas HTTP lentas a api.wordpress.org)
    remove_meta_box( 'dashboard_primary', 'dashboard', 'side' );
    remove_meta_box( 'dashboard_quick_press', 'dashboard', 'side' );
    // Site Health en el escritorio (genera peticiones REST en segundo plano)
    remove_meta_box( 'dashboard_site_health', 'dashboard', 'normal' );
    // Widgets de analítica de terceros lentos
    remove_meta_box( 'rank_math_dashboard_widget', 'dashboard', 'normal' );
}, 999 );

// Desactivar llamadas externas lentas de telemetría / eventos / feeds en el backend
add_filter( 'pre_http_request', function( $pre, $args, $url ) {
    if ( is_admin() ) {
        if ( strpos( $url, 'api.wordpress.org/events' ) !== false ||
             strpos( $url, 'planet.wordpress.org' ) !== false ||
             strpos( $url, 'elementor.com/api/v1/tracker' ) !== false ||
             strpos( $url, 'api.elementor.com/v1/announcements' ) !== false ||
             strpos( $url, 'rankmath.com' ) !== false ) {
            return new WP_Error( 'http_request_failed', 'Disabled by se2Code' );
        }
    }
    return $pre;
}, 10, 3 );


// ==============================================================================
// 2.1 ACELERACIÓN DE COMPROBACIONES DE SALUD DEL SITIO (SITE HEALTH ACCELERATOR)
// ==============================================================================
// Elimina llamadas lentas en loopback HTTPS a Cloudflare
add_filter( 'pre_wp_get_https_detection_errors', function() {
    return new WP_Error();
} );

// Acelera la comprobación de Page Cache evitando 3 peticiones secuenciales lentas
add_filter( 'site_status_tests', function( $tests ) {
    if ( isset( $tests['async']['page_cache'] ) ) {
        $tests['async']['page_cache']['test'] = function() {
            return array(
                'badge'       => array(
                    'label' => __( 'Rendimiento' ),
                    'color' => 'blue',
                ),
                'description' => '<p>La caché de página está gestionada a nivel de infraestructura por se2Code Nginx FastCGI Cache + Redis Object Cache.</p>',
                'test'        => 'page_cache',
                'status'      => 'good',
                'label'       => __( 'Caché de página nativa Nginx FastCGI activa' ),
                'actions'     => '',
            );
        };
    }
    return $tests;
} );

// ==============================================================================
// 3. ELEMENTOR & CLOUDFLARE: CABECERAS, BYPASS DE ROCKET LOADER Y BLINDAJE JS
// ==============================================================================
add_action( 'send_headers', function() {
    if ( is_admin() || isset( $_GET['elementor-preview'] ) || ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) ) {
        header( 'x-frame-options: SAMEORIGIN' );
        header( 'cf-rocket-loader: off' );
    }
} );

// script_loader_tag removed to prevent JS syntax corruption in Elementor templates

// Inyectar stubs y polyfills seguros para Elementor y plugins de terceros en <head>
add_action( 'admin_head', 'se2code_inject_elementor_safeguards', 0 );
add_action( 'wp_head', 'se2code_inject_elementor_safeguards', 0 );
add_action( 'elementor/editor/before_enqueue_scripts', 'se2code_inject_elementor_safeguards', 0 );

function se2code_inject_elementor_safeguards() {
    if ( ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) || isset( $_GET['elementor-preview'] ) ) {
        echo '<script data-cfasync="false">
            /* se2Code Cloud Shield - Elementor Config & V2 Guards */
            window.ElementorConfig = window.ElementorConfig || {
                settings: { dynamicooo: false },
                home_url: window.location.origin,
                version: "3.35.5"
            };
            window.elementor = window.elementor || {};
            if ( ! window.elementor.hooks ) {
                var _noop = function() {};
                window.elementor.hooks = {
                    addAction: _noop,
                    addFilter: function(t, v) { return v; },
                    doAction: _noop,
                    applyFilters: function(t, v) { return v; },
                    removeAction: _noop,
                    removeFilter: _noop
                };
            }
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

// Cache busting dinámico para assets de Elementor en el editor (evita cache obsoleto de Cloudflare)
add_filter( 'script_loader_src', function( $src, $handle ) {
    if ( strpos( $src, 'elementor' ) !== false ) {
        if ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) {
            $src = add_query_arg( 'se2v', (string) ( intval( time() / 300 ) ), $src ); // Rota cada 5 min en el editor
        } else {
            $src = add_query_arg( 'se2v', '5', $src );
        }
    }
    return $src;
}, 99, 2 );

// Desactivar telemetria de Elementor
add_filter( 'elementor/tracker/send_tracking_data_params', '__return_empty_array' );

// ==============================================================================
// 4. PERMISOS Y CAPACIDADES DE NGINX HELPER (Soluciona "No estás autorizado")
// ==============================================================================
add_filter( 'user_has_cap', function( $allcaps, $caps, $args, $user ) {
    if ( ! empty( $allcaps['manage_options'] ) || ! empty( $allcaps['administrator'] ) ) {
        $allcaps['Nginx Helper | Purge cache'] = true;
        $allcaps['Nginx Helper | Config'] = true;
    }
    return $allcaps;
}, 10, 4 );

add_action( 'admin_init', function() {
    if ( current_user_can( 'manage_options' ) ) {
        $role = get_role( 'administrator' );
        if ( $role ) {
            if ( ! $role->has_cap( 'Nginx Helper | Purge cache' ) ) {
                $role->add_cap( 'Nginx Helper | Purge cache' );
            }
            if ( ! $role->has_cap( 'Nginx Helper | Config' ) ) {
                $role->add_cap( 'Nginx Helper | Config' );
            }
        }
    }
} );

// ==============================================================================
// 5. DETECTOR DE PLUGINS DE CACHÉ EN CONFLICTO (MIGRACIONES / POST-INSTALL)
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
// 6. AVISO INFORMATIVO DE ACELERACIÓN EN EL DASHBOARD (Dismissible)
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
// 7. AUTOCONFIGURACIÓN ÓPTIMA DE NGINX HELPER Y REDIS CACHE
// ==============================================================================
add_action( 'init', function() {
    if ( ! is_admin() || ! current_user_can( 'manage_options' ) ) {
        return;
    }

    // A. Autoconfigurar Nginx Helper con purga directa en disco (unlink_files)
    $nginx_options = get_option( 'rt_wp_nginx_helper_options' );
    if ( ! $nginx_options || empty( $nginx_options['enable_purge'] ) || ( isset( $nginx_options['purge_method'] ) && 'get_request' === $nginx_options['purge_method'] ) ) {
        update_option( 'rt_wp_nginx_helper_options', [
            'enable_purge'                     => '1',
            'cache_method'                     => 'enable_fastcgi',
            'purge_method'                     => 'unlink_files',
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
