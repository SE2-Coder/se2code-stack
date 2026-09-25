<?php
/**
 * se2Code Stack - Procesador Ligero de Formularios de Contacto
 * Seguro, sanitizado y con persistencia local en JSON.
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

// 1. Validar Método HTTP
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Método no permitido. Solo se aceptan peticiones POST.'
    ]);
    exit;
}

// 2. Trampa anti-bots (Honeypot)
if (!empty($_POST['website'])) {
    // Si un bot llenó este campo invisible, responder éxito simulado
    echo json_encode([
        'success' => true,
        'message' => '¡Mensaje recibido correctamente!'
    ]);
    exit;
}

// 3. Capturar y Sanitizar Entradas
$name = isset($_POST['name']) ? trim(strip_tags((string)$_POST['name'])) : '';
$email = isset($_POST['email']) ? filter_var(trim((string)$_POST['email']), FILTER_VALIDATE_EMAIL) : false;
$phone = isset($_POST['phone']) ? trim(strip_tags((string)$_POST['phone'])) : '';
$message = isset($_POST['message']) ? trim(strip_tags((string)$_POST['message'])) : '';

// 4. Validar Campos Obligatorios
if (empty($name) || mb_strlen($name) < 2) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Por favor ingresa un nombre válido.'
    ]);
    exit;
}

if (!$email) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Por favor ingresa un correo electrónico válido.'
    ]);
    exit;
}

if (empty($message) || mb_strlen($message) < 5) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Por favor escribe un mensaje de al menos 5 caracteres.'
    ]);
    exit;
}

// 5. Preparar Registro de Lead
$lead = [
    'timestamp'  => date('Y-m-d H:i:s'),
    'ip_address' => $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? 'desconocida',
    'name'       => $name,
    'email'      => $email,
    'phone'      => $phone,
    'message'    => $message
];

// 6. Guardar en archivo local seguro protegido por Nginx (.json está bloqueado)
$leadsFile = __DIR__ . '/leads.json';
$leads = [];

if (file_exists($leadsFile)) {
    $currentContent = file_get_contents($leadsFile);
    if (!empty($currentContent)) {
        $decoded = json_decode($currentContent, true);
        if (is_array($decoded)) {
            $leads = $decoded;
        }
    }
}

$leads[] = $lead;
file_put_contents($leadsFile, json_encode($leads, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE), LOCK_EX);

// 7. Notificación opcional por correo (si sendmail o postfix están activos)
$adminEmail = 'admin@' . ($_SERVER['SERVER_NAME'] ?? 'localhost');
$subject = "Nuevo Lead desde Landing Page: {$name}";
$emailBody = "Has recibido un nuevo contacto desde tu landing page:\n\n"
           . "Nombre:   {$name}\n"
           . "Email:    {$email}\n"
           . "Teléfono: {$phone}\n"
           . "Fecha:    {$lead['timestamp']}\n\n"
           . "Mensaje:\n{$message}\n";

$headers = "From: no-reply@" . ($_SERVER['SERVER_NAME'] ?? 'localhost') . "\r\n"
         . "Reply-To: {$email}\r\n"
         . "X-Mailer: se2Code-Landing/1.0";

@mail($adminEmail, $subject, $emailBody, $headers);

// 8. Respuesta Exitosa
echo json_encode([
    'success' => true,
    'message' => '¡Muchas gracias! Hemos recibido tu mensaje y te contactaremos en breve.'
]);
