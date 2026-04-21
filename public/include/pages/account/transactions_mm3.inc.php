<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

if ($user->isAuthenticated()) {
  $iLimit = 30;
  empty($_REQUEST['start']) ? $start = 0 : $start = $_REQUEST['start'];
  $aTransactions = $transaction_mm3->getTransactions($start, @$_REQUEST['filter'], $iLimit, $_SESSION['USERDATA']['id']);
  $aTransactionTypes = $transaction_mm3->getTypes();
  if (!$aTransactions) $_SESSION['POPUP'][] = array('CONTENT' => 'Could not find any transaction', 'TYPE' => 'errormsg');
  if (!$setting->getValue('disable_transactionsummary')) {
    $aTransactionSummary_mm3 = $transaction_mm3->getTransactionSummary_mm3($_SESSION['USERDATA']['id']);
    $smarty->assign('SUMMARY_MM3', $aTransactionSummary_mm3);
  }
  $smarty->assign('LIMIT', $iLimit);
  $smarty->assign('TRANSACTIONS', $aTransactions);
  $smarty->assign('TRANSACTIONTYPES', $aTransactionTypes);
  $smarty->assign('TXSTATUS', array('' => '', 'Confirmed' => 'Confirmed', 'Unconfirmed' => 'Unconfirmed', 'Orphan' => 'Orphan'));
  $smarty->assign('DISABLE_TRANSACTIONSUMMARY', $setting->getValue('disable_transactionsummary'));
}
$smarty->assign('CONTENT', 'default.tpl');
?>
