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
  $aGetInfo = array('errors' => 'Unable to connect');
  $dBalance = 0;
  $dNewmint = -1;
  
  try {
    if ($bitcoin->can_connect() === true){
      $dBalance = $bitcoin->getbalance();
      $aGetInfo = $bitcoin->getinfo();
      if (is_array($aGetInfo) && array_key_exists('newmint', $aGetInfo)) {
        $dNewmint = $aGetInfo['newmint'];
      }
    } else {
      $_SESSION['POPUP'][] = array('CONTENT' => 'Unable to connect to wallet RPC service', 'TYPE' => 'errormsg');
    }
  } catch (Exception $e) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Wallet RPC Error: ' . $e->getMessage(), 'TYPE' => 'errormsg');
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
  $smarty->assign("BALANCE", $dBalance);
  $smarty->assign("COLDCOINS", $dColdCoins);
  $smarty->assign("LOCKED", $dLockedBalance);
  $smarty->assign("NEWMINT", $dNewmint);
  $smarty->assign("COININFO", $aGetInfo);

  // Tempalte specifics
} else {
  $debug->append('Using cached page', 3);
}

$wallet_ticker = isset($config['currency']) ? $config['currency'] : '';
include __DIR__ . '/_wallet_coin_meta.inc.php';

$smarty->assign("CONTENT", "default.tpl");
?>
