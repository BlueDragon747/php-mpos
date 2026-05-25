<?php
// Router for rootless PHP built-in-server deployments.
//
// PHP's built-in server exposes the bind address (0.0.0.0) as SERVER_NAME.
// MPOS builds several absolute redirects from SERVER_NAME + SERVER_PORT, so
// normalize them to the browser Host header before loading the app.
if (!empty($_SERVER['HTTP_HOST'])) {
    $host = $_SERVER['HTTP_HOST'];
    if ($host[0] === '[' && preg_match('/^\[([^\]]+)\](?::(\d+))?$/', $host, $m)) {
        $_SERVER['SERVER_NAME'] = $m[1];
        if (!empty($m[2])) $_SERVER['SERVER_PORT'] = $m[2];
    } elseif (preg_match('/^([^:]+):(\d+)$/', $host, $m)) {
        $_SERVER['SERVER_NAME'] = $m[1];
        $_SERVER['SERVER_PORT'] = $m[2];
    } else {
        $_SERVER['SERVER_NAME'] = $host;
    }
}

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/';
if (preg_match('#^/(include|templates|sql)(/|$)#', $path)) {
    http_response_code(403);
    return true;
}

$file = __DIR__ . '/web' . $path;
if ($path !== '/' && is_file($file) && !preg_match('/\.php$/i', $file)) {
    return false;
}

require __DIR__ . '/web/index.php';
return true;
