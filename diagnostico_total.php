<?php
// diagnostico_total.php
header('Content-Type: text/html; charset=utf-8');

function check(bool $cond, string $success, string $fail): bool
{
    echo $cond ? "<div style='color:green'>OK: $success</div>" : "<div style='color:red'>ERROR: $fail</div>";
    return $cond;
}

echo "<h1>Diagnostico de Sistema de Correo</h1>";
echo "<hr>";

// 1. Verificar PHP version
echo "<h3>1. Entorno PHP</h3>";
echo "PHP Version: " . phpversion() . "<br>";
check(version_compare(phpversion(), '7.0', '>='), "Version PHP adecuada", "PHP muy antiguo, podria fallar.");

// 2. Verificar Archivos
echo "<h3>2. Archivos criticos</h3>";
check(file_exists(__DIR__ . '/enviar_email_helper.php'), "Helper encontrado", "Falta enviar_email_helper.php");

// 3. Verificar Libreria PHPMailer
echo "<h3>3. Libreria PHPMailer</h3>";
$paths = [
    __DIR__ . '/PHPMailer/src/PHPMailer.php', // <--- Tu carpeta actual
    __DIR__ . '/phpmailer/src/PHPMailer.php',
    __DIR__ . '/lib/PHPMailer/src/PHPMailer.php',
    __DIR__ . '/ejemplo de email/lib/PHPMailer/src/PHPMailer.php',
    __DIR__ . '/vendor/autoload.php',
];

$found = false;
foreach ($paths as $p) {
    if (file_exists($p)) {
        echo "<div style='color:green'>OK: Encontrado en: $p</div>";
        $found = true;
        break;
    }
}
if (!$found) {
    echo "<div style='color:red; font-weight:bold'>ERROR: No se encuentra la libreria PHPMailer en las rutas conocidas.</div>";
}

// 4. Prueba de Conexion SMTP
echo "<h3>4. Prueba de Conexion SMTP</h3>";
if ($found) {
    require 'enviar_email_helper.php';
    echo "Intentando enviar correo de prueba a: cristiangomez0517@gmail.com...<br>";
    $res = enviarBoletoPorEmail('cristiangomez0517@gmail.com', 'Test Diagnostico', 'TEST-DIAG', __FILE__);

    if ($res) {
        echo "<h2 style='color:green'>EXITO: El sistema puede enviar correos.</h2>";
    } else {
        echo "<h2 style='color:red'>FALLO: Error al enviar por SMTP.</h2>";
        echo "Revisa <b>email_debug.log</b> para ver el error exacto.<br>";
        if (file_exists('email_debug.log')) {
            echo "<pre style='background:#eee; padding:10px;'>" . file_get_contents('email_debug.log') . "</pre>";
        } else {
            echo "No se genero archivo de log (posible falta de permisos de escritura).";
        }
    }
} else {
    echo "No se puede probar SMTP porque falta la libreria.";
}
?>