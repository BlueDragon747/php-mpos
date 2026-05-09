<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// twofactor stuff
$cp_editable = $wf_editable = $ea_editable = $wf_sent = $ea_sent = $cp_sent = 0;

// 2fa - set old token so we can use it if an error happens or we need to use post
$oldtoken_ea = (isset($_POST['ea_token']) && $_POST['ea_token'] !== '') ? $_POST['ea_token'] : @$_GET['ea_token'];
$oldtoken_cp = (isset($_POST['cp_token']) && $_POST['cp_token'] !== '') ? $_POST['cp_token'] : @$_GET['cp_token'];
$oldtoken_wf = (isset($_POST['wf_token']) && $_POST['wf_token'] !== '') ? $_POST['wf_token'] : @$_GET['wf_token'];
$updating = (@$_POST['do']) ? 1 : 0;

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
          case 'cashOut':
        	if ($setting->getValue('disable_payouts') == 1 || $setting->getValue('disable_manual_payouts') == 1) {
        	  $_SESSION['POPUP'][] = array('CONTENT' => 'Manual payouts are disabled.', 'TYPE' => 'info');
          } else if (!$user->getCoinAddress($_SESSION['USERDATA']['id'])) {
            $_SESSION['POPUP'][] = array('CONTENT' => 'You have no payout address set.', 'TYPE' => 'errormsg');
        	} else {
        	  $aBalance = $transaction->getBalance($_SESSION['USERDATA']['id']);
        	  $dBalance = $aBalance['confirmed'];
        	  $log->log("info", $_SESSION['USERDATA']['username']." requesting manual payout");
        	  if ($dBalance > $config['txfee_manual']) {
        	    if (!$oPayout->isPayoutActive($_SESSION['USERDATA']['id'])) {
        	      if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
        	        if ($iPayoutId = $oPayout->createPayout($_SESSION['USERDATA']['id'], $oldtoken_wf)) {
        	          $_SESSION['POPUP'][] = array('CONTENT' => 'Created new manual payout request with ID #' . $iPayoutId);
        	        } else {
        	          $_SESSION['POPUP'][] = array('CONTENT' => $iPayoutId->getError(), 'TYPE' => 'errormsg');
        	        }
        	      } else {
        	        $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
        	      }
        	    } else {
        	      $_SESSION['POPUP'][] = array('CONTENT' => 'You already have one active manual payout request.', 'TYPE' => 'errormsg');
        	    }
        	  } else {
        	    $_SESSION['POPUP'][] = array('CONTENT' => 'Insufficient funds, you need more than ' . $config['txfee_manual'] . ' ' . $config['currency'] . ' to cover transaction fees', 'TYPE' => 'errormsg');
        	  }
        	}
        	break;

          case 'cashOut_mm':
        	if ($setting->getValue('disable_payouts') == 1 || $setting->getValue('disable_manual_payouts') == 1) {
        	  $_SESSION['POPUP'][] = array('CONTENT' => 'Manual payouts are disabled.', 'TYPE' => 'info');
          } else if (!$user->getCoinAddress($_SESSION['USERDATA']['id'])) {
            $_SESSION['POPUP'][] = array('CONTENT' => 'You have no payout address set.', 'TYPE' => 'errormsg');
        	} else {
        	  $aBalance = $transaction_mm->getBalance($_SESSION['USERDATA']['id']);
        	  $dBalance = $aBalance['confirmed'];
        	  $log->log("info", $_SESSION['USERDATA']['username']." requesting manual payout");
        	  if ($dBalance > $config['txfee_manual']) {
        	    if (!$oPayout->isPayoutActive_mm($_SESSION['USERDATA']['id'])) {
        	      if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
        	        if ($iPayoutId = $oPayout->createPayout_mm($_SESSION['USERDATA']['id'], $oldtoken_wf)) {
        	          $_SESSION['POPUP'][] = array('CONTENT' => 'Created new manual payout request with ID #' . $iPayoutId);
        	        } else {
        	          $_SESSION['POPUP'][] = array('CONTENT' => $iPayoutId->getError(), 'TYPE' => 'errormsg');
        	        }
        	      } else {
        	        $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
        	      }
        	    } else {
        	      $_SESSION['POPUP'][] = array('CONTENT' => 'You already have one active manual payout request.', 'TYPE' => 'errormsg');
        	    }
        	  } else {
        	    $_SESSION['POPUP'][] = array('CONTENT' => 'Insufficient funds, you need more than ' . $config['txfee_manual'] . ' ' . $config['currency_mm'] . ' to cover transaction fees', 'TYPE' => 'errormsg');
        	  }
        	}
        	break;

          case 'cashOut_mm1':
        	if ($setting->getValue('disable_payouts') == 1 || $setting->getValue('disable_manual_payouts') == 1) {
        	  $_SESSION['POPUP'][] = array('CONTENT' => 'Manual payouts are disabled.', 'TYPE' => 'info');
          } else if (!$user->getCoinAddress($_SESSION['USERDATA']['id'])) {
            $_SESSION['POPUP'][] = array('CONTENT' => 'You have no payout address set.', 'TYPE' => 'errormsg');
        	} else {
        	  $aBalance = $transaction_mm->getBalance($_SESSION['USERDATA']['id']);
        	  $dBalance = $aBalance['confirmed'];
        	  $log->log("info", $_SESSION['USERDATA']['username']." requesting manual payout");
        	  if ($dBalance > $config['txfee_manual']) {
        	    if (!$oPayout->isPayoutActive_mm1($_SESSION['USERDATA']['id'])) {
        	      if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
        	        if ($iPayoutId = $oPayout->createPayout_mm1($_SESSION['USERDATA']['id'], $oldtoken_wf)) {
        	          $_SESSION['POPUP'][] = array('CONTENT' => 'Created new manual payout request with ID #' . $iPayoutId);
        	        } else {
        	          $_SESSION['POPUP'][] = array('CONTENT' => $iPayoutId->getError(), 'TYPE' => 'errormsg');
        	        }
        	      } else {
        	        $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
        	      }
        	    } else {
        	      $_SESSION['POPUP'][] = array('CONTENT' => 'You already have one active manual payout request.', 'TYPE' => 'errormsg');
        	    }
        	  } else {
        	    $_SESSION['POPUP'][] = array('CONTENT' => 'Insufficient funds, you need more than ' . $config['txfee_manual'] . ' ' . $config['currency_mm1'] . ' to cover transaction fees', 'TYPE' => 'errormsg');
        	  }
        	}
        	break;


          case 'cashOut_mm3':
        	if ($setting->getValue('disable_payouts') == 1 || $setting->getValue('disable_manual_payouts') == 1) {
        	  $_SESSION['POPUP'][] = array('CONTENT' => 'Manual payouts are disabled.', 'TYPE' => 'info');
          } else if (!$user->getCoinAddress($_SESSION['USERDATA']['id'])) {
            $_SESSION['POPUP'][] = array('CONTENT' => 'You have no payout address set.', 'TYPE' => 'errormsg');
        	} else {
        	  $aBalance = $transaction_mm->getBalance($_SESSION['USERDATA']['id']);
        	  $dBalance = $aBalance['confirmed'];
        	  $log->log("info", $_SESSION['USERDATA']['username']." requesting manual payout");
        	  if ($dBalance > $config['txfee_manual']) {
        	    if (!$oPayout->isPayoutActive_mm3($_SESSION['USERDATA']['id'])) {
        	      if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
        	        if ($iPayoutId = $oPayout->createPayout_mm3($_SESSION['USERDATA']['id'], $oldtoken_wf)) {
        	          $_SESSION['POPUP'][] = array('CONTENT' => 'Created new manual payout request with ID #' . $iPayoutId);
        	        } else {
        	          $_SESSION['POPUP'][] = array('CONTENT' => $iPayoutId->getError(), 'TYPE' => 'errormsg');
        	        }
        	      } else {
        	        $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
        	      }
        	    } else {
        	      $_SESSION['POPUP'][] = array('CONTENT' => 'You already have one active manual payout request.', 'TYPE' => 'errormsg');
        	    }
        	  } else {
        	    $_SESSION['POPUP'][] = array('CONTENT' => 'Insufficient funds, you need more than ' . $config['txfee_manual'] . ' ' . $config['currency_mm3'] . ' to cover transaction fees', 'TYPE' => 'errormsg');
        	  }
        	}
        	break;

          case 'cashOut_mm4':
        	if ($setting->getValue('disable_payouts') == 1 || $setting->getValue('disable_manual_payouts') == 1) {
        	  $_SESSION['POPUP'][] = array('CONTENT' => 'Manual payouts are disabled.', 'TYPE' => 'info');
          } else if (!$user->getCoinAddress($_SESSION['USERDATA']['id'])) {
            $_SESSION['POPUP'][] = array('CONTENT' => 'You have no payout address set.', 'TYPE' => 'errormsg');
        	} else {
        	  $aBalance = $transaction_mm->getBalance($_SESSION['USERDATA']['id']);
        	  $dBalance = $aBalance['confirmed'];
        	  $log->log("info", $_SESSION['USERDATA']['username']." requesting manual payout");
        	  if ($dBalance > $config['txfee_manual']) {
        	    if (!$oPayout->isPayoutActive_mm4($_SESSION['USERDATA']['id'])) {
        	      if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
        	        if ($iPayoutId = $oPayout->createPayout_mm4($_SESSION['USERDATA']['id'], $oldtoken_wf)) {
        	          $_SESSION['POPUP'][] = array('CONTENT' => 'Created new manual payout request with ID #' . $iPayoutId);
        	        } else {
        	          $_SESSION['POPUP'][] = array('CONTENT' => $iPayoutId->getError(), 'TYPE' => 'errormsg');
        	        }
        	      } else {
        	        $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
        	      }
        	    } else {
        	      $_SESSION['POPUP'][] = array('CONTENT' => 'You already have one active manual payout request.', 'TYPE' => 'errormsg');
        	    }
        	  } else {
        	    $_SESSION['POPUP'][] = array('CONTENT' => 'Insufficient funds, you need more than ' . $config['txfee_manual'] . ' ' . $config['currency_mm4'] . ' to cover transaction fees', 'TYPE' => 'errormsg');
        	  }
        	}
        	break;

          case 'cashOut_mm5':
        	if ($setting->getValue('disable_payouts') == 1 || $setting->getValue('disable_manual_payouts') == 1) {
        	  $_SESSION['POPUP'][] = array('CONTENT' => 'Manual payouts are disabled.', 'TYPE' => 'info');
          } else if (!$user->getCoinAddress($_SESSION['USERDATA']['id'])) {
            $_SESSION['POPUP'][] = array('CONTENT' => 'You have no payout address set.', 'TYPE' => 'errormsg');
        	} else {
        	  $aBalance = $transaction_mm->getBalance($_SESSION['USERDATA']['id']);
        	  $dBalance = $aBalance['confirmed'];
        	  $log->log("info", $_SESSION['USERDATA']['username']." requesting manual payout");
        	  if ($dBalance > $config['txfee_manual']) {
        	    if (!$oPayout->isPayoutActive_mm5($_SESSION['USERDATA']['id'])) {
        	      if (!$config['csrf']['enabled'] || $config['csrf']['enabled'] && $csrftoken->valid) {
        	        if ($iPayoutId = $oPayout->createPayout_mm5($_SESSION['USERDATA']['id'], $oldtoken_wf)) {
        	          $_SESSION['POPUP'][] = array('CONTENT' => 'Created new manual payout request with ID #' . $iPayoutId);
        	        } else {
        	          $_SESSION['POPUP'][] = array('CONTENT' => $iPayoutId->getError(), 'TYPE' => 'errormsg');
        	        }
        	      } else {
        	        $_SESSION['POPUP'][] = array('CONTENT' => $csrftoken->getErrorWithDescriptionHTML(), 'TYPE' => 'info');
        	      }
        	    } else {
        	      $_SESSION['POPUP'][] = array('CONTENT' => 'You already have one active manual payout request.', 'TYPE' => 'errormsg');
        	    }
        	  } else {
        	    $_SESSION['POPUP'][] = array('CONTENT' => 'Insufficient funds, you need more than ' . $config['txfee_manual'] . ' ' . $config['currency_mm5'] . ' to cover transaction fees', 'TYPE' => 'errormsg');
        	  }
        	}
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
  $coins[] = array(
    'key'              => $key,
    'currency'         => $currency,
    'coinName'         => $coin_name,
    'iconUrl'          => $icon_url,
    'address'          => isset($_userdata[$addr_col]) ? (string)$_userdata[$addr_col] : '',
    'threshold'        => isset($_userdata[$thr_col]) ? (float)$_userdata[$thr_col] : 0.0,
    'thresholdMin'     => $thr_min,
    'thresholdMax'     => $thr_max,
    'confirmedBalance' => _ae_balance($tx_obj, $_uid),
    'cashOutEnabled'   => is_object($tx_obj),
    'cashOutAction'    => $cash_action,
    'addressField'     => $addr_field,
    'thresholdField'   => $thr_field,
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
    );
  }
  $_SESSION['POPUP'] = array();
}

$ap_min = isset($config['ap_threshold']['min']) ? (float)$config['ap_threshold']['min'] : 0.0;
$ap_max = isset($config['ap_threshold']['max']) ? (float)$config['ap_threshold']['max'] : 0.0;
$donate_min = isset($config['donate_threshold']['min']) ? (float)$config['donate_threshold']['min'] : 0.0;

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
  'txFeeManual'          => isset($config['txfee_manual']) ? (float)$config['txfee_manual'] : 0.0,
  'manualPayoutsDisabled'=> !empty($config['disable_payouts']) || !empty($config['disable_manual_payouts']),
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
