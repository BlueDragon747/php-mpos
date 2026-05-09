<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if ($user->isAuthenticated()) {
  switch (@$_REQUEST['do']) {
  case 'delete':
    if ($worker->deleteWorker($_SESSION['USERDATA']['id'], $_GET['id'])) {
      $_SESSION['POPUP'][] = array('CONTENT' => 'Worker removed', 'TYPE' => 'success');
    } else {
      $_SESSION['POPUP'][] = array('CONTENT' => $worker->getError(), 'TYPE' => 'errormsg');
    }
    break;
    
  case 'add':
    if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
      if ($worker->addWorker($_SESSION['USERDATA']['id'], $_POST['username'], $_POST['password'])) {
        $_SESSION['POPUP'][] = array('CONTENT' => 'Worker added', 'TYPE' => 'success');
      } else {
        $_SESSION['POPUP'][] = array('CONTENT' => $worker->getError(), 'TYPE' => 'errormsg');
      }
    } else {
      $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
    }
    break;
    
  case 'update':
    if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
      if ($worker->updateWorkers($_SESSION['USERDATA']['id'], @$_POST['data'])) {
        $_SESSION['POPUP'][] = array('CONTENT' => 'Worker updated', 'TYPE' => 'success');
      } else {
        $_SESSION['POPUP'][] = array('CONTENT' => $worker->getError(), 'TYPE' => 'errormsg');
      }
    } else {
      $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
    }
    break;
  }

  $aWorkers = $worker->getWorkers($_SESSION['USERDATA']['id']);

  if (!$aWorkers) $_SESSION['POPUP'][] = array('CONTENT' => 'You have no workers configured', 'TYPE' => 'errormsg');

  $smarty->assign('WORKERS', $aWorkers);

  // ----------------------------------------------------------------
  // v2 (Vue/TS) hydration. The v2 default.tpl mounts the SPA in
  // #app-workers; this assembles the JSON blob it reads at boot.
  // POST handling, CSRF, $worker->updateWorkers/addWorker/deleteWorker
  // above are unchanged — the form posts to the same
  // `?page=account&action=workers` URL, the page reloads, and the
  // controller re-runs and re-hydrates with fresh worker data.
  // ----------------------------------------------------------------

  $manifest_path = $_SERVER['DOCUMENT_ROOT'] . '/v2/dist/.vite/manifest.json';
  $w_js = '';
  $w_css = array();
  if (file_exists($manifest_path)) {
    $manifest_raw = @file_get_contents($manifest_path);
    $manifest = $manifest_raw ? json_decode($manifest_raw, true) : null;
    if (is_array($manifest) && isset($manifest['workers.html'])) {
      $entry = $manifest['workers.html'];
      if (!empty($entry['file']))                          $w_js  = '/v2/dist/' . $entry['file'];
      if (!empty($entry['css']) && is_array($entry['css'])) {
        foreach ($entry['css'] as $css) $w_css[] = '/v2/dist/' . $css;
      }
    }
  }

  $parent_username = isset($_SESSION['USERDATA']['username']) ? (string)$_SESSION['USERDATA']['username'] : '';
  $disable_notifications = !empty($config['disable_notifications']);

  $workers_v2 = array();
  if (is_array($aWorkers)) {
    foreach ($aWorkers as $w) {
      $full = isset($w['username']) ? (string)$w['username'] : '';
      // Worker username convention is `<parent>.<sub>`. The parent prefix
      // is read-only on the form; users only edit the suffix.
      $sub = '';
      if ($full !== '' && strpos($full, '.') !== false) {
        $parts = explode('.', $full, 2);
        $sub = isset($parts[1]) ? $parts[1] : '';
      }
      $workers_v2[] = array(
        'id'         => isset($w['id']) ? (int)$w['id'] : 0,
        'username'   => $full,
        'subname'    => $sub,
        'password'   => isset($w['password']) ? (string)$w['password'] : '',
        'monitor'    => !empty($w['monitor']),
        'hashrate'   => isset($w['hashrate']) ? (float)$w['hashrate'] : 0.0,
        'difficulty' => isset($w['difficulty']) ? (float)$w['difficulty'] : 0.0,
        'shares10m'  => isset($w['count_all']) ? (int)$w['count_all'] : 0,
        'sharesArch' => isset($w['count_all_archive']) ? (int)$w['count_all_archive'] : 0,
        'isActive'   => (isset($w['hashrate']) && $w['hashrate'] > 0),
      );
    }
  }

  $popups = array();
  if (isset($_SESSION['POPUP']) && is_array($_SESSION['POPUP'])) {
    foreach ($_SESSION['POPUP'] as $p) {
      $popups[] = array(
        'content' => isset($p['CONTENT']) ? (string)$p['CONTENT'] : '',
        'type'    => isset($p['TYPE']) ? (string)$p['TYPE'] : 'info',
      );
    }
    $_SESSION['POPUP'] = array();
  }

  $w_initial = array(
    'formAction'           => '?page=account&action=workers',
    'csrfToken'            => (string)($smarty->getTemplateVars('CTOKEN') ?? ''),
    'parentUsername'       => $parent_username,
    'disableNotifications' => $disable_notifications,
    'workers'              => $workers_v2,
    'popups'               => $popups,
  );
  $w_initial_json = json_encode(
    $w_initial,
    JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP | JSON_HEX_TAG | JSON_UNESCAPED_UNICODE
  );

  $smarty->assign('W_JS', $w_js);
  $smarty->assign('W_CSS', $w_css);
  $smarty->assign('W_INITIAL_JSON', $w_initial_json);

  // ----------------------------------------------------------------
  // AJAX path: when the v2 SPA submits a form with _ajax=1 (or hits
  // delete via GET with _ajax=1), short-circuit Smarty and return the
  // updated worker list + popups as JSON so the page doesn't reload.
  // The action handlers above already mutated the DB and pushed
  // pop-ups; the v2 hydration block above re-fetched workers and
  // bundled the popups, so we just emit that JSON and exit.
  // ----------------------------------------------------------------
  if (!empty($_REQUEST['_ajax'])) {
    header('Content-Type: application/json; charset=utf-8');
    echo $w_initial_json;
    exit;
  }
}
$smarty->assign('CONTENT', 'default.tpl');

?>