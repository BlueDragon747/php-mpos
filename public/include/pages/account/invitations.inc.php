<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if ($user->isAuthenticated()) {
  $invitations_disabled = !empty($setting->getValue('disable_invitations'));
  if (!$invitations_disabled) {
    $sent_count = (int)$invitation->getCountInvitations($_SESSION['USERDATA']['id']);
    $max_count  = (int)(isset($config['accounts']['invitations']['count']) ? $config['accounts']['invitations']['count'] : 0);
    $limit_hit  = $max_count > 0 && $sent_count >= $max_count;

    if ($limit_hit) {
      $_SESSION['POPUP'][] = array('CONTENT' => 'You have exceeded the allowed invitations of ' . $max_count, 'TYPE' => 'errormsg');
    } else if (isset($_POST['do']) && $_POST['do'] == 'sendInvitation') {
      if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
        if ($invitation->sendInvitation($_SESSION['USERDATA']['id'], $_POST['data'])) {
          $_SESSION['POPUP'][] = array('CONTENT' => 'Invitation sent', 'TYPE' => 'success');
        } else {
          $_SESSION['POPUP'][] = array('CONTENT' => 'Unable to send invitation to recipient: ' . $invitation->getError(), 'TYPE' => 'errormsg');
        }
      } else {
        $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
      }
    }
    $aInvitations = $invitation->getInvitations($_SESSION['USERDATA']['id']);
    $smarty->assign('INVITATIONS', $aInvitations);
  } else {
    $aInvitations = array();
    $sent_count = 0;
    $max_count = 0;
    $limit_hit = false;
    $_SESSION['POPUP'][] = array('CONTENT' => 'Invitations are disabled', 'TYPE' => 'errormsg');
  }

  // ----------------------------------------------------------------
  // v2 (Vue/TS) hydration. Submit posts (form-encoded) back to
  // ?page=account&action=invitations with `do=sendInvitation` +
  // `data[email]` / `data[message]` so $invitation->sendInvitation()
  // accepts the request unchanged.
  // ----------------------------------------------------------------
  $manifest_path = $_SERVER['DOCUMENT_ROOT'] . '/v2/dist/.vite/manifest.json';
  $inv_js = '';
  $inv_css = array();
  if (file_exists($manifest_path)) {
    $manifest_raw = @file_get_contents($manifest_path);
    $manifest = $manifest_raw ? json_decode($manifest_raw, true) : null;
    if (is_array($manifest) && isset($manifest['invitations.html'])) {
      $entry = $manifest['invitations.html'];
      if (!empty($entry['file'])) $inv_js = '/v2/dist/' . $entry['file'];
      if (!empty($entry['css']) && is_array($entry['css'])) {
        foreach ($entry['css'] as $css) $inv_css[] = '/v2/dist/' . $css;
      }
    }
  }

  $invitations_v2 = array();
  if (is_array($aInvitations)) {
    foreach ($aInvitations as $inv) {
      $invitations_v2[] = array(
        'email'       => isset($inv['email']) ? (string)$inv['email'] : '',
        'time'        => isset($inv['time']) ? (string)$inv['time'] : '',
        'isActivated' => !empty($inv['is_activated']),
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

  $inv_initial = array(
    'formAction'         => '?page=account&action=invitations',
    'csrfToken'          => (string)($smarty->getTemplateVars('CTOKEN') ?? ''),
    'invitations'        => $invitations_v2,
    'sentCount'          => (int)$sent_count,
    'maxCount'           => (int)$max_count,
    'limitHit'           => (bool)$limit_hit,
    'invitationsDisabled'=> $invitations_disabled,
    'defaultMessage'     => 'Please accept my invitation to this awesome pool.',
    'popups'             => $popups,
  );
  $inv_initial_json = json_encode(
    $inv_initial,
    JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP | JSON_HEX_TAG | JSON_UNESCAPED_UNICODE
  );

  $smarty->assign('INV_JS', $inv_js);
  $smarty->assign('INV_CSS', $inv_css);
  $smarty->assign('INV_INITIAL_JSON', $inv_initial_json);
}
$smarty->assign('CONTENT', 'default.tpl');
?>
