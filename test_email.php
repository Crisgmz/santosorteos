<?php
// Script de prueba para verificar el envio de correos
require 'enviar_email_helper.php';

echo "<h1>Prueba de Envio de Email</h1>";
echo "<p>Intentando enviar un correo de prueba...</p>";

// Datos de prueba
$emailDestino = "cristiangomez0517@gmail.com"; // Tu email personal para probar
$nombreDestino = "Cristian Gomez (Prueba)";
$emailDestino = "cristiangomez0517@gmail.com"; // Tu email personal para probar
$nombreDestino = "Cristian Gomez (Prueba)";
$boletos = "2, 3";
$rutaPDF = "boleto_prueba.pdf";
$telefono = "8098618985";
$nombreSorteo = "4RUNNER Off Road 2026";

// Crear un archivo dummy para probar adjunto (opcional)
file_put_contents($rutaPDF, "Contenido de prueba para el boleto PDF");

$resultado = enviarBoletoPorEmail($emailDestino, $nombreDestino, $boletos, $rutaPDF, $telefono, $nombreSorteo);

if ($resultado) {
    echo "<h2 style='color: green;'>Envio Exitoso!</h2>";
    echo "<p>Revisa tu bandeja de entrada (y SPAM) en: <strong>$emailDestino</strong></p>";
} else {
    echo "<h2 style='color: red;'>Error en el envio</h2>";
    echo "<p>Revisa el archivo <strong>email_debug.log</strong> para ver los detalles del error.</p>";
}

echo "<hr>";
echo "<h3>Log de depuracion:</h3>";
if (file_exists('email_debug.log')) {
    echo "<pre>" . file_get_contents('email_debug.log') . "</pre>";
} else {
    echo "No hay log de depuracion disponible.";
}

// Limpiar archivo temporal
if (file_exists($rutaPDF)) {
    unlink($rutaPDF);
}
?>