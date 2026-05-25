<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// twofactor stuff
$cp_editable = $wf_editable = $ea_editable = $wf_sent = $ea_sent = $cp_sent = 0;

// 2fa - set old token so we can use it if an error happens or we need to use post
$oldtoken_ea = (isset($_POST['ea_token']) && $_POST['ea_token'] !== '') ? $_POST['ea_token'] : @$_GET['ea_token'];
$oldtoken_cp = (isset($_POST['cp_token']) && $_POST['cp_token'] !== '') ? $_POST['cp_token'] : @$_GET['cp_token'];
$oldtoken_wf = (isset($_POST['wf_token']) && $_POST['wf_token'] !== '') ? $_POST['wf_token'] : @$_GET['wf_token'];
$updating = (@$_POST['do']) ? 1 : 0;
$_ae_ajax_quote = null;

function _ae_coin_amount_str($amount) {
  return number_format(max(0, (float)$amount), 8, '.', '');
}

function _ae_user_slot_address($uid, $addr_col) {
  global $user;
  $data = $user->getUserData((int)$uid);
  if (!is_array($data) || !isset($data[$addr_col])) return '';
  return trim((string)$data[$addr_col]);
}

function _ae_estimate_wallet_payout_fee($wallet, $address, $amount) {
  $gross = round((float)$amount, 8);
  if ($gross <= 0) throw new Exception('No confirmed balance is available to pay out.');
  if (!is_object($wallet)) throw new Exception('Wallet RPC is not configured for this coin.');

  $outputs = array(array($address => _ae_coin_amount_str($gross)));
  $options = array('subtractFeeFromOutputs' => array(0));
  $quote = $wallet->walletcreatefundedpsbt(array(), $outputs, 0, $options, true);
  if (!is_array($quote) || !isset($quote['fee'])) {
    throw new Exception('Wallet did not return a fee quote.');
  }

  $fee = round((float)$quote['fee'], 8);
  $send = round($gross - $fee, 8);
  if ($fee < 0 || $send <= 0) {
    throw new Exception('Estimated network fee is greater than the payout amount.');
  }

  return array(
    'amount'     => _ae_coin_amount_str($gross),
    'fee'        => _ae_coin_amount_str($fee),
    'sendAmount' => _ae_coin_amount_str($send),
  );
}

function _ae_prepare_cashout($slot_key, $currency, $tx_obj, $wallet, $addr_col, $active_method) {
  global $user, $setting, $config, $csrftoken, $oPayout;

  $uid = isset($_SESSION['USERDATA']['id']) ? (int)$_SESSION['USERDATA']['id'] : 0;
  if ($setting->getValue('disable_payouts') == 1 || $setting->getValue('disable_manual_payouts') == 1) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Manual payouts are disabled.', 'TYPE' => 'info', 'COIN' => $slot_key);
    return false;
  }
  if ($config['csrf']['enabled'] && !$csrftoken->valid) {
    $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info', 'COIN' => $slot_key);
    return false;
  }
  $address = _ae_user_slot_address($uid, $addr_col);
  if ($address === '') {
    $_SESSION['POPUP'][] = array('CONTENT' => 'You have no payout address set.', 'TYPE' => 'errormsg', 'COIN' => $slot_key);
    return false;
  }
  if (!is_object($tx_obj)) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Cash out is not available for this coin.', 'TYPE' => 'errormsg', 'COIN' => $slot_key);
    return false;
  }
  if (method_exists($oPayout, $active_method) && $oPayout->{$active_method}($uid)) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'You already have one active manual payout request.', 'TYPE' => 'errormsg', 'COIN' => $slot_key);
    return false;
  }
  if (!is_object($wallet) || !$wallet->validateaddress($address)) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Wallet rejected your payout address.', 'TYPE' => 'errormsg', 'COIN' => $slot_key);
    return false;
  }

  $balance = $tx_obj->getBalance($uid);
  $confirmed = is_array($balance) && isset($balance['confirmed'])
    ? round((float)$balance['confirmed'], 8)
    : 0.0;
  if ($confirmed <= 0) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'You need a confirmed balance to cash out.', 'TYPE' => 'errormsg', 'COIN' => $slot_key);
    return false;
  }

  try {
    $quote = _ae_estimate_wallet_payout_fee($wallet, $address, $confirmed);
  } catch (Exception $e) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Unable to estimate network fee: ' . $e->getMessage(), 'TYPE' => 'errormsg', 'COIN' => $slot_key);
    return false;
  }

  $quote['coin'] = $slot_key;
  $quote['currency'] = (string)$currency;
  $quote['address'] = $address;
  return $quote;
}

function _ae_quote_cashout($slot_key, $currency, $tx_obj, $wallet, $addr_col, $active_method) {
  global $_ae_ajax_quote;
  $quote = _ae_prepare_cashout($slot_key, $currency, $tx_obj, $wallet, $addr_col, $active_method);
  if ($quote !== false) $_ae_ajax_quote = $quote;
}

function _ae_queue_cashout($slot_key, $currency, $tx_obj, $wallet, $addr_col, $active_method, $create_method, $token) {
  global $oPayout, $log;
  $quote = _ae_prepare_cashout($slot_key, $currency, $tx_obj, $wallet, $addr_col, $active_method);
  if ($quote === false) return;

  $uid = (int)$_SESSION['USERDATA']['id'];
  $log->log("info", $_SESSION['USERDATA']['username']." requesting manual payout");
  if (method_exists($oPayout, $create_method) && $iPayoutId = $oPayout->{$create_method}($uid, $token)) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Created new manual payout request with ID #' . $iPayoutId, 'COIN' => $slot_key, 'TYPE' => 'success');
  } else {
    $_SESSION['POPUP'][] = array('CONTENT' => $oPayout->getError(), 'TYPE' => 'errormsg', 'COIN' => $slot_key);
  }
}

if ($user->isAuthenticated()) {
  if ($config['twofactor']['enabled']) {
    $popupmsg = 'E-mail confirmations are required for ';
    $popuptypes = array();
    if ($config['twofactor']['options']['details'] && $oldtoken_ea !== "") {
      $popuptypes[] = 'editing your details';
      $ea_editable = $user->token->isTokenValid($_SESSION['USERDATA']['id'], $oldtoken_ea, 5);
      $ea_sent = $user->token->doesTokenExist('account_edit', $_SESSION['USERDATA']['id']);
    }
    if ($config['twofactor']['options']['changepw'] && $oldtoken_cp !== "") {
      $popuptypes[] = 'changing your password';
      $cp_editable = $user->token->isTokenValid($_SESSION['USERDATA']['id'], $oldtoken_cp, 6);
      $cp_sent = $user->token->doesTokenExist('change_pw', $_SESSION['USERDATA']['id']);
    }
    if ($config['twofactor']['options']['withdraw'] && $oldtoken_wf !== "") {
      $popuptypes[] = 'withdrawals';
      $wf_editable = $user->token->isTokenValid($_SESSION['USERDATA']['id'], $oldtoken_wf, 7);
      $wf_sent = $user->token->doesTokenExist('withdraw_funds', $_SESSION['USERDATA']['id']);
    }
    
    // get the status of a token if set
    $message_tokensent_invalid = 'A token was sent to your e-mail that will allow you to ';
    $message_tokensent_valid = 'You can currently ';
    $messages_tokensent_status = array(
      'ea' => 'edit your account details',
      'wf' => 'withdraw funds',
      'cp' => 'change your password'
    );
    // build the message we're going to show them for their token(s)
    $eaprep_sent = ($ea_sent) ? $message_tokensent_valid.$messages_tokensent_status['ea'] : "";
    $eaprep_edit = ($ea_editable) ? $message_tokensent_invalid.$messages_tokensent_status['ea'] : "";
    $wfprep_sent = ($wf_sent) ? $message_tokensent_valid.$messages_tokensent_status['wf'] : "";
    $wfprep_edit = ($wf_editable) ? $message_tokensent_invalid.$messages_tokensent_status['wf'] : "";
    $cpprep_sent = ($cp_sent) ? $message_tokensent_valid.$messages_tokensent_status['cp'] : "";
    $cpprep_edit = ($cp_editable) ? $message_tokensent_invalid.$messages_tokensent_status['cp'] : "";
    $ptc = 0;
    $ptcn = count($popuptypes);
    foreach ($popuptypes as $pt) {
      if ($ptcn == 1) { $popupmsg.= $popuptypes[$ptc]; continue; }
      if ($ptc !== ($ptcn-1)) {
        $popupmsg.= $popuptypes[$ptc].', ';
      } else {
        $popupmsg.= 'and '.$popuptypes[$ptc];
      }
      $ptc++;
    }
    // display global notice about tokens being in use and for which bits they're active
    $_SESSION['POPUP'][] = array('CONTENT' => $popupmsg, 'TYPE' => 'info');
  }
  
  if (isset($_POST['do']) && $_POST['do'] == 'genPin') {
    if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
      if ($user->generatePin($_SESSION['USERDATA']['id'], $_POST['currentPassword'])) {
        $_SESSION['POPUP'][] = array('CONTENT' => 'Your PIN # has been sent to your email.', 'TYPE' => 'success');
      } else {
        $_SESSION['POPUP'][] = array('CONTENT' => $user->getError(), 'TYPE' => 'errormsg');
      }
    } else {
      $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
    }
  }
  else {
    if ( @$_POST['do'] && !$user->checkPin($_SESSION['USERDATA']['id'], @$_POST['authPin'])) {
      $_SESSION['POPUP'][] = array('CONTENT' => 'Invalid PIN. ' . ($config['maxfailed']['pin'] - $user->getUserPinFailed($_SESSION['USERDATA']['id'])) . ' attempts remaining.', 'TYPE' => 'errormsg');
    } else {
      if (isset($_POST['unlock']) && isset($_POST['utype'])) {
        $validtypes = array('account_edit','change_pw','withdraw_funds');
        $isvalid = in_array($_POST['utype'],$validtypes);
        if ($isvalid) {
          $ctype = strip_tags($_POST['utype']);
          if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
            $send = $user->sendChangeConfigEmail($ctype, $_SESSION['USERDATA']['id']);
            if ($send) {
              $_SESSION['POPUP'][] = array('CONTENT' => 'A confirmation was sent to your e-mail, follow that link to continue', 'TYPE' => 'success');
            } else {
              $_SESSION['POPUP'][] = array('CONTENT' => $user->getError(), 'TYPE' => 'errormsg');
            }
          } else {
            $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
          }
        }
      } else {
        switch (@$_POST['do']) {
          case 'quoteCashOut':
            _ae_quote_cashout('main', $config['currency'], $transaction, $bitcoin, 'coin_address', 'isPayoutActive');
          break;
          case 'cashOut':
            _ae_queue_cashout('main', $config['currency'], $transaction, $bitcoin, 'coin_address', 'isPayoutActive', 'createPayout', $oldtoken_wf);
          break;

          case 'quoteCashOut_mm':
            _ae_quote_cashout('mm', $config['currency_mm'], $transaction_mm, $bitcoin_mm, 'coin_address_mm', 'isPayoutActive_mm');
          break;
          case 'cashOut_mm':
            _ae_queue_cashout('mm', $config['currency_mm'], $transaction_mm, $bitcoin_mm, 'coin_address_mm', 'isPayoutActive_mm', 'createPayout_mm', $oldtoken_wf);
          break;

          case 'quoteCashOut_mm1':
            _ae_quote_cashout('mm1', $config['currency_mm1'], $transaction_mm1, $bitcoin_mm1, 'coin_address_mm1', 'isPayoutActive_mm1');
          break;
          case 'cashOut_mm1':
            _ae_queue_cashout('mm1', $config['currency_mm1'], $transaction_mm1, $bitcoin_mm1, 'coin_address_mm1', 'isPayoutActive_mm1', 'createPayout_mm1', $oldtoken_wf);
          break;

          case 'quoteCashOut_mm3':
            _ae_quote_cashout('mm3', $config['currency_mm3'], $transaction_mm3, $bitcoin_mm3, 'coin_address_mm3', 'isPayoutActive_mm3');
          break;
          case 'cashOut_mm3':
            _ae_queue_cashout('mm3', $config['currency_mm3'], $transaction_mm3, $bitcoin_mm3, 'coin_address_mm3', 'isPayoutActive_mm3', 'createPayout_mm3', $oldtoken_wf);
          break;

          case 'quoteCashOut_mm4':
            _ae_quote_cashout('mm4', $config['currency_mm4'], $transaction_mm4, $bitcoin_mm4, 'coin_address_mm4', 'isPayoutActive_mm4');
          break;
          case 'cashOut_mm4':
            _ae_queue_cashout('mm4', $config['currency_mm4'], $transaction_mm4, $bitcoin_mm4, 'coin_address_mm4', 'isPayoutActive_mm4', 'createPayout_mm4', $oldtoken_wf);
          break;

          case 'quoteCashOut_mm5':
            _ae_quote_cashout('mm5', $config['currency_mm5'], $transaction_mm5, $bitcoin_mm5, 'coin_address_mm5', 'isPayoutActive_mm5');
          break;
          case 'cashOut_mm5':
            _ae_queue_cashout('mm5', $config['currency_mm5'], $transaction_mm5, $bitcoin_mm5, 'coin_address_mm5', 'isPayoutActive_mm5', 'createPayout_mm5', $oldtoken_wf);
          break;



          case 'updateAccount':
            if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
              if ($user->updateAccount($_SESSION['USERDATA']['id'], $_POST['paymentAddress'] ?? '', $_POST['payoutThreshold'] ?? 0, $_POST['donatePercent'] ?? 0, $_POST['email'] ?? '', $_POST['is_anonymous'] ?? 0, $oldtoken_ea, $_POST['paymentAddress_mm'] ?? '', $_POST['payoutThreshold_mm'] ?? 0, $_POST['paymentAddress_mm1'] ?? '', $_POST['payoutThreshold_mm1'] ?? 0, $_POST['paymentAddress_mm3'] ?? '', $_POST['payoutThreshold_mm3'] ?? 0, $_POST['paymentAddress_mm4'] ?? '', $_POST['payoutThreshold_mm4'] ?? 0, $_POST['paymentAddress_mm5'] ?? '', $_POST['payoutThreshold_mm5'] ?? 0)) {
               $_SESSION['POPUP'][] = array('CONTENT' => 'Account details updated', 'TYPE' => 'success');
              } else {
               $_SESSION['POPUP'][] = array('CONTENT' => 'Failed to update your account: ' . $user->getError(), 'TYPE' => 'errormsg');
              }
            } else {
              $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
            }
          break;

          case 'updatePassword':
            if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
              if ($user->updatePassword($_SESSION['USERDATA']['id'], $_POST['currentPassword'] ?? '', $_POST['newPassword'] ?? '', $_POST['newPassword2'] ?? '', $oldtoken_cp)) {
                $_SESSION['POPUP'][] = array('CONTENT' => 'Password updated', 'TYPE' => 'success');
              } else {
                $_SESSION['POPUP'][] = array('CONTENT' => $user->getError(), 'TYPE' => 'errormsg');
              }
            } else {
              $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
            }
          break;
        }
      }
    }
  }
}

// AJAX short-circuit for cash-out + future inline POST handlers. The
// SPA POSTs the cashOut form with `_ajax=1`; we serve back the
// resulting popups as JSON so the page can update the matching coin
// card in place instead of doing a full reload (which "flashes" and
// resets scroll). Mirrors the pattern in admin/templates.inc.php.
if (!empty($_REQUEST['_ajax']) && @$_POST['do']) {
  $ajax_popups = array();
  if (isset($_SESSION['POPUP']) && is_array($_SESSION['POPUP'])) {
    foreach ($_SESSION['POPUP'] as $p) {
      $ajax_popups[] = array(
        'content' => isset($p['CONTENT']) ? (string)$p['CONTENT'] : '',
        'type'    => isset($p['TYPE']) ? (string)$p['TYPE'] : 'info',
        'coin'    => isset($p['COIN']) ? (string)$p['COIN'] : '',
      );
    }
    $_SESSION['POPUP'] = array();
  }
  header('Content-Type: application/json; charset=utf-8');
  $ajax_response = array('popups' => $ajax_popups);
  if ($_ae_ajax_quote !== null) $ajax_response['quote'] = $_ae_ajax_quote;
  echo json_encode($ajax_response);
  exit;
}


// 2fa - one last time so we can sync with changes we made during this page
if ($config['twofactor']['enabled'] && $user->isAuthenticated()) {
  // set the token to be the old token, just in case an error occured
  $ea_token = (@$oldtoken_ea !== '') ? $oldtoken_ea : @$ea_token;
  $wf_token = (@$oldtoken_wf !== '') ? $oldtoken_wf : @$wf_token;
  $cp_token = (@$oldtoken_cp !== '') ? $oldtoken_cp : @$cp_token;
  if ($config['twofactor']['options']['details'] && $ea_token !== "") {
    $ea_editable = $user->token->isTokenValid($_SESSION['USERDATA']['id'], $ea_token, 5);
    $ea_sent = $user->token->doesTokenExist('account_edit', $_SESSION['USERDATA']['id']);
  }
  if ($config['twofactor']['options']['changepw'] && $cp_token !== "") {
    $cp_editable = $user->token->isTokenValid($_SESSION['USERDATA']['id'], $cp_token, 6);
    $cp_sent = $user->token->doesTokenExist('change_pw', $_SESSION['USERDATA']['id']);
  }
  if ($config['twofactor']['options']['withdraw'] && $wf_token !== "") {
    $wf_editable = $user->token->isTokenValid($_SESSION['USERDATA']['id'], $wf_token, 7);
    $wf_sent = $user->token->doesTokenExist('withdraw_funds', $_SESSION['USERDATA']['id']);
  }
  
  // display token info per each - only when sent and editable or just sent, not by default
  (!empty($eaprep_sent) && !empty($eaprep_edit)) ? $_SESSION['POPUP'][] = array('CONTENT' => $eaprep_sent, 'TYPE' => 'success'):"";
  (!empty($eaprep_sent) && empty($eaprep_edit)) ? $_SESSION['POPUP'][] = array('CONTENT' => $message_tokensent_invalid.$messages_tokensent_status['ea'], 'TYPE' => 'success'):"";
  (!empty($wfprep_sent) && !empty($wfprep_edit)) ? $_SESSION['POPUP'][] = array('CONTENT' => $wfprep_sent, 'TYPE' => 'success'):"";
  (!empty($wfprep_sent) && empty($wfprep_edit)) ? $_SESSION['POPUP'][] = array('CONTENT' => $message_tokensent_invalid.$messages_tokensent_status['wf'], 'TYPE' => 'success'):"";
  (!empty($cpprep_sent) && !empty($cpprep_edit)) ? $_SESSION['POPUP'][] = array('CONTENT' => $cpprep_sent, 'TYPE' => 'success'):"";
  (!empty($cpprep_sent) && empty($cpprep_edit)) ? $_SESSION['POPUP'][] = array('CONTENT' => $message_tokensent_invalid.$messages_tokensent_status['cp'], 'TYPE' => 'success'):"";
  // two-factor stuff
  $smarty->assign("CHANGEPASSUNLOCKED", $cp_editable);
  $smarty->assign("WITHDRAWUNLOCKED", $wf_editable);
  $smarty->assign("DETAILSUNLOCKED", $ea_editable);
  $smarty->assign("CHANGEPASSSENT", $cp_sent);
  $smarty->assign("WITHDRAWSENT", $wf_sent);
  $smarty->assign("DETAILSSENT", $ea_sent);
}

$smarty->assign("DONATE_THRESHOLD", $config['donate_threshold']);

// ---------------------------------------------------------------------
// v2 (Vue/TS) hydration. The v2 default.tpl is a thin wrapper that
// mounts the Vue app in #app-account-edit; everything below assembles
// the single JSON blob the SPA reads at boot. POST handling, CSRF, 2FA
// and User->update*() above are unchanged — the form posts to the same
// `?page=account&action=edit` URL, the page reloads, and the controller
// re-runs and re-hydrates with fresh values + a fresh popup list.
// ---------------------------------------------------------------------

// Vite manifest lookup — same pattern as dashboard.inc.php.
$manifest_path = $_SERVER['DOCUMENT_ROOT'] . '/v2/dist/.vite/manifest.json';
$account_edit_js = '';
$account_edit_css = array();
if (file_exists($manifest_path)) {
  $manifest_raw = @file_get_contents($manifest_path);
  $manifest = $manifest_raw ? json_decode($manifest_raw, true) : null;
  if (is_array($manifest) && isset($manifest['account-edit.html'])) {
    $entry = $manifest['account-edit.html'];
    if (!empty($entry['file']))                          $account_edit_js  = '/v2/dist/' . $entry['file'];
    if (!empty($entry['css']) && is_array($entry['css'])) {
      foreach ($entry['css'] as $css) $account_edit_css[] = '/v2/dist/' . $css;
    }
  }
}

// Pull confirmed balances per coin slot. Cash-out enabled means the
// legacy controller has a do=cashOut_<slot> handler; mm5 used to but
// the legacy code paths cover it, so we include it.
function _ae_balance($tx, $uid) {
  if (!is_object($tx) || !method_exists($tx, 'getBalance')) return 0.0;
  $b = $tx->getBalance($uid);
  return isset($b['confirmed']) ? (float)$b['confirmed'] : 0.0;
}

// Per-slot pending-payout state. Returned as
// ['active' => bool, 'requestedAt' => ISO-ish string|null, 'txid' => string|null].
//   - `active` is true while either:
//      * a payouts_<slot> row with completed=0 exists (the moment after
//        the user clicked Cash Out, before cronjobs-py picks it up), or
//      * a transactions_outbox row exists for this user/slot whose
//        status is 'pending' or 'broadcast'. Failed/abandoned rows and
//        operator-review indeterminate rows are not user-facing pending
//        payouts, so the balance can show again after a failed send.
//      * an unarchived Debit_MP row exists in transactions_<slot>
//        (defensive — covers the gap if outbox row is missing).
//   - `requestedAt` prefers the outbox.created_at (broadcast time); if
//     no outbox row exists yet, falls back to the payouts row time.
//   - `txid` comes from the outbox row, null until cronjobs-py broadcasts.
// Slot key is restricted to a known whitelist so this can't become an
// SQL injection vector.
function _ae_pending_payout($mysqli, $slotKey, $uid) {
  $base = array('active' => false, 'requestedAt' => null, 'txid' => null, 'amount' => null, 'kind' => null);
  $payoutsTable = array(
    'main' => 'payouts',
    'mm'   => 'payouts_mm',
    'mm1'  => 'payouts_mm1',
    'mm3'  => 'payouts_mm3',
    'mm4'  => 'payouts_mm4',
    'mm5'  => 'payouts_mm5',
  );
  $txTable = array(
    'main' => 'transactions',
    'mm'   => 'transactions_mm',
    'mm1'  => 'transactions_mm1',
    'mm3'  => 'transactions_mm3',
    'mm4'  => 'transactions_mm4',
    'mm5'  => 'transactions_mm5',
  );
  $outboxSlot = ($slotKey === 'main') ? '' : $slotKey;   // BLC slot in outbox is ''
  if (!isset($payoutsTable[$slotKey]) || $uid <= 0) return $base;

  // 1) Outbox-backed pending: cronjobs-py is about to broadcast or has
  //    broadcast and is waiting for reconciliation confirmations.
  $sql = "SELECT txid, status, created_at, amount FROM transactions_outbox
          WHERE account_id = ? AND slot = ?
            AND status IN ('pending', 'broadcast')
          ORDER BY id DESC LIMIT 1";
  if ($stmt = $mysqli->prepare($sql)) {
    if ($stmt->bind_param('is', $uid, $outboxSlot) && $stmt->execute()) {
      $stmt->bind_result($otxid, $ostatus, $ocreated, $oamount);
      if ($stmt->fetch()) {
        $base['active']      = true;
        $base['requestedAt'] = (string)$ocreated;
        if ($otxid !== null && $otxid !== '') $base['txid'] = (string)$otxid;
        if ($oamount !== null && $oamount !== '') $base['amount'] = (string)$oamount;
      }
    }
    $stmt->close();
  }
  if ($base['active']) {
    // Look up the kind from the matching debit row in
    // transactions_<slot>: Debit_MP = manual cash-out request,
    // Debit_AP = auto-payout fired by the cronjobs-py threshold job.
    if ($base['txid'] !== null) {
      $sql = "SELECT type FROM " . $txTable[$slotKey]
           . " WHERE account_id = ? AND txid = ? AND type IN ('Debit_MP','Debit_AP')
              ORDER BY id DESC LIMIT 1";
      if ($stmt = $mysqli->prepare($sql)) {
        if ($stmt->bind_param('is', $uid, $base['txid']) && $stmt->execute()) {
          $stmt->bind_result($ttype);
          if ($stmt->fetch()) {
            $base['kind'] = ($ttype === 'Debit_AP') ? 'auto' : 'manual';
          }
        }
        $stmt->close();
      }
    }
    if ($base['kind'] === null) {
      // Indeterminate/pending outbox rows can exist before a Debit row is
      // written, so classify by whether this account still has an open
      // manual payout queue row. Auto-payouts do not use payouts_<slot>.
      $sql = "SELECT 1 FROM " . $payoutsTable[$slotKey]
           . " WHERE completed = 0 AND account_id = ? LIMIT 1";
      if ($stmt = $mysqli->prepare($sql)) {
        if ($stmt->bind_param('i', $uid) && $stmt->execute()) {
          $stmt->store_result();
          $base['kind'] = ($stmt->num_rows > 0) ? 'manual' : 'auto';
        }
        $stmt->close();
      }
    }
    return $base;
  }

  // 2) Pre-broadcast: payouts_<slot> row queued but cronjobs-py
  //    hasn't run yet (so no outbox / no Debit_MP exists). Only
  //    manual cash-outs go through the payouts_<slot> queue —
  //    auto-payouts skip it and write Debit_AP + outbox directly,
  //    so we can hard-code kind='manual' here.
  $sql = "SELECT time FROM " . $payoutsTable[$slotKey]
       . " WHERE completed = 0 AND account_id = ? ORDER BY id DESC LIMIT 1";
  if ($stmt = $mysqli->prepare($sql)) {
    if ($stmt->bind_param('i', $uid) && $stmt->execute()) {
      $stmt->bind_result($ptime);
      if ($stmt->fetch()) {
        $base['active']      = true;
        $base['requestedAt'] = (string)$ptime;
        $base['kind']        = 'manual';
      }
    }
    $stmt->close();
  }
  if ($base['active']) return $base;

  // 3) Defensive: unarchived Debit_MP / Debit_AP without an outbox
  //    row (legacy payouts the cronjobs-py reconciler hasn't touched
  //    yet). Type tells us the kind.
  $sql = "SELECT txid, type FROM " . $txTable[$slotKey]
       . " WHERE account_id = ? AND type IN ('Debit_MP','Debit_AP') AND archived = 0
          ORDER BY id DESC LIMIT 1";
  if ($stmt = $mysqli->prepare($sql)) {
    if ($stmt->bind_param('i', $uid) && $stmt->execute()) {
      $stmt->bind_result($tx, $ttype);
      if ($stmt->fetch()) {
        $base['active'] = true;
        if ($tx !== null && $tx !== '') $base['txid'] = (string)$tx;
        $base['kind']   = ($ttype === 'Debit_AP') ? 'auto' : 'manual';
      }
    }
    $stmt->close();
  }
  return $base;
}
$_uid = isset($_SESSION['USERDATA']['id']) ? (int)$_SESSION['USERDATA']['id'] : 0;
$_userdata = array();
if ($_uid > 0) {
  $_fetched_userdata = $user->getUserData($_uid);
  if (is_array($_fetched_userdata)) {
    $_userdata = $_fetched_userdata;
    $_SESSION['USERDATA'] = isset($_SESSION['USERDATA']) && is_array($_SESSION['USERDATA'])
      ? array_merge($_SESSION['USERDATA'], $_fetched_userdata)
      : $_fetched_userdata;
  }
}
if (empty($_userdata) && isset($_SESSION['USERDATA']) && is_array($_SESSION['USERDATA'])) {
  $_userdata = $_SESSION['USERDATA'];
}

// Per-coin auto-payout threshold ranges (min/max). Keyed by ticker so
// we don't accidentally couple to the slot suffix — easier to extend
// when a new coin lands. Falls back to the global $config['ap_threshold']
// min/max when a coin's ticker isn't in the map (still bounded sanely).
$ae_threshold_ranges = array(
  'BLC'  => array('min' => 1.0,    'max' => 2500.0),
  'PHO'  => array('min' => 1.0,    'max' => 999999.0),
  'BBTC' => array('min' => 1.0,    'max' => 25.0),
  'ELT'  => array('min' => 1.0,    'max' => 1000.0),
  'UMO'  => array('min' => 0.1,    'max' => 9999.0),
  'LIT'  => array('min' => 1.0,    'max' => 9999.0),
);

require_once dirname(__DIR__) . '/admin/_wallet_coin_meta.inc.php';

$coins = array();
foreach (array(
  array('main', 'currency',     isset($transaction)     ? $transaction     : null, 'paymentAddress',     'payoutThreshold',     'cashOut',     'coin_address',     'ap_threshold'),
  array('mm',   'currency_mm',  isset($transaction_mm)  ? $transaction_mm  : null, 'paymentAddress_mm',  'payoutThreshold_mm',  'cashOut_mm',  'coin_address_mm',  'ap_threshold_mm'),
  array('mm1',  'currency_mm1', isset($transaction_mm1) ? $transaction_mm1 : null, 'paymentAddress_mm1', 'payoutThreshold_mm1', 'cashOut_mm1', 'coin_address_mm1', 'ap_threshold_mm1'),
  array('mm3',  'currency_mm3', isset($transaction_mm3) ? $transaction_mm3 : null, 'paymentAddress_mm3', 'payoutThreshold_mm3', 'cashOut_mm3', 'coin_address_mm3', 'ap_threshold_mm3'),
  array('mm4',  'currency_mm4', isset($transaction_mm4) ? $transaction_mm4 : null, 'paymentAddress_mm4', 'payoutThreshold_mm4', 'cashOut_mm4', 'coin_address_mm4', 'ap_threshold_mm4'),
  array('mm5',  'currency_mm5', isset($transaction_mm5) ? $transaction_mm5 : null, 'paymentAddress_mm5', 'payoutThreshold_mm5', 'cashOut_mm5', 'coin_address_mm5', 'ap_threshold_mm5'),
) as $row) {
  list($key, $cfg_key, $tx_obj, $addr_field, $thr_field, $cash_action, $addr_col, $thr_col) = $row;
  $currency = isset($config[$cfg_key]) ? $config[$cfg_key] : '';
  if ($currency === '' && $key !== 'main') continue;   // slot not configured on this pool
  $tk = strtoupper($currency);
  $thr_min = isset($ae_threshold_ranges[$tk]) ? $ae_threshold_ranges[$tk]['min'] : $ap_min;
  $thr_max = isset($ae_threshold_ranges[$tk]) ? $ae_threshold_ranges[$tk]['max'] : $ap_max;
  $coin_name = isset($_wallet_coin_names[$tk]) ? $_wallet_coin_names[$tk] : $currency;
  $icon_url  = _wallet_coin_icon_url($tk);
  $icon_fallback_url = _wallet_coin_icon_fallback_url($tk);
  $coins[] = array(
    'key'              => $key,
    'currency'         => $currency,
    'coinName'         => $coin_name,
    'iconUrl'          => $icon_url,
    'iconFallbackUrl'  => $icon_fallback_url,
    'address'          => isset($_userdata[$addr_col]) ? (string)$_userdata[$addr_col] : '',
    'threshold'        => isset($_userdata[$thr_col]) ? (float)$_userdata[$thr_col] : 0.0,
    'thresholdMin'     => $thr_min,
    'thresholdMax'     => $thr_max,
    'confirmedBalance' => _ae_balance($tx_obj, $_uid),
    'cashOutEnabled'   => is_object($tx_obj),
    'cashOutAction'    => $cash_action,
    'addressField'     => $addr_field,
    'thresholdField'   => $thr_field,
    // SPA flips header to "Pending payout" while one is in flight,
    // then offers a click-through to the body details (requestedAt +
    // txid once the cronjobs-py payouts worker broadcasts).
    'pendingPayout'    => _ae_pending_payout($mysqli, $key, $_uid),
  );
}

$twofactor = array(
  'enabled'           => !empty($config['twofactor']['enabled']),
  'details'           => !empty($config['twofactor']['options']['details']),
  'changepw'          => !empty($config['twofactor']['options']['changepw']),
  'withdraw'          => !empty($config['twofactor']['options']['withdraw']),
  'detailsSent'       => !empty($ea_sent),
  'detailsUnlocked'   => !empty($ea_editable),
  'changepwSent'      => !empty($cp_sent),
  'changepwUnlocked'  => !empty($cp_editable),
  'withdrawSent'      => !empty($wf_sent),
  'withdrawUnlocked'  => !empty($wf_editable),
  'eaToken'           => isset($oldtoken_ea) ? (string)$oldtoken_ea : '',
  'cpToken'           => isset($oldtoken_cp) ? (string)$oldtoken_cp : '',
  'wfToken'           => isset($oldtoken_wf) ? (string)$oldtoken_wf : '',
);

// Pop-ups already accumulated by the POST handlers above + the 2FA block.
// We hand them to the SPA and clear so a hard refresh doesn't re-show.
$popups = array();
if (isset($_SESSION['POPUP']) && is_array($_SESSION['POPUP'])) {
  foreach ($_SESSION['POPUP'] as $p) {
    $popups[] = array(
      'content' => isset($p['CONTENT']) ? (string)$p['CONTENT'] : '',
      'type'    => isset($p['TYPE']) ? (string)$p['TYPE'] : 'info',
      // Per-coin tagging for cash-out success — lets the SPA flip the
      // matching payout card body to show the success message inline
      // instead of routing it to the page-top popup strip.
      'coin'    => isset($p['COIN']) ? (string)$p['COIN'] : '',
    );
  }
  $_SESSION['POPUP'] = array();
}

$ap_min = isset($config['ap_threshold']['min']) ? (float)$config['ap_threshold']['min'] : 0.0;
$ap_max = isset($config['ap_threshold']['max']) ? (float)$config['ap_threshold']['max'] : 0.0;
$donate_min = isset($config['donate_threshold']['min']) ? (float)$config['donate_threshold']['min'] : 0.0;
$manual_payouts_disabled = !empty($config['disable_payouts']) || !empty($config['disable_manual_payouts']);
if (isset($setting) && is_object($setting) && method_exists($setting, 'getValue')) {
  $manual_payouts_disabled =
    ((int)$setting->getValue('disable_payouts') === 1)
    || ((int)$setting->getValue('disable_manual_payouts') === 1);
}

$ae_initial = array(
  'formAction'           => '?page=account&action=edit',
  'username'             => isset($_userdata['username']) ? (string)$_userdata['username'] : '',
  'userId'               => $_uid,
  'apiKey'               => isset($_userdata['api_key']) ? (string)$_userdata['api_key'] : '',
  'apiKeyEnabled'        => empty($config['website']['api']['disabled']),
  'email'                => isset($_userdata['email']) ? (string)$_userdata['email'] : '',
  'isAnonymous'          => !empty($_userdata['is_anonymous']),
  'coins'                => $coins,
  'donatePercent'        => isset($_userdata['donate_percent']) ? (float)$_userdata['donate_percent'] : 0.0,
  'donateThreshold'      => array('min' => $donate_min),
  'apThresholdMin'       => $ap_min,
  'apThresholdMax'       => $ap_max,
  'manualPayoutsDisabled'=> $manual_payouts_disabled,
  // CSRF token. index.php (line ~160) assigns this to Smarty as
  // {$CTOKEN}; we read it back so the SPA's hidden inputs match.
  'csrfToken'            => (string)($smarty->getTemplateVars('CTOKEN') ?? ''),
  'twoFactor'            => $twofactor,
  'popups'               => $popups,
);

// JSON-encode for embedding inside a single-quoted HTML attribute.
// Same escaping flags as dashboard.inc.php's json_encode_attr().
$ae_initial_json = json_encode(
  $ae_initial,
  JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP | JSON_HEX_TAG | JSON_UNESCAPED_UNICODE
);

$smarty->assign('AE_JS', $account_edit_js);
$smarty->assign('AE_CSS', $account_edit_css);
$smarty->assign('AE_INITIAL_JSON', $ae_initial_json);

// Tempalte specifics
$smarty->assign("CONTENT", "default.tpl");
?>
