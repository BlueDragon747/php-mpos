<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Check user to ensure they are admin
if (!$user->isAuthenticated() || !$user->isAdmin($_SESSION['USERDATA']['id'])) {
  header("HTTP/1.1 404 Page not found");
  die("404 Page not found");
}

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $iLimit = 30;
  $debug->append('No cached version available, fetching from backend', 3);
  empty($_REQUEST['start']) ? $start = 0 : $start = max(0, (int)$_REQUEST['start']);

  $coin_names = array(
    'BLC'  => isset($config['gettingstarted']['coinname']) ? (string)$config['gettingstarted']['coinname'] : 'Blakecoin',
    'PHO'  => 'Photon',
    'BBTC' => 'BlakeBitcoin',
    'LIT'  => 'Lithium',
    'ELT'  => 'Electron',
    'UMO'  => 'Universalmolecule',
  );
  $slot_defs = array(
    array('slot' => '',    'currency_key' => 'currency',     'tx' => isset($transaction)     ? $transaction     : null, 'summary' => 'getTransactionSummary'),
    array('slot' => 'mm',  'currency_key' => 'currency_mm',  'tx' => isset($transaction_mm)  ? $transaction_mm  : null, 'summary' => 'getTransactionSummary_mm'),
    array('slot' => 'mm1', 'currency_key' => 'currency_mm1', 'tx' => isset($transaction_mm1) ? $transaction_mm1 : null, 'summary' => 'getTransactionSummary_mm1'),
    array('slot' => 'mm2', 'currency_key' => 'currency_mm2', 'tx' => isset($transaction_mm2) ? $transaction_mm2 : null, 'summary' => 'getTransactionSummary_mm2'),
    array('slot' => 'mm3', 'currency_key' => 'currency_mm3', 'tx' => isset($transaction_mm3) ? $transaction_mm3 : null, 'summary' => 'getTransactionSummary_mm3'),
    array('slot' => 'mm4', 'currency_key' => 'currency_mm4', 'tx' => isset($transaction_mm4) ? $transaction_mm4 : null, 'summary' => 'getTransactionSummary_mm4'),
    array('slot' => 'mm5', 'currency_key' => 'currency_mm5', 'tx' => isset($transaction_mm5) ? $transaction_mm5 : null, 'summary' => 'getTransactionSummary_mm5'),
    array('slot' => 'mm6', 'currency_key' => 'currency_mm6', 'tx' => isset($transaction_mm6) ? $transaction_mm6 : null, 'summary' => 'getTransactionSummary_mm6'),
  );
  $tx_slots = array();
  foreach ($slot_defs as $def) {
    $currency = isset($config[$def['currency_key']]) ? trim((string)$config[$def['currency_key']]) : '';
    if ($currency === '' || stripos($currency, 'unused') !== false || !$def['tx']) continue;
    $ticker = strtoupper($currency);
    $value = strtolower($ticker);
    $tx_slots[$value] = array(
      'slot'        => $def['slot'],
      'currency'    => $ticker,
      'coin_name'   => isset($coin_names[$ticker]) ? $coin_names[$ticker] : $ticker,
      'transaction' => $def['tx'],
      'summary'     => $def['summary'],
      'aliases'     => array($value, strtolower($def['slot']), $def['slot'] === '' ? 'blc' : ''),
    );
  }

  $selected_key = '';
  $requested_coin = isset($_REQUEST['coin']) ? strtolower(trim((string)$_REQUEST['coin'])) : '';
  foreach ($tx_slots as $key => $slot) {
    if ($selected_key === '') $selected_key = $key;
    if ($requested_coin !== '' && in_array($requested_coin, $slot['aliases'], true)) {
      $selected_key = $key;
      break;
    }
  }
  if ($selected_key === '' || !isset($tx_slots[$selected_key])) {
    header("HTTP/1.1 404 Page not found");
    die("404 Page not found");
  }
  $selected_slot = $tx_slots[$selected_key];

  $aTransactions = $selected_slot['transaction']->getTransactions($start, @$_REQUEST['filter'], $iLimit);
  $aTransactionTypes = $selected_slot['transaction']->getTypes();
  if (!$aTransactions) $_SESSION['POPUP'][] = array('CONTENT' => 'Could not find any transaction', 'TYPE' => 'errormsg');
  $summary_disabled = !empty($setting->getValue('disable_transactionsummary'));
  $aTransactionSummary = null;
  if (!$summary_disabled && method_exists($selected_slot['transaction'], $selected_slot['summary'])) {
    $aTransactionSummary = $selected_slot['transaction']->{$selected_slot['summary']}();
  }

  $tx_v2_coin_options = array();
  foreach ($tx_slots as $key => $slot) {
    $tx_v2_coin_options[] = array(
      'value'    => $key,
      'currency' => $slot['currency'],
      'name'     => $slot['coin_name'],
      'label'    => $slot['coin_name'],
    );
  }

  // Hand off to the shared v2 hydration helper. Same helper user-side
  // uses; flagged with $tx_v2_page = 'admin' + $tx_v2_show_username
  // = true so the SPA points its form back to ?page=admin&action=…
  // and renders the Username column.
  $tx_v2_action          = 'transactions';
  $tx_v2_form_action     = '?page=admin&action=transactions&coin=' . rawurlencode($selected_key);
  $tx_v2_page            = 'admin';
  $tx_v2_show_username   = true;
  $tx_v2_currency        = $selected_slot['currency'];
  $tx_v2_selected_coin   = $selected_key;
  $tx_v2_transactions    = $aTransactions;
  $tx_v2_types           = $aTransactionTypes;
  $tx_v2_summary         = $aTransactionSummary;
  $tx_v2_summary_disabled = $summary_disabled;
  $tx_v2_start           = (int)$start;
  $tx_v2_limit           = $iLimit;
  include __DIR__ . '/../account/_transactions_v2.inc.php';
} else {
  $debug->append('Using cached page', 3);
}

$smarty->assign('CONTENT', 'default.tpl');
?>
