<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

$smarty->assign("SITESTRATUMURL", $config['gettingstarted']['stratumurl']);
$smarty->assign("SITESTRATUMPORT", $config['gettingstarted']['stratumport']);
$smarty->assign("SITECOINNAME", $config['gettingstarted']['coinname']);
$smarty->assign("SITECOINURL", $config['gettingstarted']['coinurl']);

// Build a flat list of merge-mine coins (primary + active mm slots) so
// the template can surface a clickable name per coin pointing at its
// GitHub releases page. Skips slots whose value starts with "unused"
// (operators use that sentinel for retired mm slots — see
// global.inc.php currency_mm2 / _mm6 today).
require_once(INCLUDE_DIR . '/pages/admin/_wallet_coin_meta.inc.php');
$_gs_slot_keys = array('currency', 'currency_mm', 'currency_mm1', 'currency_mm2',
                       'currency_mm3', 'currency_mm4', 'currency_mm5', 'currency_mm6');
$_gs_seen = array();
$_gs_coins = array();
foreach ($_gs_slot_keys as $_gs_key) {
  if (!isset($config[$_gs_key])) continue;
  $_gs_ticker = (string)$config[$_gs_key];
  if ($_gs_ticker === '' || stripos($_gs_ticker, 'unused') === 0) continue;
  if (isset($_gs_seen[$_gs_ticker])) continue;
  $_gs_seen[$_gs_ticker] = true;
  $_gs_coins[] = array(
    'ticker' => $_gs_ticker,
    'name'   => isset($_wallet_coin_names[$_gs_ticker])
                  ? $_wallet_coin_names[$_gs_ticker]
                  : $_gs_ticker,
    'url'    => isset($_wallet_coin_releases[$_gs_ticker])
                  ? $_wallet_coin_releases[$_gs_ticker]
                  : '',
  );
}
$smarty->assign('MERGEMINE_COINS', $_gs_coins);

// Tempalte specifics
$smarty->assign("CONTENT", "default.tpl");
?>
