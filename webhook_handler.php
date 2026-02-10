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
// IMPORTANTE: 'numeros' puede venir como array o string.
$rawBoletos = $record['numeros'] ?? $record['numero'] ?? $record['id'];
if (is_array($rawBoletos)) {
    $boletos = implode(', ', $rawBoletos);
} else {
    // Limpiar caracteres extraños si viene como string JSON "[1,2]"
    $boletos = str_replace(['[', ']', '"'], '', $rawBoletos);
}
$sorteoId = $record['sorteo_id'] ?? 0;

// Intentar obtener telefono
$telefono = $record['buyer_telefono'] ?? $record['telefono'] ?? $record['celular'] ?? $record['phone'] ?? '';

// Intentar obtener nombre del sorteo
$nombreSorteo = $record['sorteo_nombre'] ?? $record['nombre_sorteo'] ?? 'Evento Multisorteos';

// Intentar obtener montos y metodo de pago
$montoTotal = $record['monto_total'] ?? '';
$metodoPago = $record['banco'] ?? 'N/A';

writeEmailLog("📦 Procesando orden para: $nombreCliente ($emailCliente) - Boletos: $boletos - Tel: $telefono - Monto: $montoTotal");

if (!$emailCliente) {
    writeEmailLog("⚠️ La orden no tiene email asociado. Saltando envío.");
    exit('Sin email');
}

// 3. Definir la ruta del PDF
$rutaPDF = __DIR__ . "/boletos/boleto_" . $boletos . ".pdf";

// 4. Enviar el correo
$resultado = enviarBoletoPorEmail($emailCliente, $nombreCliente, $boletos, $rutaPDF, $telefono, $nombreSorteo, $montoTotal, $metodoPago);

if ($resultado) {
    echo "Correo enviado correctamente";
} else {
    http_response_code(500);
    echo "Fallo al enviar correo";
}
?>
