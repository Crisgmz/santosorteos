<?php
// webhook_handler.php
// Sube este archivo a tu servidor junto con enviar_email_helper.php y la carpeta vendor

require 'enviar_email_helper.php';

// 1. Recibir la notificación de Supabase
$input = file_get_contents('php://input');
$data = json_decode($input, true);

// Log para depuración
writeEmailLog("🔔 Webhook recibido: " . substr($input, 0, 100) . "...");

// Validar que sea un evento de nueva reserva (INSERT)
if (!isset($data['type']) || $data['type'] !== 'INSERT') {
    writeEmailLog("ℹ️ Ignorando evento tipo: " . ($data['type'] ?? 'desconocido'));
    exit('Evento ignorado');
}

// 2. Extraer datos del registro insertado en la tabla 'reservados'
$record = $data['record'];

$emailCliente = $record['buyer_email'] ?? null;
$nombreCliente = $record['buyer_nombre'] ?? 'Cliente';
$ticketId = $record['numero'] ?? $record['id']; // Usar número de boleto o ID interno
$sorteoId = $record['sorteo_id'];

writeEmailLog("📦 Procesando orden para: $nombreCliente ($emailCliente) - Ticket: $ticketId");

if (!$emailCliente) {
    writeEmailLog("⚠️ La orden no tiene email asociado. Saltando envío.");
    exit('Sin email');
}

// 3. Definir la ruta del PDF
// IMPORTANTE: Aquí asumo que tus PDFs ya existen o se generan con este nombre
// Si no existen, el correo se enviará SIN adjunto.
$rutaPDF = __DIR__ . "/boletos/boleto_" . $ticketId . ".pdf";

// 4. Enviar el correo
$resultado = enviarBoletoPorEmail($emailCliente, $nombreCliente, $ticketId, $rutaPDF);

if ($resultado) {
    echo "Correo enviado correctamente";
} else {
    http_response_code(500);
    echo "Fallo al enviar correo";
}
?>