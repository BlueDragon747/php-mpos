<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check user to ensure they are admin
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);
  // Initialize defaults
  $aGetInfo_mm3 = array('errors' => 'Unable to connect');
  $dBalance_mm3 = 0;
  $dNewmint_mm3 = -1;

  try {
    if ($bitcoin_mm3->can_connect() === true){
      $dBalance_mm3 = $bitcoin_mm3->getbalance();
      $aGetInfo_mm3 = $bitcoin_mm3->getinfo();
      if (is_array($aGetInfo_mm3) && array_key_exists('newmint', $aGetInfo_mm3)) {
        $dNewmint_mm3 = $aGetInfo_mm3['newmint'];
      }
    } else {
      $_SESSION['POPUP'][] = array('CONTENT' => 'Unable to connect to wallet RPC service', 'TYPE' => 'errormsg');
    }
  } catch (Exception $e) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Wallet RPC Error: ' . $e->getMessage(), 'TYPE' => 'errormsg');
  }
  // Fetch unconfirmed amount from blocks table
  empty($config['network_confirmations']) ? $confirmations = 120 : $confirmations = $config['network_confirmations'];
  $aBlocksUnconfirmed_mm3 = $block_mm3->getAllUnconfirmed($confirmations);
  $dBlocksUnconfirmedBalance_mm3 = 0;
  if (!empty($aBlocksUnconfirmed_mm3))
    foreach ($aBlocksUnconfirmed_mm3 as $aData) $dBlocksUnconfirmedBalance_mm3 += $aData['amount'];

  // Fetch locked balance from transactions
  $dLockedBalance_mm3 = $transaction_mm3->getLockedBalance();

  // Cold wallet balance
  if (! $dColdCoins = $setting->getValue('wallet_cold_coins')) $dColdCoins = 0;
  $smarty->assign("UNCONFIRMED", $dBlocksUnconfirmedBalance_mm3);
  $smarty->assign("BALANCE", $dBalance_mm3);
  $smarty->assign("COLDCOINS", $dColdCoins);
  $smarty->assign("LOCKED", $dLockedBalance_mm3);
  $smarty->assign("NEWMINT", $dNewmint_mm3);
  $smarty->assign("COININFO", $aGetInfo_mm3);

  // Tempalte specifics
} else {
  $debug->append('Using cached page', 3);
}

$wallet_ticker = isset($config['currency_mm3']) ? $config['currency_mm3'] : '';
include __DIR__ . '/_wallet_coin_meta.inc.php';

$smarty->assign("CONTENT", "default.tpl");
?>
