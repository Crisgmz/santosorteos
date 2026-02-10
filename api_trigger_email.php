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
$boletos = $data['boletos'] ?? $data['tickets'] ?? $data['ticket_id'] ?? '';
$rutaPDF = $data['ruta_pdf'] ?? '';
$telefono = $data['telefono'] ?? '';
$nombreSorteo = $data['nombre_sorteo'] ?? 'Evento Multisorteos';
$montoTotal = $data['monto_total'] ?? $data['monto'] ?? '';
$metodoPago = $data['metodo_pago'] ?? $data['banco'] ?? 'N/A';

if (!$email || !$boletos) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Faltan email o boletos']);
    exit;
}

// === VALIDACIÓN: SI ES NULL O "ORDEN-...", BUSCAR EN SUPABASE ===
if (strpos($boletos, 'Orden-') === 0) {
    // Es un ID de orden (formato antiguo o fallback), consultamos Supabase
    $orderId = str_replace('Orden-', '', $boletos);

    // Configuración Supabase (Anon Key es suficiente si RLS permite leer)
    $supabaseUrl = 'https://ocnztzrtzjpfqckqrzkq.supabase.co';
    $supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9jbnp0enJ0empwZnFja3FyemtxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE1OTg5MDUsImV4cCI6MjA3NzE3NDkwNX0.lLtJ4bPPAHfHeabFbdKjfZAwSOq-MrCPm0Kk-QLMLj4';

    // Agregamos monto_total y banco a la seleccion
    $url = "$supabaseUrl/rest/v1/reservados?order_id=eq.$orderId&select=numeros,buyer_telefono,sorteo_nombre,monto_total,banco";

    $opts = [
        "http" => [
            "method" => "GET",
            "header" => [
                "apikey: $supabaseKey",
                "Authorization: Bearer $supabaseKey",
                "Content-Type: application/json"
            ]
        ]
    ];

    $context = stream_context_create($opts);
    $response = file_get_contents($url, false, $context);

    if ($response) {
        $result = json_decode($response, true);
        if (!empty($result) && isset($result[0])) {
            $record = $result[0];

            // Actualizar boletos desde DB
            $nums = $record['numeros'] ?? [];
            if (is_array($nums)) {
                $boletos = implode(', ', $nums);
            } else {
                $boletos = str_replace(['[', ']', '"'], '', $nums);
            }

            // Actualizar telefono y sorteo si faltaban
            if (empty($telefono) && !empty($record['buyer_telefono'])) {
                $telefono = $record['buyer_telefono'];
            }
            // (Opcional) Nombre sorteo a veces no guardas nombre en reservados, pero si esta:
            if (isset($record['sorteo_nombre']) && !empty($record['sorteo_nombre'])) {
                $nombreSorteo = $record['sorteo_nombre'];
            }

            // Actualizar monto y banco
            if (empty($montoTotal) && isset($record['monto_total'])) {
                $montoTotal = $record['monto_total'];
            }
            if (($metodoPago == 'N/A' || empty($metodoPago)) && isset($record['banco'])) {
                $metodoPago = $record['banco'];
            }

            writeEmailLog("✅ Recuperados datos reales de Supabase para Orden $orderId: Boletos [$boletos], Tel [$telefono], Monto [$montoTotal]");
        } else {
            writeEmailLog("⚠️ No se encontro orden $orderId en Supabase");
        }
    } else {
        writeEmailLog("⚠️ Fallo conexion a Supabase para verificar orden $orderId");
    }
}

// 3. (Opcional) Generar ruta del PDF si no viene
// Si tus PDFs se guardan en una ruta predecible:
if (!$rutaPDF) {
    // Si viene mas de un boleto, quiza no tengamos PDF unico, o si.
    // Usamos el primer numero para intentar buscar algo, o lo dejamos vacio.
    $primerBoleto = explode(',', $boletos)[0];
    if ($primerBoleto) {
        $rutaPDF = __DIR__ . "/boletos/boleto_" . trim($primerBoleto) . ".pdf";
    }
}

// 4. Enviar
$resultado = enviarBoletoPorEmail($email, $nombre, $boletos, $rutaPDF, $telefono, $nombreSorteo, $montoTotal, $metodoPago);

if ($resultado) {
    echo json_encode(['success' => true]);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error enviando el correo (ver email_debug.log)']);
}
?>
