<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check user to ensure they are admin
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);
  if ($bitcoin_mm->can_connect() === true){
    $dBalance_mm = $bitcoin_mm->getbalance();
    $aGetInfo_mm = $bitcoin_mm->getinfo();
    if (is_array($aGetInfo_mm) && array_key_exists('newmint', $aGetInfo_mm)) {
      $dNewmint_mm = $aGetInfo_mm['newmint'];
    } else {
      $dNewmint_mm = -1;
    }
  } else {
    $aGetInfo_mm = array('errors' => 'Unable to connect');
    $dBalance_mm = 0;
    $dNewmint_mm = -1;
    $_SESSION['POPUP'][] = array('CONTENT' => 'Unable to connect to wallet RPC service: ' . $bitcoin_mm->can_connect(), 'TYPE' => 'errormsg');
  }
  // Fetch unconfirmed amount from blocks table
  empty($config['network_confirmations']) ? $confirmations = 120 : $confirmations = $config['network_confirmations'];
  $aBlocksUnconfirmed = $block->getAllUnconfirmed($confirmations);
  $dBlocksUnconfirmedBalance = 0;
  if (!empty($aBlocksUnconfirmed))
    foreach ($aBlocksUnconfirmed as $aData) $dBlocksUnconfirmedBalance += $aData['amount'];

  // Fetch locked balance from transactions
  $dLockedBalance = $transaction->getLockedBalance();

  // Cold wallet balance
  if (! $dColdCoins = $setting->getValue('wallet_cold_coins')) $dColdCoins = 0;
  $smarty->assign("UNCONFIRMED", $dBlocksUnconfirmedBalance);
  $smarty->assign("BALANCE", $dBalance_mm);
  $smarty->assign("COLDCOINS", $dColdCoins);
  $smarty->assign("LOCKED", $dLockedBalance);
  $smarty->assign("NEWMINT", $dNewmint_mm);
  $smarty->assign("COININFO", $aGetInfo_mm);

  // Tempalte specifics
} else {
  $debug->append('Using cached page', 3);
}

$smarty->assign("CONTENT", "default.tpl");
?>
