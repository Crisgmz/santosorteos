<?php
// test_native.php
// Prueba de envío usando la función mail() nativa de PHP (sin librerías)

$destinatario = "cristiangomez0517@gmail.com"; // Tu correo
$asunto = "Prueba Nativa PHP - Sin PHPMailer";
$mensaje = "Hola,\n\nSi lees esto, tu servidor PUEDE enviar correos nativamente usando la función mail().\n\nSaludos.";

// Cabeceras básicas
$headers = "From: boletos@multisorteos.com\r\n";
$headers .= "Reply-To: boletos@multisorteos.com\r\n";
$headers .= "X-Mailer: PHP/" . phpversion();

echo "<h1>Prueba de mail() Nativo</h1>";

if (mail($destinatario, $asunto, $mensaje, $headers)) {
    echo "<h2 style='color:green'>✅ Función mail() ejecutada correctamente.</h2>";
    echo "<p>Revisa tu bandeja de entrada (y SPAM) ahora mismo.</p>";
} else {
    echo "<h2 style='color:red'>❌ La función mail() falló.</h2>";
    echo "<p>Tu hosting probablemente tiene deshabilitada esta función o requiere configuración SMTP obligatoria.</p>";
}
?>