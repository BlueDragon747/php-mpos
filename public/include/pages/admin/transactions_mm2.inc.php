<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check user to ensure they are admin
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $iLimit = 30;
  empty($_REQUEST['start']) ? $start = 0 : $start = $_REQUEST['start'];
  $aTransactions = $transaction_mm2->getTransactions($start, @$_REQUEST['filter'], $iLimit);
  $aTransactionTypes = $transaction_mm2->getTypes();
  if (!$aTransactions) $_SESSION['POPUP'][] = array('CONTENT' => 'Could not find any transaction', 'TYPE' => 'errormsg');
  $summary_disabled = !empty($setting->getValue('disable_transactionsummary'));
  $aTransactionSummary = !$summary_disabled
    ? $transaction_mm2->getTransactionSummary_mm2()
    : null;

  $tx_v2_action          = 'transactions_mm2';
  $tx_v2_page            = 'admin';
  $tx_v2_show_username   = true;
  $tx_v2_currency        = isset($config['currency_mm2']) ? $config['currency_mm2'] : '';
  $tx_v2_transactions    = $aTransactions;
  $tx_v2_types           = $aTransactionTypes;
  $tx_v2_summary         = $aTransactionSummary;
  $tx_v2_summary_disabled = $summary_disabled;
  $tx_v2_start           = (int)$start;
  $tx_v2_limit           = $iLimit;
  include __DIR__ . '/../account/_transactions_v2.inc.php';
}

$smarty->assign('CONTENT', 'default.tpl');
?>
