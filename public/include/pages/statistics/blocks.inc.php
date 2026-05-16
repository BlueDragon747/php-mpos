<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;

// Multi-chain Block listing.
//
// Default view ("ALL") shows blocks from BLC + every active aux slot
// merged into one time-ordered table. A coin dropdown in the Block
// Overview header lets the user filter to a single chain.
//
// What changes per-mode:
//   - "ALL"   : UNION ALL across every active blocks_<slot> table.
//               Pagination is time-based (heights are not comparable
//               across chains). Block Overview totals show parent BLC
//               only — aggregating period totals across chains is
//               TODO; the per-chain getLastBlocksbyTime() helper is
//               not slot-parameterised yet.
//   - <coin>  : only that chain's blocks_<slot> table. Pagination is
//               height-based (the legacy behaviour). Block Overview
//               totals are parent-only too — same TODO.
//
// The Block Shares graph at the top is only meaningful for one chain
// at a time, so it's hidden in ALL mode.

if (!$smarty->isCached('master.tpl', $smarty_cache_key)) {
  $debug->append('No cached version available, fetching from backend', 3);

  // ---- 1) Build the active-slots map: [ticker => slot_suffix] ---------
  // Suffix '' = parent (table=blocks); 'mm' = blocks_mm; etc.
  // Slots whose currency_<slot> starts with 'unused' are skipped.
  $aActiveSlots = array();
  $aActiveSlots[$config['currency']] = '';
  foreach (array('mm','mm1','mm2','mm3','mm4','mm5','mm6') as $s) {
    $tk = isset($config['currency_' . $s]) ? $config['currency_' . $s] : '';
    if ($tk !== '' && stripos($tk, 'unused') === false) {
      $aActiveSlots[$tk] = $s;
    }
  }

  // ---- 2) Coin filter ---------------------------------------------------
  $sSelectedCoin = isset($_REQUEST['coin']) ? strtoupper(trim($_REQUEST['coin'])) : 'ALL';
  if ($sSelectedCoin !== 'ALL' && !isset($aActiveSlots[$sSelectedCoin])) {
    $sSelectedCoin = 'ALL';
  }

  $aQuerySlots = array();
  if ($sSelectedCoin === 'ALL') {
    $aQuerySlots = $aActiveSlots;
  } else {
    $aQuerySlots[$sSelectedCoin] = $aActiveSlots[$sSelectedCoin];
  }

  // ---- 3) Limit + pagination -------------------------------------------
  $iLimit = $setting->getValue('statistics_block_count') ? (int)$setting->getValue('statistics_block_count') : 20;
  if (!empty($_REQUEST['limit']) && is_numeric($_REQUEST['limit'])) {
    $iLimit = min(40, (int)$_REQUEST['limit']);
  }

  // Time-based pagination is always supported (works for ALL and per-coin).
  // Legacy height-based pagination is also accepted in single-coin mode for
  // backward compat with existing pager links.
  $iBefore = (isset($_REQUEST['before']) && is_numeric($_REQUEST['before'])) ? (int)$_REQUEST['before'] : 0;
  $iAfter  = (isset($_REQUEST['after'])  && is_numeric($_REQUEST['after']))  ? (int)$_REQUEST['after']  : 0;

  // ---- 4) Build the UNION query ----------------------------------------
  // Per-chain `chain` (ticker) and `slot` are attached to each row so the
  // template can render a CHAIN column and link to /statistics/round?
  // height=...&slot=... .
  $iTargetBits      = isset($config['target_bits']) ? (int)$config['target_bits'] : 32;
  $iDifficultyConst = isset($config['difficulty'])  ? (int)$config['difficulty']  : 32;

  $aUnions = array();
  foreach ($aQuerySlots as $sTicker => $sSuffix) {
    $sBlocksTbl = 'blocks' . ($sSuffix !== '' ? '_' . $sSuffix : '');
    // Backtick-safe: ticker comes from operator config and is uppercase
    // alphanumeric; suffix is from a fixed allow-list. Still, use string
    // values explicitly to avoid SQL injection from any future config
    // weirdness.
    $sTickerSql = $mysqli->real_escape_string($sTicker);
    // Only list pool-found blocks. Aux daemons receive every block on
    // their public chain via merged-mining-proxy block scanning, so
    // blocks_mm[N] contains both pool-mined and non-pool blocks.
    // Pool-mined blocks have a matching upstream parent share via
    // findblock-mm[N], which sets share_id and account_id. Non-pool
    // blocks stay account_id=NULL.
    //
    // INNER JOIN (not LEFT JOIN) on accounts: some legacy aux blocks
    // have account_id pointing at a since-deleted account (e.g.
    // historical BBTC rows from a prior pool session with
    // account_id=1 but no matching accounts row). LEFT JOIN would
    // surface those as "unknown" finder; INNER JOIN drops them.
    $aUnions[] = "
      SELECT b.id, b.height, b.blockhash, b.confirmations, b.amount, b.difficulty, b.time,
             b.accounted, b.account_id, b.worker_name, b.shares, b.share_id,
             a.username      AS finder,
             a.is_anonymous  AS is_anonymous,
             ROUND((b.difficulty * POW(2, 32 - {$iTargetBits})) / POW(2, ({$iDifficultyConst} - 16)), 0) AS estshares,
             '{$sTickerSql}' AS chain,
             '{$sSuffix}'    AS slot
      FROM {$sBlocksTbl} AS b
      INNER JOIN " . $user->getTableName() . " AS a ON b.account_id = a.id
    ";
  }
  $sUnion = '(' . implode(' UNION ALL ', $aUnions) . ') AS u';

  $aWhereParts = array();
  if ($iBefore) $aWhereParts[] = "u.time < " . (int)$iBefore;
  if ($iAfter)  $aWhereParts[] = "u.time > " . (int)$iAfter;
  $sWhere = empty($aWhereParts) ? '' : ('WHERE ' . implode(' AND ', $aWhereParts));

  // When fetching "Newer" (after=) we sort ASC and reverse afterwards
  // so the page still shows newest-first.
  $bAscFetch = (bool)$iAfter;
  $sSort = $bAscFetch ? 'ASC' : 'DESC';

  // Pull one extra row so we can detect "more available" for the pager.
  $iFetchLimit = $iLimit + 1;
  $sSql = "SELECT * FROM $sUnion $sWhere ORDER BY u.time $sSort LIMIT " . (int)$iFetchLimit;

  $aBlocksFoundData = array();
  if ($oRes = $mysqli->query($sSql)) {
    while ($r = $oRes->fetch_assoc()) $aBlocksFoundData[] = $r;
    $oRes->free();
  }
  if ($bAscFetch) $aBlocksFoundData = array_reverse($aBlocksFoundData);

  $bHasOlder = (count($aBlocksFoundData) > $iLimit);
  if ($bHasOlder) {
    if ($bAscFetch) array_shift($aBlocksFoundData);
    else            array_pop($aBlocksFoundData);
  }
  // Flag for the Newer pager: true if we're paged into history.
  $bHasNewer = ($iBefore || $iAfter);

  // ---- 5) Per-block decorations ----------------------------------------
  $bUseAverage = false;
  if ($config['payout_system'] == 'pplns') {
    foreach ($aBlocksFoundData as $key => $aData) {
      // PPLNS shares are only meaningful for parent blocks in this
      // merge-mined stack. Aux PPLNS draws from the same parent share
      // stream; for aux rows leave it 0 and the template renders a dash.
      if ($aData['slot'] === '') {
        $aBlocksFoundData[$key]['pplns_shares'] = $roundstats->getPPLNSRoundShares($aData['height']);
      } else {
        $aBlocksFoundData[$key]['pplns_shares'] = 0;
      }
      if ($setting->getValue('statistics_show_block_average') && $aData['slot'] === '') {
        $aBlocksFoundData[$key]['block_avg'] = round($block->getAvgBlockShares($aData['height'], $config['pplns']['blockavg']['blockcount']));
        $bUseAverage = true;
      }
    }
  } else if ($config['payout_system'] == 'prop' || $config['payout_system'] == 'pps') {
    if ($setting->getValue('statistics_show_block_average')) {
      foreach ($aBlocksFoundData as $key => $aData) {
        if ($aData['slot'] === '') {
          $aBlocksFoundData[$key]['block_avg'] = round($block->getAvgBlockShares($aData['height'], $config['pplns']['blockavg']['blockcount']));
          $bUseAverage = true;
        } else {
          $aBlocksFoundData[$key]['block_avg'] = 0;
        }
      }
    }
  }

  // ---- 6) Block Overview / supporting data -----------------------------
  $iHours                  = 24;
  $aPoolStatistics         = $statistics->getPoolStatsHours($iHours);
  $iFirstBlockFound        = $statistics->getFirstBlockFound();
  $iTimeSinceFirstBlock    = (time() - $iFirstBlockFound);
  $aFoundBlocksByTime      = $statistics->getLastBlocksbyTime(); // parent only — TODO multi-chain

  // ---- 7) Pager bounds for the template --------------------------------
  $iOlderTime = !empty($aBlocksFoundData) ? (int)$aBlocksFoundData[count($aBlocksFoundData) - 1]['time'] : 0;
  $iNewerTime = !empty($aBlocksFoundData) ? (int)$aBlocksFoundData[0]['time'] : 0;

  // Build the dropdown options: ALL first, then each active ticker in
  // operator-config order (BLC, mm, mm1, mm3, mm4, mm5).
  $aCoinOptions = array_keys($aActiveSlots);

  // ---- 7b) Hide-nav-for-non-admin gate -------------------------------
  // New admin setting (default ON): when enabled, the coin filter and
  // Older/Newer pager render only for admin viewers. Guests and
  // logged-in non-admin users see neither control.
  $bIsAdmin = $user->isAuthenticated(false) && $user->isAdmin($_SESSION['USERDATA']['id']);
  // setting->getValue returns '' for a row that's never been saved.
  // Treat that as the schema default (1 = Hide).
  $sHideNavRaw = $setting->getValue('acl_block_statistics_hide_nav');
  $bHideNavSetting = ($sHideNavRaw === '' || $sHideNavRaw === null) ? 1 : (int)$sHideNavRaw;
  $bBlocksHideNav  = ($bHideNavSetting === 1) && !$bIsAdmin;

  // ---- 8) Smarty assigns ----------------------------------------------
  @$config['cointarget'] ? $smarty->assign("COINGENTIME", $config['cointarget']) : $smarty->assign("COINGENTIME", 150);
  $smarty->assign("FIRSTBLOCKFOUND",  $iTimeSinceFirstBlock);
  $smarty->assign("LASTBLOCKSBYTIME", $aFoundBlocksByTime);
  $smarty->assign("BLOCKSFOUND",      $aBlocksFoundData);
  $smarty->assign("BLOCKLIMIT",       $iLimit);
  $smarty->assign("USEBLOCKAVERAGE",  $bUseAverage);
  $smarty->assign("POOLSTATS",        $aPoolStatistics);

  $smarty->assign("SELECTED_COIN",    $sSelectedCoin);
  $smarty->assign("COIN_OPTIONS",     $aCoinOptions);
  $smarty->assign("PAGER_AT_OLDEST",  !$bHasOlder);
  $smarty->assign("PAGER_AT_NEWEST",  !$bHasNewer);
  $smarty->assign("PAGER_OLDER_TIME", $iOlderTime);
  $smarty->assign("PAGER_NEWER_TIME", $iNewerTime);
  $smarty->assign("BLOCKS_HIDE_NAV",  $bBlocksHideNav);
} else {
  $debug->append('Using cached page', 3);
}

if ($setting->getValue('acl_block_statistics')) {
  $smarty->assign("CONTENT", "default.tpl");
} else if ($user->isAuthenticated()) {
  $smarty->assign("CONTENT", "default.tpl");
}
?>
