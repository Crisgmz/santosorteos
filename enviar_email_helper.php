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
function enviarBoletoPorEmail(string $emailCliente, string $nombreCliente, string $ticketId, string $rutaPDF): bool
{
    writeEmailLog("Inicio de envio -> $emailCliente (ticket $ticketId)");

    // Configuracion SMTP
    $SMTP_HOST = 'mail.multisorteos.com';
    $SMTP_USER = 'boletos@multisorteos.com';
    $SMTP_PASS = 'Noviembre0824@';
    $FROM_EMAIL = 'boletos@multisorteos.com';
    $FROM_NAME = 'Sistema de Sorteos';
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

        // Adjunto PDF
        if (file_exists($rutaPDF)) {
            $mail->addAttachment($rutaPDF);
            writeEmailLog("PDF adjuntado: $rutaPDF");
        } else {
            writeEmailLog("PDF no encontrado en: $rutaPDF");
        }

        // Asunto y cuerpo
        $mail->Subject = "Tu boleto de sorteo #$ticketId";
        $mail->isHTML(true);

        $safeNombre = htmlspecialchars($nombreCliente, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $html = <<<HTML
<!doctype html>
<html lang="es">
<body style="font-family:Arial, sans-serif; background:#f5f7fb; padding:20px;">
<div style="max-width:600px; margin:0 auto; background:#fff; padding:20px; border-radius:10px; border:1px solid #ddd;">
<h2 style="color:#2c3e50;">Hola {$safeNombre}!</h2>
<p style="font-size:16px; color:#555;">Gracias por tu participacion.</p>
<div style="background:#eaf2f8; padding:15px; border-radius:5px; margin:20px 0;">
<p style="margin:0; font-size:18px; font-weight:bold; color:#2980b9;">Boleto #: {$ticketId}</p>
</div>
<p style="color:#555;">Adjunto encontraras el comprobante oficial de tu boleto.</p>
<hr style="border:0; border-top:1px solid #eee; margin:20px 0;">
<p style="font-size:12px; color:#999;">Sistema de Sorteos Automatico</p>
</div>
</body>
</html>
HTML;

        $mail->Body = $html;
        $mail->AltBody = "Hola $nombreCliente. Tu boleto #$ticketId esta adjunto.";

        try {
            $mail->send();
            writeEmailLog("Envio exitoso a $emailCliente con " . implode(',', $attempted));
            return true;
        } catch (PHPMailerException $e) {
            writeEmailLog("Fallo primer intento (" . implode(',', $attempted) . "): " . $mail->ErrorInfo);

            // Reintento automatico en 587 STARTTLS si el primer intento fue 465 SSL
            if (!$useTls) {
                $mail->smtpClose();
                $mail->clearAttachments();
                $useTls = true;
                $setTransport(PHPMailer::ENCRYPTION_STARTTLS, 587);
                writeEmailLog("Reintentando via STARTTLS 587...");

                // Reagregar adjunto si existia
                if (file_exists($rutaPDF)) {
                    $mail->addAttachment($rutaPDF);
                }

                try {
                    $mail->send();
                    writeEmailLog("Envio exitoso a $emailCliente en reintento STARTTLS");
                    return true;
                } catch (PHPMailerException $e2) {
                    writeEmailLog("Fallo reintento STARTTLS: " . $mail->ErrorInfo);
                    return false;
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