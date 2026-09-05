<?php
/**
 * Plugin Name: se2Code Performance & Cloud Accelerator
 * Description: Elimina latencias de red (fuerza IPv4 en cURL), optimiza el editor Elementor y previene cuelgues.
 * Author: se2Code
 * Version: 1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// 1. Forzar IPv4 en todas las peticiones cURL externas de WordPress (Evita timeouts de 20s en VPS)
add_action( 'http_api_curl', function( $handle ) {
    curl_setopt( $handle, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4 );
    curl_setopt( $handle, CURLOPT_CONNECTTIMEOUT, 5 );
    curl_setopt( $handle, CURLOPT_TIMEOUT, 10 );
} );

// 2. Cabeceras especiales para Elementor y Cloudflare (Carga de editor 100% fluida)
add_action( 'send_headers', function() {
    if ( isset( $_GET['elementor-preview'] ) || ( isset( $_GET['action'] ) && 'elementor' === $_GET['action'] ) ) {
        header( 'X-Frame-Options: SAMEORIGIN' );
        header( 'cf-rocket-loader: off' );
    }
} );

// 3. Desactivar telemetría externa de Elementor que frena la navegación en el wp-admin
add_filter( 'elementor/tracker/send_tracking_data_params', '__return_empty_array' );
