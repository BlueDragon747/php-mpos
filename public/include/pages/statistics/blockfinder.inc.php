<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Grab Block Finder
if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);

  // Resolve ?coin=<TICKER> → slot suffix. Same shape as the round page
  // so the operator can switch coins via a chip rail in the header.
  // Empty suffix = parent (BLC); unknown / 'unused*' tickers fall back
  // to the parent.
  $sFinderCoin = isset($_REQUEST['coin']) ? strtoupper(trim($_REQUEST['coin'])) : '';
  $aSlotMap = array('' => $config['currency']);
  foreach (array('mm','mm1','mm2','mm3','mm4','mm5','mm6') as $s) {
    $tk = isset($config['currency_' . $s]) ? $config['currency_' . $s] : '';
    if ($tk !== '' && stripos($tk, 'unused') === false) $aSlotMap[$s] = $tk;
  }
  $aTickerToSlot = array_flip($aSlotMap);
  if ($sFinderCoin === '' || !isset($aTickerToSlot[$sFinderCoin])) {
    $sFinderCoin = $config['currency'];
    $sCoinSlot   = '';
  } else {
    $sCoinSlot = $aTickerToSlot[$sFinderCoin];
  }

  // Pick the right Statistics instance for the resolved slot. Each
  // slot has its own subclass that queries blocks_<slot>; the parent
  // hits the unsuffixed `blocks` table.
  $oStats = $statistics;
  if ($sCoinSlot !== '') {
    $sStatsVar = 'statistics_' . $sCoinSlot;
    if (isset($$sStatsVar)) $oStats = $$sStatsVar;
  }

  $getBlocksSolvedbyAccount = $oStats->getBlocksSolvedbyAccount();
  $smarty->assign("BLOCKSSOLVEDBYACCOUNT", $getBlocksSolvedbyAccount);

  if (isset($_SESSION['USERDATA']['id'])) {
    $getBlocksSolvedbyWorker = $oStats->getBlocksSolvedbyWorker($_SESSION['USERDATA']['id']);
    $smarty->assign("BLOCKSSOLVEDBYWORKER", $getBlocksSolvedbyWorker);
  }

  $smarty->assign("ROUND_COIN", $sFinderCoin);
  $smarty->assign("ROUND_COIN_LIST", array_values($aSlotMap));

} else {
  $debug->append('Using cached page', 3);
}

// Public / private page detection
if ($setting->getValue('acl_blockfinder_statistics')) {
  $smarty->assign("CONTENT", "finder.tpl");
} else if ($user->isAuthenticated()) {
  $smarty->assign("CONTENT", "finder.tpl");
} else {
  $smarty->assign("CONTENT", "default.tpl");
}
?>
