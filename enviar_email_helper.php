<?php
// enviar_email_helper.php
// Helper para enviar correos con PHPMailer (sin composer).

// Posibles rutas donde buscar la libreria. Se prioriza /phpmailer/src.
$possiblePaths = [
    __DIR__ . '/PHPMailer/src/',          // <--- ESTA es la que tienes en tu imagen
    __DIR__ . '/phpmailer/src/',
    __DIR__ . '/lib/PHPMailer/src/',
    __DIR__ . '/ejemplo de email/lib/PHPMailer/src/',
    __DIR__ . '/vendor/phpmailer/phpmailer/src/',
];

$baseLibPath = null;
foreach ($possiblePaths as $path) {
    if (file_exists($path . 'PHPMailer.php')) {
        $baseLibPath = $path;
        break;
    }
}

// Carga manual de clases
if ($baseLibPath) {
    require_once $baseLibPath . 'Exception.php';
    require_once $baseLibPath . 'PHPMailer.php';
    require_once $baseLibPath . 'SMTP.php';
} elseif (file_exists(__DIR__ . '/vendor/autoload.php')) {
    // Intento final con autoload global
    require __DIR__ . '/vendor/autoload.php';
} else {
    $pathsList = implode(', ', $possiblePaths);
    error_log("Mailer error: PHPMailer no encontrado. Revisar rutas: $pathsList");
    http_response_code(500);
    die("Mailer no configurado: falta libreria PHPMailer.");
}

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

function writeEmailLog(string $message): void
{
    try {
        file_put_contents(__DIR__ . '/email_debug.log', "[" . date('Y-m-d H:i:s') . "] $message" . PHP_EOL, FILE_APPEND);
    } catch (\Throwable $e) {
        // Ignorar errores de escritura de log.
    }
}

/**
 * Envia un boleto por email con un PDF adjunto.
 */
function enviarBoletoPorEmail(
    string $emailCliente,
    string $nombreCliente,
    string $boletos,
    string $rutaPDF,
    string $telefono = '',
    string $nombreSorteo = 'Evento',
    string $montoTotal = '',
    string $metodoPago = 'N/A'
): bool {
    writeEmailLog("Inicio de envio -> $emailCliente (Boletos: $boletos)");

    // Configuracion SMTP
    $SMTP_HOST = 'mail.multisorteos.com';
    $SMTP_USER = 'boletos@multisorteos.com';
    $SMTP_PASS = 'Noviembre0824@';
    $FROM_EMAIL = 'boletos@multisorteos.com';
    $FROM_NAME = 'Su orden ha sido realizada - Multisorteos';
    $USE_SSL_465 = true; // si falla 465/SSL, se intentara 587/STARTTLS automaticamente
    $ALLOW_SELF_SIGNED = true; // algunos hostings usan certificados autofirmados

    $mail = new PHPMailer(true);

    try {
        $mail->CharSet = 'UTF-8';
        $mail->isSMTP();
        $mail->Host = $SMTP_HOST;
        $mail->SMTPAuth = true;
        $mail->Username = $SMTP_USER;
        $mail->Password = $SMTP_PASS;
        // Log detallado
        $mail->SMTPDebug = 2;
        $mail->Debugoutput = function ($str, $level) {
            writeEmailLog("DEBUG[$level] $str");
        };

        if ($ALLOW_SELF_SIGNED) {
            $mail->SMTPOptions = [
                'ssl' => [
                    'verify_peer' => false,
                    'verify_peer_name' => false,
                    'allow_self_signed' => true,
                ],
            ];
        }

        $useTls = false;
        $attempted = [];

        $setTransport = function ($secure, $port) use ($mail, &$attempted) {
            $mail->SMTPSecure = $secure;
            $mail->Port = $port;
            $attempted[] = "$secure:$port";
        };

        if ($USE_SSL_465) {
            $setTransport(PHPMailer::ENCRYPTION_SMTPS, 465);
        } else {
            $setTransport(PHPMailer::ENCRYPTION_STARTTLS, 587);
            $useTls = true;
        }

        // Remitente y destinatario
        $mail->setFrom($FROM_EMAIL, $FROM_NAME);
        $mail->addAddress($emailCliente, $nombreCliente);

        // Adjunto PDF (solo si existe y es uno solo, si son multiples podria ser complejo, aqui asumimos que la rutaPDF es valida o se omite)
        if (!empty($rutaPDF) && file_exists($rutaPDF)) {
            $mail->addAttachment($rutaPDF);
            writeEmailLog("PDF adjuntado: $rutaPDF");
        } else {
            writeEmailLog("PDF no encontrado en: $rutaPDF");
        }

        // Asunto
        $mail->Subject = "Su orden para $nombreSorteo ha sido confirmada";
        $mail->isHTML(true);

        // Variables para template
        $safeNombre = htmlspecialchars($nombreCliente, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $safeSorteo = htmlspecialchars($nombreSorteo, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $fecha = date('d/m/Y');

        // Calculos y Formatos
        $linkBoleto = "https://multisorteos.com/";
        if (!empty($telefono)) {
            $linkBoleto .= "?phone=" . $telefono;
        }

        // Formatear boletos
        $boletosVisual = $boletos;
        $cantidadBoletos = 1;
        if (preg_match('/^[0-9, ]+$/', $boletos)) {
            $parts = explode(',', $boletos);
            $cantidadBoletos = count($parts);
            $formatted = array_map(function ($p) {
                return '#' . trim($p);
            }, $parts);
            $boletosVisual = implode(', ', $formatted);
        } else {
            // Si no es numerico puro, intentar contar por comas
            $cantidadBoletos = substr_count($boletos, ',') + 1;
        }

        $montoVisual = $montoTotal ? "RD$ " . number_format((float) $montoTotal, 2) : "N/A";

        // Imagen Logo (Embedded CID)
        // ruta fisica donde esta el logo en el servidor. Ajustar si es necesario.
        // Se asume que esta en la misma carpeta o subcarpeta 'imagenes'
        $rutaLogo = __DIR__ . '/assets/imagenes/logo_completo.png';
        $cidLogo = 'logo_multisorteos';

        if (file_exists($rutaLogo)) {
            $mail->addEmbeddedImage($rutaLogo, $cidLogo, 'logo_completo.png');
        } else {
            writeEmailLog("Logo no encontrado en: $rutaLogo");
        }

        $html = <<<HTML
<!doctype html>
<html lang="es">
<body style="font-family:'Helvetica Neue', Helvetica, Arial, sans-serif; background-color:#f4f4f4; margin:0; padding:0; color:#333;">
<div style="max-width:600px; margin:20px auto; background-color:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 8px rgba(0,0,0,0.05);">

    <!-- Header Azul con Logo -->
    <div style="background-color:#ffffff; padding:20px 20px; text-align:center; border-bottom: 3px solid #007bff;">
        <img src="cid:{$cidLogo}" alt="Multisorteos Logo" style="max-width:200px; height:auto; display:block; margin:0 auto;">
    </div>
    <div style="background-color:#007bff; padding:15px; text-align:center;">
         <h1 style="color:#ffffff; margin:0; font-size:22px; font-weight:700; text-transform:uppercase; letter-spacing:1px;">¡Orden Confirmada!</h1>
    </div>

    <!-- Contenido Principal -->
    <div style="padding:40px 30px;">
        <h2 style="color:#2c3e50; margin-top:0; font-size:20px;">Hola, {$safeNombre}</h2>
        
        <p style="font-size:15px; line-height:1.6; color:#555;">
            Hemos procesado su orden correctamente. Aquí están los detalles de su participación para <strong>{$safeSorteo}</strong>.
        </p>

        <!-- Bloque de Boletos -->
        <div style="background-color:#f8faff; border: 1px solid #e1e8ed; border-radius:8px; padding:25px; margin:25px 0; text-align:center;">
            <p style="margin:0 0 10px 0; font-size:13px; text-transform:uppercase; color:#007bff; font-weight:800; letter-spacing:0.5px;">SUS BOLETOS OFICIALES</p>
            <p style="margin:0; font-size:24px; font-weight:bold; color:#2c3e50; letter-spacing:1px;">
                {$boletosVisual}
            </p>
        </div>

        <!-- Boton de Accion -->
        <div style="text-align:center; margin:35px 0;">
            <a href="{$linkBoleto}" style="background-color:#28a745; color:#ffffff; padding:14px 30px; text-decoration:none; border-radius:6px; font-weight:bold; font-size:16px; display:inline-block; box-shadow: 0 4px 6px rgba(40, 167, 69, 0.2);">
                VER BOLETO DIGITAL
            </a>
            <p style="margin-top:15px; font-size:13px; color:#999;">
                O visite: <a href="{$linkBoleto}" style="color:#007bff; text-decoration:none;">{$linkBoleto}</a>
            </p>
        </div>

        <!-- Tabla Resumen -->
        <div style="border-top:1px solid #eeeeee; margin-top:40px; padding-top:20px;">
            <h3 style="color:#2c3e50; font-size:16px; margin-bottom:15px; text-transform:uppercase; font-weight:700;">Resumen de la orden</h3>
            
            <table style="width:100%; border-collapse:collapse; font-size:14px;">
                <thead>
                    <tr style="background-color:#f9f9f9; border-bottom:2px solid #eaeaea;">
                        <th style="padding:10px; text-align:left; color:#666; font-weight:600;">Concepto</th>
                        <th style="padding:10px; text-align:right; color:#666; font-weight:600;">Total</th>
                    </tr>
                </thead>
                <tbody>
                    <tr style="border-bottom:1px solid #f1f1f1;">
                        <td style="padding:12px; color:#333;">
                            <strong>{$safeSorteo}</strong><br>
                            <span style="font-size:12px; color:#888;">Cantidad: {$cantidadBoletos} boletos</span>
                        </td>
                        <td style="padding:12px; text-align:right; color:#333; font-weight:bold;">{$montoVisual}</td>
                    </tr>
                </tbody>
                <tfoot>
                     <tr>
                        <td style="padding:12px; text-align:right; color:#666;">Método de Pago:</td>
                        <td style="padding:12px; text-align:right; color:#333;">{$metodoPago}</td>
                    </tr>
                    <tr style="background-color:#fdfdfd;">
                        <td style="padding:12px; text-align:right; font-weight:bold; color:#2c3e50; font-size:16px;">Total Pagado:</td>
                        <td style="padding:12px; text-align:right; font-weight:bold; color:#28a745; font-size:16px;">{$montoVisual}</td>
                    </tr>
                </tfoot>
            </table>
        </div>

        <!-- Footer Info Extra -->
        <div style="background-color:#fff8e1; padding:15px; border-radius:6px; margin-top:30px; border:1px solid #ffe0b2;">
            <p style="margin:0; font-size:13px; color:#8d6e63; text-align:center;">
                <strong>Recuerde:</strong> La fecha y hora del evento están sujetas a la programación oficial. ¡Mucha suerte!
            </p>
        </div>

    </div>

    <!-- Footer General -->
    <div style="background-color:#f4f4f4; padding:20px; text-align:center; font-size:12px; color:#999; border-top:1px solid #e0e0e0;">
        <p style="margin:5px 0;">&copy; Multisorteos - Sistema Oficial de Eventos</p>
        <p style="margin:5px 0;">Fecha de orden: {$fecha}</p>
    </div>
</div>
</body>
</html>
HTML;

        $mail->Body = $html;
        $mail->AltBody = "Hola $nombreCliente. Orden para $nombreSorteo confirmada. Boletos: $boletosVisual. Total: $montoVisual";

        try {
            $mail->send();
            writeEmailLog("Envio exitoso a $emailCliente");
            return true;
        } catch (PHPMailerException $e) {
            writeEmailLog("Fallo primer intento (" . implode(',', $attempted) . "): " . $mail->ErrorInfo);

            // Reintento automatico en 587 STARTTLS si el primer intento fue 465 SSL
            if (!$useTls) {
                // Reintento logica simplificada para ahorrar espacio en replace
                $mail->smtpClose();
                $useTls = true;
                $setTransport(PHPMailer::ENCRYPTION_STARTTLS, 587);
                try {
                    $mail->send();
                    writeEmailLog("Reintento Exitoso");
                    return true;
                } catch (Exception $e2) {
                }
            }
            return false;
        }
    } catch (PHPMailerException $e) {
        writeEmailLog("Error PHPMailer inicial: " . $mail->ErrorInfo);
        return false;
    } catch (\Throwable $e) {
        writeEmailLog("Error general: " . $e->getMessage());
        return false;
    }
}
?>
