<?php
// api_trigger_email.php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
header('Content-Type: application/json');

// Manejar preflight request de CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require 'enviar_email_helper.php';

// 1. Recibir JSON desde Flutter
$input = file_get_contents('php://input');
$data = json_decode($input, true);

if (!is_array($data)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'JSON invalido']);
    exit;
}

// 2. Validar datos
$email = $data['email'] ?? '';
$nombre = $data['nombre'] ?? '';
$ticketId = $data['ticket_id'] ?? '';
$rutaPDF = $data['ruta_pdf'] ?? ''; // Opcional, o generada aqui

if (!$email || !$ticketId) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Faltan email o ticket_id']);
    exit;
}

// 3. (Opcional) Generar ruta del PDF si no viene
// Si tus PDFs se guardan en una ruta predecible:
if (!$rutaPDF) {
    $rutaPDF = __DIR__ . "/boletos/boleto_" . $ticketId . ".pdf";
}

// 4. Enviar
$resultado = enviarBoletoPorEmail($email, $nombre, $ticketId, $rutaPDF);

if ($resultado) {
    echo json_encode(['success' => true]);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error enviando el correo (ver email_debug.log)']);
}
?>
