
<?php
session_start();
include '../conexion/configv2.php';

// Verificar si el usuario está autenticado
if (!isset($_SESSION['user_id'])) {
    echo "No estás autenticado.";
    exit();
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Sanitización del monto final
    $monto_final = filter_var($_POST['monto_final'], FILTER_SANITIZE_NUMBER_FLOAT, FILTER_FLAG_ALLOW_FRACTION);

    if ($monto_final <= 0) {
        echo "El monto final debe ser un número mayor que cero.";
        exit();
    }

    // Obtener el ID del usuario desde la sesión
    $usuario = $_SESSION['user_id'];

    // Usar una consulta preparada para evitar inyecciones SQL
    $sql = "SELECT cerrar_caja($1, $2) AS resultado"; // Usamos $1 y $2 como parámetros placeholders
    $result = pg_query_params($conn, $sql, array($monto_final, $usuario)); // Asignamos los parámetros

    // Verificar el resultado de la consulta
    if ($row = pg_fetch_assoc($result)) {
        echo $row['resultado'];
    } else {
        echo "Error al cerrar la caja.";
    }
}
?>
