<?php
/**
 * Plugin Name: se2Code Performance & Cloud Accelerator
 * Description: Elimina latencias de red (IPv4 forzado), optimiza Elementor y previene cuelgues.
 * Author: se2Code
 * Version: 1.1.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// 1. Forzar IPv4 en todas las peticiones cURL (Evita timeouts de 20s en APIs/WordPress.org)
add_action( 'http_api_curl', function( $handle ) {
    curl_setopt( $handle, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4 );
    curl_setopt( $handle, CURLOPT_CONNECTTIMEOUT, 5 );
    curl_setopt( $handle, CURLOPT_TIMEOUT, 10 );
} );

// 2. Cabeceras y prevención de Rocket Loader en Elementor y Admin
add_action( 'send_headers', function() {
    if ( is_admin() || isset( $_GET['elementor-preview'] ) || ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) ) {
        header( 'x-frame-options: SAMEORIGIN' );
        header( 'cf-rocket-loader: off' );
    }
} );

// 3. Desactivar Rocket Loader en tags de scripts para evitar que reordene la carga de React/Elementor
add_filter( 'script_loader_tag', function( $tag, $handle ) {
    if ( is_admin() || ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) ) {
        if ( strpos( $tag, 'data-cfasync' ) === false ) {
            $tag = str_replace( '<script ', '<script data-cfasync="false" ', $tag );
        }
    }
    return $tag;
}, 10, 2 );

// 4. Inyectar polyfill seguro de Elementor v2 antes de que carguen los scripts
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

// 5. Cache busting de Cloudflare para scripts de Elementor (fuerza carga de versión parcheada)
add_filter( 'script_loader_src', function( $src, $handle ) {
    if ( strpos( $src, 'elementor' ) !== false && strpos( $src, 'ver=' ) !== false ) {
        $src = add_query_arg( 'se2v', '3', $src );
    }
    return $src;
}, 99, 2 );

// 6. Desactivar telemetria de Elementor
add_filter( 'elementor/tracker/send_tracking_data_params', '__return_empty_array' );
