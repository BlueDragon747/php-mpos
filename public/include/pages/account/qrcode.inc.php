<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if ($user->isAuthenticated()) {
  $smarty->assign("CONTENT", "default.tpl");

  // ----------------------------------------------------------------
  // v2 (Vue/TS) hydration. The legacy template encoded
  // `|<api_url>|<api_key>|<user_id>|` into the QR. We pre-build the
  // payload server-side so the SPA only renders it.
  // ----------------------------------------------------------------
  $manifest_path = $_SERVER['DOCUMENT_ROOT'] . '/v2/dist/.vite/manifest.json';
  $qr_js = '';
  $qr_css = array();
  if (file_exists($manifest_path)) {
    $manifest_raw = @file_get_contents($manifest_path);
    $manifest = $manifest_raw ? json_decode($manifest_raw, true) : null;
    if (is_array($manifest) && isset($manifest['qrcode.html'])) {
      $entry = $manifest['qrcode.html'];
      if (!empty($entry['file'])) $qr_js = '/v2/dist/' . $entry['file'];
      if (!empty($entry['css']) && is_array($entry['css'])) {
        foreach ($entry['css'] as $css) $qr_css[] = '/v2/dist/' . $css;
      }
    }
  }

  $api_disabled = !empty($config['website']['api']['disabled']);

  // Resolve the API URL the QR encodes. Same shape as the legacy
  // template: scheme + host + script_name + ?page=api.
  $scheme = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https' : 'http';
  $host   = isset($_SERVER['SERVER_NAME']) ? (string)$_SERVER['SERVER_NAME'] : '';
  $script = isset($_SERVER['SCRIPT_NAME']) ? (string)$_SERVER['SCRIPT_NAME'] : '/index.php';
  $api_url = $scheme . '://' . $host . $script . '?page=api';

  // User id + api_key. Resolve api_key fresh from the session — the
  // dashboard hydration does a DB re-read; the legacy QR page just
  // uses the session value. Keeping it consistent with the latter.
  $api_key = isset($_SESSION['USERDATA']['api_key']) ? (string)$_SESSION['USERDATA']['api_key'] : '';
  $user_id = isset($_SESSION['USERDATA']['id']) ? (int)$_SESSION['USERDATA']['id'] : 0;

  $qr_initial = array(
    'apiDisabled' => $api_disabled,
    'apiUrl'      => $api_url,
    'apiKey'      => $api_key,
    'userId'      => $user_id,
    // Same payload format the legacy template encoded.
    'payload'     => '|' . $api_url . '|' . $api_key . '|' . $user_id . '|',
  );
  $qr_initial_json = json_encode(
    $qr_initial,
    JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP | JSON_HEX_TAG | JSON_UNESCAPED_UNICODE
  );

  $smarty->assign('QR_JS', $qr_js);
  $smarty->assign('QR_CSS', $qr_css);
  $smarty->assign('QR_INITIAL_JSON', $qr_initial_json);
}
?>
