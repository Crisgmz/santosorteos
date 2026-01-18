<?php
// send.php - Envio HTML con PHPMailer para Sistema de Sorteos
// Responde JSON al fetch() de index.html
header('Content-Type: application/json; charset=utf-8');

// Carga de PHPMailer sin composer: intenta varias rutas conocidas.
$libPaths = [
    __DIR__ . '/../phpmailer/src/',
    __DIR__ . '/../lib/PHPMailer/src/',
    __DIR__ . '/lib/PHPMailer/src/',
    __DIR__ . '/../vendor/phpmailer/phpmailer/src/',
];

$libBase = null;
foreach ($libPaths as $path) {
    if (file_exists($path . 'PHPMailer.php')) {
        $libBase = $path;
        break;
    }
}

if ($libBase) {
    require_once $libBase . 'Exception.php';
    require_once $libBase . 'PHPMailer.php';
    require_once $libBase . 'SMTP.php';
} else {
    http_response_code(500);
    echo json_encode(['error' => 'No se encontro PHPMailer']);
    exit;
}

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

/* =====================  CONFIGURACION  ===================== */
$SMTP_HOST   = 'mail.multisorteos.com';
$SMTP_USER   = 'boletos@multisorteos.com';
$SMTP_PASS   = 'Noviembre0824@';
$FROM_EMAIL  = 'boletos@multisorteos.com';
$FROM_NAME   = 'Sistema de Sorteos';
$TO_EMAIL    = 'boletos@multisorteos.com';

// Usa 465/SSL como indica tu panel.
// Si necesitas 587/TLS, cambia las 2 lineas del bloque SMTP mas abajo.
$USE_SSL_465 = true;
/* =========================================================== */

// Helpers
function e(string $s): string { return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
function nltobr(string $s): string { return nl2br(e($s)); }

try {
  // Leer JSON del frontend
  $raw = file_get_contents('php://input');
  $data = json_decode($raw, true);
  if (!is_array($data)) {
    http_response_code(400);
    echo json_encode(['error' => 'Formato invalido']); exit;
  }

  $nombre   = trim($data['nombre']   ?? '');
  $email    = trim($data['email']    ?? '');
  $telefono = trim($data['telefono'] ?? '');
  $negocio  = trim($data['negocio']  ?? '');
  $mensaje  = trim($data['mensaje']  ?? '');

  if ($nombre === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    http_response_code(400);
    echo json_encode(['error' => 'Nombre y correo validos son obligatorios']); exit;
  }

  // Datos utiles
  $when = date('Y-m-d H:i:s');
  $ip   = $_SERVER['REMOTE_ADDR'] ?? 'N/D';

  // Instanciar PHPMailer
  $mail = new PHPMailer(true);
  $mail->CharSet = 'UTF-8';
  $mail->isSMTP();
  $mail->Host       = $SMTP_HOST;
  $mail->SMTPAuth   = true;
  $mail->Username   = $SMTP_USER;
  $mail->Password   = $SMTP_PASS;

  if ($USE_SSL_465) {
    // 465 SSL
    $mail->SMTPSecure = PHPMailer::ENCRYPTION_SMTPS;
    $mail->Port       = 465;
  } else {
    // 587 STARTTLS
    $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
    $mail->Port       = 587;
  }

  // $mail->SMTPDebug = 0;           // 2 para depurar
  // $mail->Debugoutput = 'error_log';

  $mail->setFrom($FROM_EMAIL, $FROM_NAME);
  $mail->addAddress($TO_EMAIL);
  $mail->addReplyTo($email, $nombre);

  // Logo embebido (opcional)
  $logoCid = null;
  $logoPath = __DIR__ . '/logo.png';
  if (is_file($logoPath)) {
    $logoCid = 'logoimg';
    $mail->addEmbeddedImage($logoPath, $logoCid, 'logo.png');
  }

  // Subject
  $subject = 'Contacto Sistema de Sorteos - ' . ($negocio !== '' ? $negocio : $nombre);

  // Paleta
  $green  = '#32ad40';
  $orange = '#f7941a';
  $dark   = '#32363f';

  // Preheader (texto de vista previa en inbox)
  $preheader = 'Nuevo contacto desde la web de Sistema de Sorteos';

  // HTML con estilos inline (compatibilidad alta)
  $html = '
  <!doctype html>
  <html lang="es">
  <head><meta charset="utf-8"><meta name="color-scheme" content="light">
    <title>'.e($subject).'</title>
  </head>
  <body style="margin:0;padding:0;background:#f5f7fb;">
    <span style="display:none !important;opacity:0;visibility:hidden;height:0;width:0;color:transparent;">'.e($preheader).'</span>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f5f7fb;">
      <tr>
        <td align="center" style="padding:24px 12px;">
          <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:100%;background:#ffffff;border-radius:16px;box-shadow:0 10px 30px rgba(0,0,0,.08);overflow:hidden;border:1px solid #eaeaea;">
            <tr>
              <td align="center" style="padding:22px 22px 8px 22px;">
                '.($logoCid
                  ? '<img src="cid:'.$logoCid.'" alt="Sistema de Sorteos" width="96" style="display:block;border:none;outline:none;text-decoration:none;height:auto;">'
                  : '<div style="font-weight:800;font-size:22px;color:'.$green.'">Sistema de Sorteos</div>').'
              </td>
            </tr>
            <tr>
              <td align="center" style="background:'.$green.';padding:18px 22px;">
                <div style="font-family:Arial,Helvetica,sans-serif;font-size:20px;color:#ffffff;font-weight:700;line-height:1.3;">Nuevo contacto</div>
                '.($negocio !== '' ? '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#eaffef;opacity:.95;margin-top:4px;">'.e($negocio).'</div>' : '').'
              </td>
            </tr>

            <tr>
              <td style="padding:20px 22px 8px 22px;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="font-family:Arial,Helvetica,sans-serif;color:'.$dark.';font-size:15px;">
                  <tr>
                    <td style="padding:10px 0;width:180px;color:#6b7280;">Nombre</td>
                    <td style="padding:10px 0;font-weight:700;">'.e($nombre).'</td>
                  </tr>
                  <tr>
                    <td style="padding:10px 0;color:#6b7280;">Email</td>
                    <td style="padding:10px 0;">
                      <a href="mailto:'.e($email).'" style="color:'.$green.';text-decoration:none;border-bottom:1px dashed '.$green.';">'.e($email).'</a>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:10px 0;color:#6b7280;">Telefono</td>
                    <td style="padding:10px 0;">'.($telefono ? '<a href="tel:'.e($telefono).'" style="color:'.$dark.';text-decoration:none;">'.e($telefono).'</a>' : 'N/D').'</td>
                  </tr>
                  <tr>
                    <td style="padding:10px 0;color:#6b7280;">Negocio</td>
                    <td style="padding:10px 0;">'.($negocio !== '' ? e($negocio) : 'N/D').'</td>
                  </tr>
                  <tr>
                    <td style="padding:10px 0;color:#6b7280;vertical-align:top;">Mensaje</td>
                    <td style="padding:10px 0;">
                      <div style="padding:12px 14px;border-left:4px solid '.$orange.';background:#fff7ef;border-radius:10px;line-height:1.55;">'
                        .($mensaje !== '' ? nltobr($mensaje) : 'N/D').
                      '</div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td align="center" style="padding:4px 22px 18px 22px;">
                <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                  <tr>
                    <td style="padding:8px;">
                      <a href="mailto:'.e($email).'" style="display:inline-block;padding:12px 18px;border:2px solid '.$orange.';border-radius:40px;color:'.$orange.';text-decoration:none;font-family:Arial,Helvetica,sans-serif;font-weight:700;">Responder por email</a>
                    </td>
                    '.($telefono ? '<td style="padding:8px;">
                      <a href="tel:'.e($telefono).'" style="display:inline-block;padding:12px 18px;background:'.$green.';border:2px solid '.$green.';border-radius:40px;color:#fff;text-decoration:none;font-family:Arial,Helvetica,sans-serif;font-weight:700;">Llamar</a>
                    </td>' : '').'
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td style="padding:12px 22px 18px 22px;border-top:1px solid #eeeeee;background:#fcfcfd;">
                <div style="font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#6b7280;line-height:1.5;">
                  Recibido el <strong>'.e($when).'</strong> desde <strong>'.e($ip).'</strong>. - Enviado desde la web de Sistema de Sorteos.
                </div>
              </td>
            </tr>

          </table>

          <div style="font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#98a2b3;margin-top:10px;">
            (c) '.date('Y').' Sistema de Sorteos. Todos los derechos reservados.
          </div>
        </td>
      </tr>
    </table>
  </body>
  </html>';

  // Texto alterno (fallback)
  $text = "Nuevo contacto desde la web de Sistema de Sorteos:\n\n"
        . "Nombre: $nombre\n"
        . "Email: $email\n"
        . "Telefono: ".($telefono ?: 'N/D')."\n"
        . "Negocio: ".($negocio ?: 'N/D')."\n\n"
        . "Mensaje:\n".($mensaje ?: 'N/D')."\n\n"
        . "Recibido: $when - IP: $ip\n- Enviado desde la web de Sistema de Sorteos";

  $mail->Subject = $subject;
  $mail->isHTML(true);
  $mail->Body    = $html;
  $mail->AltBody = $text;

  $mail->send();
  echo json_encode(['ok' => true]);

} catch (Exception $e) {
  http_response_code(500);
  echo json_encode(['error' => 'Error enviando el correo', 'detalle' => $e->getMessage()]);
}
