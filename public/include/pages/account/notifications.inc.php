<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if ($user->isAuthenticated()) {
  if ($setting->getValue('disable_notifications') == 1) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Notification system disabled by admin.', 'TYPE' => 'info');
    $smarty->assign('CONTENT', 'empty');
  } else {
    if (@$_REQUEST['do'] == 'save') {
      if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
        if ($notification->updateSettings($_SESSION['USERDATA']['id'], $_REQUEST['data'])) {
          $_SESSION['POPUP'][] = array('CONTENT' => 'Updated notification settings', 'TYPE' => 'success');
        } else {
          $_SESSION['POPUP'][] = array('CONTENT' => $notification->getError(), 'TYPE' => 'errormsg');
        }
      } else {
        $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
      }
    }

    // Fetch notifications + per-user settings.
    $aNotifications = $notification->getNofifications($_SESSION['USERDATA']['id']);
    $aSettings = $notification->getNotificationSettings($_SESSION['USERDATA']['id']);

    $smarty->assign('NOTIFICATIONS', $aNotifications);
    $smarty->assign('SETTINGS', $aSettings);
    $smarty->assign('CONTENT', 'default.tpl');

    // ----------------------------------------------------------------
    // v2 (Vue/TS) hydration. The settings form posts back here with
    // `do=save` + `data[<type>]=1` for each enabled toggle (legacy
    // contract — see $notification->updateSettings()). On success the
    // page reloads with a "Updated notification settings" popup.
    // ----------------------------------------------------------------
    $manifest_path = $_SERVER['DOCUMENT_ROOT'] . '/v2/dist/.vite/manifest.json';
    $n_js = '';
    $n_css = array();
    if (file_exists($manifest_path)) {
      $manifest_raw = @file_get_contents($manifest_path);
      $manifest = $manifest_raw ? json_decode($manifest_raw, true) : null;
      if (is_array($manifest) && isset($manifest['notifications.html'])) {
        $entry = $manifest['notifications.html'];
        if (!empty($entry['file'])) $n_js = '/v2/dist/' . $entry['file'];
        if (!empty($entry['css']) && is_array($entry['css'])) {
          foreach ($entry['css'] as $css) $n_css[] = '/v2/dist/' . $css;
        }
      }
    }

    // Five notification types the cron actually supports — see
    // $notification->sendNotification($id, $strType, …) call sites.
    $type_meta = array(
      'new_block'      => 'New Block',
      'auto_payout'    => 'Auto Payout',
      'idle_worker'    => 'Idle Worker',
      'manual_payout'  => 'Manual Payout',
      'success_login'  => 'Successful Login',
    );

    $settings_v2 = array();
    foreach ($type_meta as $type => $label) {
      $active = (is_array($aSettings) && isset($aSettings[$type])) ? (int)$aSettings[$type] : 0;
      $settings_v2[] = array(
        'type'   => $type,
        'label'  => $label,
        'active' => $active === 1,
      );
    }

    $history_v2 = array();
    if (is_array($aNotifications)) {
      foreach ($aNotifications as $n) {
        $type = isset($n['type']) ? (string)$n['type'] : '';
        $history_v2[] = array(
          'id'       => isset($n['id']) ? (int)$n['id'] : 0,
          'time'     => isset($n['time']) ? (string)$n['time'] : '',
          'type'     => $type,
          'label'    => isset($type_meta[$type]) ? $type_meta[$type] : $type,
          'active'   => !empty($n['active']),
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

    $n_initial = array(
      'formAction'  => '?page=account&action=notifications',
      'csrfToken'   => (string)($smarty->getTemplateVars('CTOKEN') ?? ''),
      'settings'    => $settings_v2,
      'history'     => $history_v2,
      'popups'      => $popups,
    );
    $n_initial_json = json_encode(
      $n_initial,
      JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP | JSON_HEX_TAG | JSON_UNESCAPED_UNICODE
    );

    $smarty->assign('N_JS', $n_js);
    $smarty->assign('N_CSS', $n_css);
    $smarty->assign('N_INITIAL_JSON', $n_initial_json);
  }
}

?>
