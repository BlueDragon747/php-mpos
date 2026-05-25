<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check user to ensure they are admin
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}
require_once __DIR__ . '/_daemon_rule_status.inc.php';
$wallet_ticker = isset($config['currency_mm5']) ? $config['currency_mm5'] : '';

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);
  // Initialize defaults
  $aGetInfo_mm5 = array('errors' => 'Unable to connect');
  $dBalance_mm5 = 0;
  $dNewmint_mm5 = -1;

  try {
    if ($bitcoin_mm5->can_connect() === true){
      $dBalance_mm5 = $bitcoin_mm5->getbalance();
      $aGetInfo_mm5 = $bitcoin_mm5->getinfo();
      if (is_array($aGetInfo_mm5) && array_key_exists('newmint', $aGetInfo_mm5)) {
        $dNewmint_mm5 = $aGetInfo_mm5['newmint'];
      }
    } else {
      $_SESSION['POPUP'][] = array('CONTENT' => 'Unable to connect to wallet RPC service', 'TYPE' => 'errormsg');
    }
  } catch (Exception $e) {
    $_SESSION['POPUP'][] = array('CONTENT' => 'Wallet RPC Error: ' . $e->getMessage(), 'TYPE' => 'errormsg');
  }
  // Fetch unconfirmed amount from blocks table
  empty($config['network_confirmations']) ? $confirmations = 120 : $confirmations = $config['network_confirmations'];
  $aBlocksUnconfirmed_mm5 = $block_mm5->getAllUnconfirmed($confirmations);
  $dBlocksUnconfirmedBalance_mm5 = 0;
  if (!empty($aBlocksUnconfirmed_mm5))
    foreach ($aBlocksUnconfirmed_mm5 as $aData) $dBlocksUnconfirmedBalance_mm5 += $aData['amount'];

  // Fetch locked balance from transactions
  $dLockedBalance_mm5 = $transaction_mm5->getLockedBalance();

  // Cold wallet balance
  if (! $dColdCoins = $setting->getValue('wallet_cold_coins')) $dColdCoins = 0;
  $smarty->assign("UNCONFIRMED", $dBlocksUnconfirmedBalance_mm5);
  $smarty->assign("BALANCE", $dBalance_mm5);
  $smarty->assign("COLDCOINS", $dColdCoins);
  $smarty->assign("LOCKED", $dLockedBalance_mm5);
  $smarty->assign("NEWMINT", $dNewmint_mm5);
  $smarty->assign("COININFO", $aGetInfo_mm5);
  $smarty->assign("COIN_RULE_STATUS", bsx_daemon_rule_status($bitcoin_mm5, $aGetInfo_mm5, null, null, $wallet_ticker));

  // Tempalte specifics
} else {
  $debug->append('Using cached page', 3);
}

include __DIR__ . '/_wallet_coin_meta.inc.php';

$smarty->assign("CONTENT", "default.tpl");
?>
